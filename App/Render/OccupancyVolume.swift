// OccupancyVolume.swift
// Builds the "visible-label occupancy" volume the peel shader shades from
// (docs/viz/SPEC.md section 2): occ = (label != 0 && visible[label]) ? 1 : 0.
// The shader trilinearly samples this with a wide finite-difference offset as a cheap
// stand-in for the reference's Gaussian(sigma=1 voxel) blur before taking its gradient.

import Metal

enum OccupancyVolume {
    static func makeTexture(device: MTLDevice, bundle: CaseBundle) -> MTLTexture? {
        let dims = bundle.meta.dims
        guard dims.count == 3 else { return nil }
        let w = dims[0], h = dims[1], d = dims[2]
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r8Unorm
        descriptor.width = w
        descriptor.height = h
        descriptor.depth = d
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    /// Recomputes occupancy for the given visible set and uploads it into `texture`.
    static func update(texture: MTLTexture, bundle: CaseBundle, visibleLayerIDs: Set<Int>) {
        let dims = bundle.meta.dims
        let w = dims[0], h = dims[1], d = dims[2]
        let voxelCount = w * h * d

        var visibleLUT = [UInt8](repeating: 0, count: 256)
        for id in visibleLayerIDs where id >= 0 && id < 256 { visibleLUT[id] = 1 }
        visibleLUT[0] = 0 // background is never occupancy

        var occ = [UInt8](repeating: 0, count: voxelCount)
        bundle.labels.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let src = raw.bindMemory(to: UInt8.self)
            visibleLUT.withUnsafeBufferPointer { lut in
                occ.withUnsafeMutableBufferPointer { dst in
                    for i in 0..<voxelCount {
                        dst[i] = lut[Int(src[i])] &* 255
                    }
                }
            }
        }

        let region = MTLRegionMake3D(0, 0, 0, w, h, d)
        occ.withUnsafeBytes { raw in
            texture.replace(region: region, mipmapLevel: 0, slice: 0,
                             withBytes: raw.baseAddress!, bytesPerRow: w, bytesPerImage: w * h)
        }
    }
}
