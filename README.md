# BalutCam

BalutCam is an iOS app scaffold for a LUT-based film camera experience. It includes:

- Photo and video capture modes
- Kodak-inspired film looks and LUT intensity controls
- User-supplied LUT folder support
- Photo and video library import support
- Preset management with custom save/load flows
- GitHub Actions workflow for iOS build verification
- iOS 16+ deployment target

## Project structure

- `BalutCam/` — SwiftUI app source
- `LUTs/` — sample LUT folder for user-supplied `.cube` files
- `.github/workflows/ios-build.yml` — CI build workflow
- `project.yml` — XcodeGen project definition

## Running locally

1. Install XcodeGen:
   - `brew install xcodegen`
2. Generate the Xcode project:
   - `xcodegen generate`
3. Open `BalutCam.xcodeproj` in Xcode 15+
4. Select an iPhone simulator or a device running iOS 16+
5. Run the app

## LUT folder

The app expects LUT files in a user-accessible folder such as:

- `~/Documents/BalutCam/LUTs`
- or a user-selected folder from the app settings screen

The folder can contain `.cube` files and the app will list them for import and presets.

## Notes

This repository contains a compact but functional starter app and CI pipeline. The UI and media processing are designed to be expanded into a production-grade camera app while staying compatible with GitHub-hosted iOS builds.
