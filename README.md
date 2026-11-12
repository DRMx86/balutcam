# BalutCam

Film-look photo and video camera for iOS 16+ (SwiftUI, AVFoundation, Core Image, Metal).

## Features
- Live camera preview with the look applied in real time; video is recorded already graded, photos are graded at full resolution
- Film presets inspired by classic Kodak-style stocks (approximations built from the sliders, not official profiles) plus your own saved presets (JSON in Application Support)
- 3D `.cube` LUT support with an intensity slider
- Pick any photo or video from the camera roll, adjust live, and save it as a **new** file (the original is untouched)
- Sliders: exposure, contrast, highlights, shadows, fade, saturation, warmth, tint, grain amount/size, halation, bloom, sharpness, vignette amount/size/feather
- VHS controls (color bleed, scanlines, tape noise, softness) and four VHS presets
- Every preset starts with grain at 0; raise it in the Film tab
- Output formats: Full, 1:1 (1080x1080), 4:5 (1080x1350 feed), 9:16 (1080x1920 Reels/Stories) and 16:9 (1920x1080) when held sideways. Applies to camera photos/video and to the editor
- Video frame rate: 23.976, 24, 25, 29.97 or 30 fps
- Portrait and landscape layouts; front camera is always mirrored
- All settings (look, preset, LUT, format, frame rate, mode, camera, panel state) are remembered between launches

## LUTs
Drop `.cube` files into **Files → On My iPhone → BalutCam → LUTs** (or use Import in the LUT tab), then tap Rescan. Two sample LUTs are copied there on first launch (source: `LUTs/`). Only 3D LUTs are supported; use display-referred (Rec.709) LUTs.

## Layout
```
BalutCam/Engine   look parameters, presets, .cube parser, LUT library, Core Image film pipeline, media export
BalutCam/Camera   AVFoundation capture + Metal preview
BalutCam/UI       camera screen, editor screen, shared controls
LUTs/             sample LUTs (bundled)
project.yml       XcodeGen spec (the .xcodeproj is generated, not committed)
```

## Build
GitHub Actions (`.github/workflows/ios-build.yml`) runs XcodeGen, builds for device unsigned, and uploads `BalutCam-unsigned-ipa`. Install it with AltStore/Sideloadly (they re-sign with your Apple ID). TestFlight/App Store needs a paid developer account and signing secrets.

Local: `brew install xcodegen && xcodegen generate && open BalutCam.xcodeproj`.
EOF
