[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Reference,

    [Parameter(Position=1)]
    [string]$Lossy,

    [Alias("h")]
    [switch]$Help
)

function Show-Help {
    Write-Host "----------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "                            2FSIQA" -ForegroundColor White
    Write-Host "   Usage:"
    Write-Host "   2FSIQA reference.png distorted.png"
    Write-Host "   Recommended inputs: 16 bit png in same color space"
	Write-Host "   Use '-verbose' for debug or to check raw metrics"
    Write-Host "----------------------------------------------------------------" -ForegroundColor Cyan
    exit 0
}

if ($Help) {
    Show-Help
}

if ([string]::IsNullOrWhiteSpace($Reference) -or [string]::IsNullOrWhiteSpace($Lossy)) {
    Write-Host "Error: You must provide both a reference and a lossy file." -ForegroundColor Red
    Show-Help
}

if (-not (Test-Path $Reference)) { 
    Write-Error "Reference file not found: $Reference"
    exit 1 
}

if (-not (Test-Path $Lossy)) { 
    Write-Error "Lossy file not found: $Lossy"
    exit 1 
}

function Get-QualityMetric {
    param (
        [Parameter(Mandatory)][string]$Lossy,
        [Parameter(Mandatory)][string]$Reference,
        [Parameter(Mandatory)][string]$Metric
    )

    switch ($Metric) {
        { $_ -in "VMAF", "SSIM", "PSNR" } {
            $filter = switch ($Metric) {
                "VMAF" { "libvmaf" }
                "SSIM" { "ssim" }
                "PSNR" { "psnr" }
            }

            $output = & "ffmpeg" -hide_banner -i "$Lossy" -i "$Reference" -lavfi $filter -f null - 2>&1
            
            switch ($Metric) {
                "VMAF" {
                    $match = $output | Select-String 'VMAF score:\s*([\d.]+)'
                    if ($match) { return [decimal]$match.Matches.Groups[1].Value }
                }
                "SSIM" {
                    $match = $output | Select-String 'All:\s*([\d.]+)'
                    if ($match) { return [decimal]$match.Matches.Groups[1].Value }
                }
                "PSNR" {
                    $match = $output | Select-String 'average:\s*(inf|[\d.]+)'
                    if ($match) {
                        $value = $match.Matches.Groups[1].Value
                        if ($value -eq "inf") {
                            return 108
                        } else {
                            return [decimal]$value
                        }
                    }
                }
            }
        }
        
        "DSSIM" {
            $output = & "dssim" "$Reference" "$Lossy" 2>&1
            $match = $output | Select-String '^\s*([\d.]+)'
            if ($match) { return [decimal]$match.Matches.Groups[1].Value }
        }
        
        "BUTTERAUGLI" {
            $output = & "butteraugli_main" "$Reference" "$Lossy" 2>&1
            $match = $output | Select-String '3-norm:\s*([\d.]+)'
            if ($match) { return [decimal]$match.Matches.Groups[1].Value }
        }
		
        "SSIMULACRA2" {
            $output = & "ssimulacra2" "$Reference" "$Lossy" 2>&1
            $value = $output | Select-String '^(\d+\.\d+|\d+)'
            if ($value) { return [decimal]$value.Matches.Groups[1].Value }
        }
    }
    
    return $null
}
function Compute-2FSIQA {
    param(
        [hashtable]$Metrics,
        [decimal]$Gamma = 3.14159265359
    )
    
    $LOWER_IS_BETTER = @("dssim", "butteraugli")
    
    $METRIC_WEIGHT = @{
        "ssimulacra2" = 0.2545
        "dssim"       = 0.2212
        "vmaf"        = 0.1582
        "ssim"        = 0.1492
        "butteraugli" = 0.1441
        "psnr"        = 0.0728
    }
    
    $METRIC_BEST = @{
        "ssimulacra2" = 100.0
        "dssim"       = 0.0
        "vmaf"        = 97.42632
        "ssim"        = 1.0
        "butteraugli" = 0.0
        "psnr"        = 108.0
    }
    
    $METRIC_WORST = @{
        "ssimulacra2" = 0.0
        "dssim"       = 0.286928710964912280701754386
        "vmaf"        = 3.0809662850877192982456140351
        "ssim"        = 0.5746939736842105263157894737
        "butteraugli" = 24.640694285087719298245614035
        "psnr"        = 17.279693267543859649122807018
    }
    
    if ($Metrics.Count -eq 0) {
        return $null
    }
    
    $availableMetrics = @()
    foreach ($key in $Metrics.Keys) {
        $lowerKey = $key.ToLower()
        if ($METRIC_WEIGHT.ContainsKey($lowerKey) -and $Metrics[$key] -ne $null) {
            $availableMetrics += $lowerKey
        }
    }
    
    $totalWeight = 0.0
    foreach ($metric in $availableMetrics) {
        $totalWeight += $METRIC_WEIGHT[$metric]
    }
    
    if ($totalWeight -eq 0) {
        return $null
    }
    
    $qualityScore = 0.0
    
    foreach ($metric in $availableMetrics) {
        $value = $Metrics[$metric]
        $bestValue = $METRIC_BEST[$metric]
        $worstValue = $METRIC_WORST[$metric]
        $rangeVal = [Math]::Abs($bestValue - $worstValue)
        
        if ($rangeVal -eq 0) {
            continue
        }
        
        $minVal = [Math]::Min($bestValue, $worstValue)
        $maxVal = [Math]::Max($bestValue, $worstValue)
        if ($value -lt $minVal) { $value = $minVal }
        if ($value -gt $maxVal) { $value = $maxVal }
        
        if ($LOWER_IS_BETTER -contains $metric) {
            $norm = ($worstValue - $value) / $rangeVal
        } else {
            $norm = ($value - $worstValue) / $rangeVal
        }
        
        $norm = ([Math]::Exp($Gamma * $norm) - 1) / ([Math]::Exp($Gamma) - 1)
        
        $weight = $METRIC_WEIGHT[$metric] / $totalWeight
        $qualityScore += $norm * $weight
    }
    
    return $qualityScore
}
$metrics = @("VMAF", "SSIM", "PSNR", "DSSIM", "BUTTERAUGLI", "SSIMULACRA2")
$collectedMetrics = @{}
$metrics | ForEach-Object {
    $value = Get-QualityMetric -Lossy $lossy -Reference $reference -Metric $_
    $collectedMetrics[$_.ToLower()] = $value
}
$qualityScore = Compute-2FSIQA -Metrics $collectedMetrics
if ($null -ne $qualityScore) {
    Write-Output "2FSIQA = $qualityScore" 
} else {
    Write-Output "Could not compute (insufficient data)"
}
Write-Verbose "`n--- Detailed Metrics ---"

$collectedMetrics.GetEnumerator() | Sort-Object Name | ForEach-Object {
    $displayName = $_.Name.ToUpper()
    
    if ($null -ne $_.Value) {
        Write-Verbose "$displayName = $($_.Value)"
    } else {
        Write-Verbose "$displayName = Not found"
    }
}

