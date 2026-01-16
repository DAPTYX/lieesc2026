# 2FSIQA

## What is it
2FSIQA is a metric that estimates the similarity between two input images and produces a score ranging from 0 (not similar) to 1 (identical). It works by combining multiple established Image Quality Assessment (IQA) metrics into a single composite score.

The score is calculated by rescaling the following metrics, applying a nonlinear gamma transformation, and combining them with weighted averages:

- SSIMULACRA2 (25.45%)
- Kornelski's DSSIM (22.12%)
- VMAF (15.82%)
- FFmpeg's SSIM (14.92%)
- Butteraugli (14.41%)
- PSNR (7.28%)

These weights are based on the "Metric performance" section benchmark results in the [SSIMULACRA2 GitHub README](https://github.com/cloudinary/ssimulacra2).

For each metric, the raw value is clamped to predefined "best" and "worst" bounds based on empirical testing.

Refer to [example implementation](scripts/2FSIQA.ps1) for details.


## Example implementation for Windows

### How to try it:
If you're interested in trying it out, there is a PowerShell CLI script tool that includes all the necessary requirements in the archive: https://github.com/DAPTYX/lieesc2026/releases

Alternatively, use [this version](scripts/2FSIQA.ps1) if you already have the requirements installed.

### Usage:
`2FSIQA reference.png distorted.png`  
Add `-verbose` for debug output or to view the raw individual metrics.

### Requirements and Tested Versions:
- [DSSIM](https://github.com/kornelski/dssim), version [3.4.0](https://github.com/kornelski/dssim/releases/tag/3.4.0)
- [FFmpeg](https://ffmpeg.org/) for VMAF, SSIM, and PSNR. Version used: [Windows builds by BtbN](https://github.com/BtbN/FFmpeg-Builds/releases/tag/autobuild-2025-11-30-12-53)
- From the libjxl package: `butteraugli_main` and `ssimulacra2` [build from November 24, 2025](https://artifacts.lucaversari.it/libjxl/libjxl/2025-11-24T11%3A20%3A07Z_65ee3ee7dd640bbcfcfef676f242bcccc687dcd7/)

You can use other versions or implementations of the same metrics for experimentation or implementation purposes. These specific versions are only intended to establish a reproducible reference.
