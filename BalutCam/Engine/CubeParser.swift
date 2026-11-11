import Foundation

struct LUTCube {
    let dimension: Int
    let data: Data   // RGBA Float32, red varies fastest (what CIColorCube expects)
}

enum CubeError: LocalizedError {
    case unsupported1D, invalid, unreadable

    var errorDescription: String? {
        switch self {
        case .unsupported1D: return "1D LUTs are not supported. Use a 3D .cube file."
        case .invalid: return "This .cube file is not a valid 3D LUT."
        case .unreadable: return "The file could not be read."
        }
    }
}

enum CubeParser {
    static func parse(url: URL) throws -> LUTCube {
        guard let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
            throw CubeError.unreadable
        }

        var size = 0
        var dmin: [Float] = [0, 0, 0]
        var dmax: [Float] = [1, 1, 1]
        var floats: [Float] = []

        func triple(_ s: Substring) -> [Float]? {
            let parts = s.split(whereSeparator: { $0 == " " || $0 == "\t" }).dropFirst()
            let v = parts.compactMap { Float($0) }
            return v.count >= 3 ? Array(v.prefix(3)) : nil
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("TITLE") { continue }

            if line.hasPrefix("LUT_1D_SIZE") { throw CubeError.unsupported1D }
            if line.hasPrefix("LUT_3D_SIZE") {
                size = Int(line.split(separator: " ").last ?? "") ?? 0
                if size >= 2 { floats.reserveCapacity(size * size * size * 4) }
                continue
            }
            if line.hasPrefix("DOMAIN_MIN") { if let t = triple(Substring(line)) { dmin = t }; continue }
            if line.hasPrefix("DOMAIN_MAX") { if let t = triple(Substring(line)) { dmax = t }; continue }

            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 3,
                  let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) else { continue }
            floats.append((r - dmin[0]) / max(dmax[0] - dmin[0], 1e-6))
            floats.append((g - dmin[1]) / max(dmax[1] - dmin[1], 1e-6))
            floats.append((b - dmin[2]) / max(dmax[2] - dmin[2], 1e-6))
            floats.append(1)
        }

        guard size >= 2, size <= 128, floats.count == size * size * size * 4 else {
            throw CubeError.invalid
        }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        return LUTCube(dimension: size, data: data)
    }
}
