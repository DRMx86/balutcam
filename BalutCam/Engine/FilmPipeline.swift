import CoreImage

/// The whole film look as a Core Image filter chain. Used for live preview, recording,
/// photo capture, and exporting existing media, so every path looks identical.
final class FilmPipeline {
    static let shared = FilmPipeline()

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context: CIContext

    private init() {
        // Gamma-encoded sRGB working space makes contrast/blend sliders behave the way people expect.
        context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .cacheIntermediates: false
        ])
    }

    private func matrix(_ img: CIImage,
                        r: CIVector, g: CIVector, b: CIVector,
                        a: CIVector = CIVector(x: 0, y: 0, z: 0, w: 1),
                        bias: CIVector = CIVector(x: 0, y: 0, z: 0, w: 0)) -> CIImage {
        img.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": r, "inputGVector": g, "inputBVector": b,
            "inputAVector": a, "inputBiasVector": bias
        ])
    }

    /// `seed` changes the grain pattern (pass the frame counter / time for video).
    func apply(_ input: CIImage, params p: LookParameters, seed: Int = 0) -> CIImage {
        let extent = input.extent
        guard !extent.isInfinite, !extent.isNull, extent.width > 0, extent.height > 0 else { return input }

        // Effect sizes scale with resolution so preview and full-res export match.
        let unit = max(extent.width, extent.height) / 1500.0
        var img = input

        // 1. Exposure
        if p.exposure != 0 {
            img = img.applyingFilter("CIExposureAdjust", parameters: ["inputEV": p.exposure])
        }

        // 2. White balance (warmth on R/B, tint on G)
        if p.warmth != 0 || p.tint != 0 {
            let r = CGFloat(1 + 0.20 * p.warmth)
            let g = CGFloat(1 - 0.10 * p.tint)
            let b = CGFloat(1 - 0.20 * p.warmth)
            img = matrix(img,
                         r: CIVector(x: r, y: 0, z: 0, w: 0),
                         g: CIVector(x: 0, y: g, z: 0, w: 0),
                         b: CIVector(x: 0, y: 0, z: b, w: 0))
        }

        // 3. Highlights / shadows
        if p.highlightRecovery > 0 || p.shadowLift != 0 {
            img = img.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 1 - p.highlightRecovery,
                "inputShadowAmount": p.shadowLift
            ])
        }

        // 4. Contrast / saturation
        if p.contrast != 1 || p.saturation != 1 {
            img = img.applyingFilter("CIColorControls", parameters: [
                "inputContrast": p.contrast,
                "inputSaturation": p.saturation
            ])
        }

        // 5. LUT with adjustable intensity
        if p.lutIntensity > 0.001, let cube = LUTLibrary.shared.cube(named: p.lutName),
           let filter = CIFilter(name: "CIColorCubeWithColorSpace") {
            filter.setValue(cube.dimension, forKey: "inputCubeDimension")
            filter.setValue(cube.data, forKey: "inputCubeData")
            filter.setValue(colorSpace, forKey: "inputColorSpace")
            filter.setValue(img, forKey: kCIInputImageKey)
            if let graded = filter.outputImage {
                if p.lutIntensity < 0.999 {
                    img = img.applyingFilter("CIDissolveTransition", parameters: [
                        "inputTargetImage": graded,
                        "inputTime": p.lutIntensity
                    ])
                } else {
                    img = graded
                }
            }
        }

        // 6. Fade (lifted blacks)
        if p.fade > 0.001 {
            let s = CGFloat(1 - 0.09 * p.fade)
            let bias = CGFloat(0.09 * p.fade)
            img = matrix(img,
                         r: CIVector(x: s, y: 0, z: 0, w: 0),
                         g: CIVector(x: 0, y: s, z: 0, w: 0),
                         b: CIVector(x: 0, y: 0, z: s, w: 0),
                         bias: CIVector(x: bias, y: bias, z: bias, w: 0))
        }

        // 7. Bloom
        if p.bloom > 0.001 {
            img = img.clampedToExtent().applyingFilter("CIBloom", parameters: [
                "inputRadius": min(100, 14 * unit),
                "inputIntensity": p.bloom
            ]).cropped(to: extent)
        }

        // 8. Halation: red/orange glow bleeding from bright areas
        if p.halation > 0.001 {
            let hi = img.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 5.0])
            let blurred = hi.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 22 * unit])
                .cropped(to: extent)
            let a = CGFloat(p.halation) * 1.6
            let glow = matrix(blurred,
                              r: CIVector(x: 0.30 * a, y: 0.59 * a, z: 0.11 * a, w: 0),
                              g: CIVector(x: 0.09 * a, y: 0.18 * a, z: 0.03 * a, w: 0),
                              b: CIVector(x: 0.012 * a, y: 0.024 * a, z: 0.004 * a, w: 0))
            img = glow.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: img])
        }

        // 9. Sharpness
        if p.sharpness > 0.001 {
            img = img.applyingFilter("CISharpenLuminance", parameters: [
                "inputSharpness": p.sharpness * 0.8,
                "inputRadius": 1.5 * unit
            ])
        }

        // 10. Grain (monochrome noise, soft-light blended)
        if p.grain > 0.001, let noise = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let scale = max(0.5, CGFloat(p.grainSize) * CGFloat(unit) * 1.2)
            let shift = CGAffineTransform(translationX: CGFloat((seed &* 131) % 1013) * 7,
                                          y: CGFloat((seed &* 197) % 1019) * 5)
            let k = CGFloat(p.grain) * 0.9
            let bias = 0.5 - 0.5 * k
            let kv = CIVector(x: k, y: 0, z: 0, w: 0)
            let mono = noise
                .transformed(by: shift)
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .cropped(to: extent)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": kv, "inputGVector": kv, "inputBVector": kv,
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1)
                ])
            img = mono.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: img])
        }

        // 11. Vignette
        if p.vignette > 0.001 {
            let diag = hypot(extent.width, extent.height)
            img = img.applyingFilter("CIVignetteEffect", parameters: [
                "inputCenter": CIVector(x: extent.midX, y: extent.midY),
                "inputRadius": diag * (0.18 + 0.42 * p.vignetteSize),
                "inputIntensity": p.vignette,
                "inputFalloff": p.vignetteFeather
            ])
        }

        return img.cropped(to: extent)
    }
}
