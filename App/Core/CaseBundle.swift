// CaseBundle.swift
// Non-visual Swift only (Foundation / simd / Metal). No SwiftUI or UIKit.
//
// Loads an A4 case bundle (meta.json, layers.json, findings.json, ct.raw, labels.raw)
// from disk and exposes it as typed Swift plus ready-to-sample Metal textures.
//
// Texture formats (see docs/PRD.md addendum A4):
//   - CT volume:    MTLTextureType.type3D, pixelFormat .r16Snorm.
//     ct.raw is little-endian Int16 HU with no header. .r16Snorm reinterprets the
//     same 16-bit bit pattern as a normalized signed value in [-1, 1], so the raw
//     bytes upload unchanged (no repacking) and the sampler's LINEAR filtering
//     works correctly on the normalized value. A shader recovers HU with
//     `hu = value * 32767.0`.
//   - Label volume: MTLTextureType.type3D, pixelFormat .r8Uint.
//     Read with `texture.read(...)` (nearest / integer sampling) in the shader —
//     never with a filtering sampler — since interpolating label IDs is meaningless.
//
// Voxel ordering is x fastest, then y, then z (RAS, +z toward the head), per A4.

import Foundation
import simd
import Metal

// MARK: - Meta

struct CaseMeta: Codable {
    let dims: [Int]
    let spacingMM: [Double]
    let originMM: [Double]
    let orientation: String
    let ctDtype: String
    let labelsDtype: String
    let windowPresets: [String: [Double]]
    let source: String
    let license: String

    enum CodingKeys: String, CodingKey {
        case dims
        case spacingMM = "spacing_mm"
        case originMM = "origin_mm"
        case orientation
        case ctDtype = "ct_dtype"
        case labelsDtype = "labels_dtype"
        case windowPresets = "window_presets"
        case source
        case license
    }

    init(dims: [Int], spacingMM: [Double], originMM: [Double], orientation: String,
         ctDtype: String, labelsDtype: String, windowPresets: [String: [Double]],
         source: String, license: String) {
        self.dims = dims
        self.spacingMM = spacingMM
        self.originMM = originMM
        self.orientation = orientation
        self.ctDtype = ctDtype
        self.labelsDtype = labelsDtype
        self.windowPresets = windowPresets
        self.source = source
        self.license = license
    }

    /// L2's synthetic bundles (observed 2026-09-26) emit a nested `"dtypes": {"ct": ..., "labels": ...}`
    /// instead of the flat `ct_dtype`/`labels_dtype` keys this contract's Required API specifies.
    /// A4 only names the field "dtypes" without pinning its shape, so this decoder accepts either,
    /// while the Swift-side property names stay exactly as specified (Bitrig builds against those).
    private struct NestedDtypes: Decodable {
        struct Pair: Decodable { let ct: String; let labels: String }
        let dtypes: Pair?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dims = try c.decode([Int].self, forKey: .dims)
        spacingMM = try c.decode([Double].self, forKey: .spacingMM)
        originMM = try c.decode([Double].self, forKey: .originMM)
        orientation = try c.decode(String.self, forKey: .orientation)
        windowPresets = try c.decode([String: [Double]].self, forKey: .windowPresets)
        source = try c.decode(String.self, forKey: .source)
        license = try c.decode(String.self, forKey: .license)

        if let ct = try c.decodeIfPresent(String.self, forKey: .ctDtype),
           let labels = try c.decodeIfPresent(String.self, forKey: .labelsDtype) {
            ctDtype = ct
            labelsDtype = labels
        } else if let pair = try NestedDtypes(from: decoder).dtypes {
            ctDtype = pair.ct
            labelsDtype = pair.labels
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .ctDtype, in: c,
                debugDescription: "Expected either ct_dtype/labels_dtype or a nested dtypes:{ct,labels} object")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dims, forKey: .dims)
        try c.encode(spacingMM, forKey: .spacingMM)
        try c.encode(originMM, forKey: .originMM)
        try c.encode(orientation, forKey: .orientation)
        try c.encode(ctDtype, forKey: .ctDtype)
        try c.encode(labelsDtype, forKey: .labelsDtype)
        try c.encode(windowPresets, forKey: .windowPresets)
        try c.encode(source, forKey: .source)
        try c.encode(license, forKey: .license)
    }
}

// MARK: - Layer

struct CaseLayer: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    /// Free string. The pipeline emits skin/fat/muscle/bone/organ/brain/finding,
    /// but synthetic cases (circuit board, Sun) may use other groups.
    let group: String
    /// "#RRGGBB"
    let color: String
    let peelOrder: Int
    let blurb: String

    enum CodingKeys: String, CodingKey {
        case id, name, group, color
        case peelOrder = "peel_order"
        case blurb
    }

    /// Parsed color with alpha = 1. Falls back to opaque magenta on a malformed hex string.
    var rgba: SIMD4<Float> {
        var hex = color
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            return SIMD4<Float>(1, 0, 1, 1)
        }
        let r = Float((value >> 16) & 0xFF) / 255.0
        let g = Float((value >> 8) & 0xFF) / 255.0
        let b = Float(value & 0xFF) / 255.0
        return SIMD4<Float>(r, g, b, 1)
    }
}

// MARK: - Finding

struct CaseFinding: Codable, Identifiable, Hashable {
    let id: Int
    let labelID: Int
    let title: String
    let centerMM: [Double]
    let radiusMM: Double
    let explanation: String

    enum CodingKeys: String, CodingKey {
        case id
        case labelID = "label_id"
        case title
        case centerMM = "center_mm"
        case radiusMM = "radius_mm"
        case explanation
    }

    init(id: Int, labelID: Int, title: String, centerMM: [Double], radiusMM: Double, explanation: String) {
        self.id = id
        self.labelID = labelID
        self.title = title
        self.centerMM = centerMM
        self.radiusMM = radiusMM
        self.explanation = explanation
    }

    /// A stable (non-randomized) hash of a string id into a positive Int, used only as a fallback
    /// below. Swift's built-in String.hashValue is seeded per process and would make `id` unstable
    /// across launches, which breaks the Identifiable contract this type promises.
    private static func stableHash(_ s: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325 // FNV-1a offset basis
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return Int(h & 0x7fff_ffff)
    }

    /// L2's synthetic findings.json (observed 2026-09-26) uses semantic string ids ("core",
    /// "sunspot") rather than the Int this contract's Required API specifies. Bitrig's views build
    /// against `id: Int`, so this accepts either shape and derives a stable Int from a string id.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intID = try? c.decode(Int.self, forKey: .id) {
            id = intID
        } else {
            id = Self.stableHash(try c.decode(String.self, forKey: .id))
        }
        labelID = try c.decode(Int.self, forKey: .labelID)
        title = try c.decode(String.self, forKey: .title)
        centerMM = try c.decode([Double].self, forKey: .centerMM)
        radiusMM = try c.decode(Double.self, forKey: .radiusMM)
        explanation = try c.decode(String.self, forKey: .explanation)
    }

    /// centerMM as a SIMD3<Float>. Zero if the array is malformed (should never happen for a valid bundle).
    var center: SIMD3<Float> {
        guard centerMM.count >= 3 else { return .zero }
        return SIMD3<Float>(Float(centerMM[0]), Float(centerMM[1]), Float(centerMM[2]))
    }
}

// MARK: - Errors

enum CaseBundleError: Error, CustomStringConvertible {
    case missingFile(String)
    case sizeMismatch(file: String, expected: Int, actual: Int)
    case invalidJSON(file: String, underlying: Error)
    case textureCreationFailed(String)
    case noBundleResourceURL

    var description: String {
        switch self {
        case .missingFile(let name):
            return "CaseBundle: missing required file \"\(name)\""
        case .sizeMismatch(let file, let expected, let actual):
            return "CaseBundle: \(file) is \(actual) bytes, expected \(expected) (product(dims) * bytesPerVoxel — check meta.json dims against the raw file)"
        case .invalidJSON(let file, let underlying):
            return "CaseBundle: failed to decode \(file): \(underlying)"
        case .textureCreationFailed(let which):
            return "CaseBundle: MTLDevice failed to create the \(which) texture"
        case .noBundleResourceURL:
            return "CaseBundle: Bundle.main.resourceURL is nil"
        }
    }
}

// MARK: - Bundle

final class CaseBundle {
    let name: String
    let meta: CaseMeta
    let layers: [CaseLayer]
    let findings: [CaseFinding]
    let ct: Data
    let labels: Data

    init(name: String, meta: CaseMeta, layers: [CaseLayer], findings: [CaseFinding], ct: Data, labels: Data) {
        self.name = name
        self.meta = meta
        self.layers = layers
        self.findings = findings
        self.ct = ct
        self.labels = labels
    }

    // MARK: Loading

    static func load(directory: URL, name: String) throws -> CaseBundle {
        let metaURL = directory.appendingPathComponent("meta.json")
        let layersURL = directory.appendingPathComponent("layers.json")
        let findingsURL = directory.appendingPathComponent("findings.json")
        let ctURL = directory.appendingPathComponent("ct.raw")
        let labelsURL = directory.appendingPathComponent("labels.raw")

        for (url, label) in [(metaURL, "meta.json"), (layersURL, "layers.json"),
                              (findingsURL, "findings.json"), (ctURL, "ct.raw"),
                              (labelsURL, "labels.raw")] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CaseBundleError.missingFile("\(name)/\(label)")
            }
        }

        let decoder = JSONDecoder()

        let meta: CaseMeta
        do {
            meta = try decoder.decode(CaseMeta.self, from: try Data(contentsOf: metaURL))
        } catch {
            throw CaseBundleError.invalidJSON(file: "meta.json", underlying: error)
        }

        let layers: [CaseLayer]
        do {
            layers = try decoder.decode([CaseLayer].self, from: try Data(contentsOf: layersURL))
        } catch {
            throw CaseBundleError.invalidJSON(file: "layers.json", underlying: error)
        }

        let findings: [CaseFinding]
        do {
            findings = try decoder.decode([CaseFinding].self, from: try Data(contentsOf: findingsURL))
        } catch {
            throw CaseBundleError.invalidJSON(file: "findings.json", underlying: error)
        }

        let ct = try Data(contentsOf: ctURL)
        let labelsData = try Data(contentsOf: labelsURL)

        let voxelCount = meta.dims.reduce(1, *)
        let expectedCT = voxelCount * 2
        let expectedLabels = voxelCount * 1
        guard ct.count == expectedCT else {
            throw CaseBundleError.sizeMismatch(file: "ct.raw", expected: expectedCT, actual: ct.count)
        }
        guard labelsData.count == expectedLabels else {
            throw CaseBundleError.sizeMismatch(file: "labels.raw", expected: expectedLabels, actual: labelsData.count)
        }

        return CaseBundle(name: name, meta: meta, layers: layers, findings: findings, ct: ct, labels: labelsData)
    }

    /// Loads from Bundle.main.resourceURL/Cases/<name> (App/Cases is a folder reference in the app target).
    static func bundled(_ name: String) throws -> CaseBundle {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw CaseBundleError.noBundleResourceURL
        }
        let directory = resourceURL.appendingPathComponent("Cases").appendingPathComponent(name)
        return try load(directory: directory, name: name)
    }

    /// Names of bundled cases available under Bundle.main.resourceURL/Cases (each with a meta.json).
    static func availableBundled() -> [String] {
        guard let resourceURL = Bundle.main.resourceURL else { return [] }
        let casesDir = resourceURL.appendingPathComponent("Cases")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: casesDir, includingPropertiesForKeys: nil
        ) else { return [] }
        return entries
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("meta.json").path) }
            .map { $0.lastPathComponent }
            .sorted()
    }

    // MARK: Geometry

    private var dims: SIMD3<Int> {
        SIMD3<Int>(meta.dims[0], meta.dims[1], meta.dims[2])
    }

    private var spacing: SIMD3<Float> {
        SIMD3<Float>(Float(meta.spacingMM[0]), Float(meta.spacingMM[1]), Float(meta.spacingMM[2]))
    }

    private var origin: SIMD3<Float> {
        SIMD3<Float>(Float(meta.originMM[0]), Float(meta.originMM[1]), Float(meta.originMM[2]))
    }

    /// Physical size of the volume in mm (dims * spacing).
    var extentMM: SIMD3<Float> {
        SIMD3<Float>(Float(dims.x), Float(dims.y), Float(dims.z)) * spacing
    }

    /// Midpoint of the volume in mm.
    var centerMM: SIMD3<Float> {
        origin + extentMM * 0.5
    }

    /// Voxel index (corner convention) -> mm, per A4: origin_mm + ijk * spacing_mm.
    func mm(forVoxel ijk: SIMD3<Int>) -> SIMD3<Float> {
        origin + SIMD3<Float>(Float(ijk.x), Float(ijk.y), Float(ijk.z)) * spacing
    }

    /// mm -> normalized 0...1 texture coordinates, texel-center-correct (x fastest, RAS).
    /// Inverse of `mm(forVoxel:)` up to the +0.5 texel-center offset expected by texture sampling.
    func textureCoord(forMM p: SIMD3<Float>) -> SIMD3<Float> {
        let voxel = (p - origin) / spacing
        let dimsF = SIMD3<Float>(Float(dims.x), Float(dims.y), Float(dims.z))
        return (voxel + SIMD3<Float>(repeating: 0.5)) / dimsF
    }

    // MARK: Sampling raw arrays

    private func linearIndex(_ ijk: SIMD3<Int>) -> Int {
        ijk.x + ijk.y * dims.x + ijk.z * dims.x * dims.y
    }

    /// Reads one HU value from ct.raw (little-endian Int16).
    func hu(at ijk: SIMD3<Int>) -> Int16 {
        let byteOffset = linearIndex(ijk) * 2
        let o = ct.startIndex + byteOffset
        let low = UInt16(ct[o])
        let high = UInt16(ct[o + 1])
        return Int16(bitPattern: low | (high << 8))
    }

    /// Reads one label ID from labels.raw.
    func label(at ijk: SIMD3<Int>) -> UInt8 {
        labels[labels.startIndex + linearIndex(ijk)]
    }

    // MARK: Metal textures

    /// Builds the CT (.r16Snorm) and labels (.r8Uint) 3D textures described in the header comment above.
    func makeTextures(device: MTLDevice) throws -> (ct: MTLTexture, labels: MTLTexture) {
        let w = dims.x, h = dims.y, d = dims.z

        let ctDescriptor = MTLTextureDescriptor()
        ctDescriptor.textureType = .type3D
        ctDescriptor.pixelFormat = .r16Snorm
        ctDescriptor.width = w
        ctDescriptor.height = h
        ctDescriptor.depth = d
        ctDescriptor.usage = [.shaderRead]
        ctDescriptor.storageMode = .shared
        guard let ctTexture = device.makeTexture(descriptor: ctDescriptor) else {
            throw CaseBundleError.textureCreationFailed("ct")
        }

        let labelsDescriptor = MTLTextureDescriptor()
        labelsDescriptor.textureType = .type3D
        labelsDescriptor.pixelFormat = .r8Uint
        labelsDescriptor.width = w
        labelsDescriptor.height = h
        labelsDescriptor.depth = d
        labelsDescriptor.usage = [.shaderRead]
        labelsDescriptor.storageMode = .shared
        guard let labelsTexture = device.makeTexture(descriptor: labelsDescriptor) else {
            throw CaseBundleError.textureCreationFailed("labels")
        }

        let region = MTLRegionMake3D(0, 0, 0, w, h, d)

        let ctBytesPerRow = w * 2
        let ctBytesPerImage = ctBytesPerRow * h
        ct.withUnsafeBytes { raw in
            ctTexture.replace(region: region, mipmapLevel: 0, slice: 0,
                               withBytes: raw.baseAddress!,
                               bytesPerRow: ctBytesPerRow, bytesPerImage: ctBytesPerImage)
        }

        let labelsBytesPerRow = w
        let labelsBytesPerImage = labelsBytesPerRow * h
        labels.withUnsafeBytes { raw in
            labelsTexture.replace(region: region, mipmapLevel: 0, slice: 0,
                                   withBytes: raw.baseAddress!,
                                   bytesPerRow: labelsBytesPerRow, bytesPerImage: labelsBytesPerImage)
        }

        return (ctTexture, labelsTexture)
    }
}
