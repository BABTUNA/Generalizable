// VolumeRenderer — MTKView delegate for the 3D pane's GPU raycaster (Shaders/Volume.metal).
//
// Design follows NiiVue's volume renderer (github.com/niivue/niivue,
// packages/niivue/src/shader-srcs.ts kRenderFunc/kRenderTail; niivue.ts uploads an 8-bit
// copy of the volume scaled from cal_min/cal_max): one-voxel steps, jitter, empty-space fast
// pass, clip-plane sample range, early termination.
//
// Transfer functions: the point lists of 3D Slicer's volume-rendering presets, copied verbatim
// from github.com/Slicer/Slicer, Modules/Loadable/VolumeRendering/Resources/presets.xml
// (`scalarOpacity` / `colorTransfer` of CT-AAA, CT-Bone, CT-Soft-Tissue). Picked per case:
// head CT (skull label present) → CT-Bone; everything else → CT-AAA (contrast vessels + bone)
// plus a faint soft-tissue ramp (stated deviation: without it the abdomen is just skeleton).
//
// Camera: perspective, orbiting a target in millimetre RAS space centred on the volume.
// Default: camera anterior of the patient looking posterior, superior up, which puts the
// patient's right on the screen's left (radiological, like a coronal slice).
import MetalKit
import simd

struct VolumeRenderParams: Equatable {
    var mode: VolumeRenderMode = .volume
    var cursor: SIMD3<Float> = .zero
    var clipNormal: SIMD3<Float>?
    var organMask: SIMD2<UInt32> = .zero
    var tint = true
    var window: WindowLevel = .softTissue
    var selected: UInt8 = 0
    var showPlanes = true
}

private struct VolumeUniforms {
    var eye, right, up, forward, halfExtent, dims, spacing, clip, cursorMM, window, misc: SIMD4<Float>
    var organMask: SIMD4<UInt32>
}

final class VolumeRenderer: NSObject, MTKViewDelegate {
    static let huMin: Float = -1000, huRange: Float = 2500   // must match Volume.metal

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let textures: VolumeTextures
    private let ct8: MTLTexture
    private let labelTex: MTLTexture
    private let hasLabels: Bool
    private let tf: MTLTexture
    let geometry: VolumeGeometry

    enum Preset: String { case ctAAA = "CT-AAA", ctBone = "CT-Bone", ctSoftTissue = "CT-Soft-Tissue" }
    let preset: Preset

    var params = VolumeRenderParams()
    var interacting = false

    // Camera
    private(set) var orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private(set) var distance: Float = 1
    private(set) var target = SIMD3<Float>(repeating: 0)
    let fovY: Float = 30 * .pi / 180
    private var viewHeightPoints: Float = 1

    init?(loaded: LoadedCase) {
        let dev = VolumeTextures.device
        device = dev
        guard let q = dev.makeCommandQueue(), let lib = dev.makeDefaultLibrary(),
              let vf = lib.makeFunction(name: "volumeVertex"), let ff = lib.makeFunction(name: "volumeFragment")
        else { return nil }
        queue = q
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = vf; pd.fragmentFunction = ff
        pd.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let ps = try? dev.makeRenderPipelineState(descriptor: pd) else { return nil }
        pipeline = ps
        textures = VolumeTextures.shared(for: loaded)
        geometry = loaded.ct.geometry
        guard let c8 = Self.unorm8(for: textures.ct, device: dev, lib: lib, queue: q) else { return nil }
        ct8 = c8
        if let l = textures.labels { labelTex = l; hasLabels = true } else {
            let d = MTLTextureDescriptor()
            d.textureType = .type3D; d.pixelFormat = .r8Uint; d.width = 1; d.height = 1; d.depth = 1
            labelTex = dev.makeTexture(descriptor: d)!
            hasLabels = false
        }
        let isHead = loaded.info.id.hasPrefix("CQ500")
        preset = isHead ? .ctBone : .ctAAA
        tf = Self.makeTransferFunction(dev, preset: preset)
        super.init()
        resetCamera()
    }

    // MARK: Camera

    func resetCamera() {
        orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        target = .zero
        let half = geometry.extentMM / 2
        // Fit the coronal silhouette (x by z) plus some depth margin.
        let r = max(half.x, half.z) + half.y * 0.3
        distance = r / tan(fovY / 2) * 1.02
    }

    private var basis: (fwd: SIMD3<Float>, up: SIMD3<Float>, right: SIMD3<Float>) {
        let f = simd_normalize(orientation.act(SIMD3(0, -1, 0)))
        let u = simd_normalize(orientation.act(SIMD3(0, 0, 1)))
        return (f, u, simd_normalize(simd_cross(f, u)))
    }

    /// Drag in points: horizontal = turntable about patient S-I axis, vertical = tilt.
    func orbit(dx: Float, dy: Float) {
        let k: Float = 0.008
        orientation = simd_normalize(simd_quatf(angle: -dx * k, axis: SIMD3(0, 0, 1)) * orientation)
        orientation = simd_normalize(simd_quatf(angle: -dy * k, axis: basis.right) * orientation)
    }

    func pan(dx: Float, dy: Float) {
        let mmPerPt = 2 * distance * tan(fovY / 2) / max(viewHeightPoints, 1)
        let b = basis
        target += (-b.right * dx + b.up * dy) * mmPerPt
    }

    func zoom(by scale: Float) {
        let r = simd_length(geometry.extentMM)
        distance = min(max(distance / max(scale, 0.01), r * 0.15), r * 6)
    }

    func setViewHeight(points: CGFloat) { viewHeightPoints = Float(points) }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }

    func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: rpd)
        else { return }
        var u = uniforms(drawableSize: view.drawableSize)
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<VolumeUniforms>.stride, index: 0)
        enc.setFragmentTexture(ct8, index: 0)
        enc.setFragmentTexture(labelTex, index: 1)
        enc.setFragmentTexture(textures.organLUT, index: 2)
        enc.setFragmentTexture(tf, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    private func uniforms(drawableSize s: CGSize) -> VolumeUniforms {
        let g = geometry
        let half = g.extentMM / 2
        let b = basis
        let eye = target - b.fwd * distance
        let tanH = tan(fovY / 2)
        let aspect = Float(max(s.width, 1) / max(s.height, 1))
        let minSp = g.spacing.min()
        let step = minSp * (interacting ? 2.0 : 1.0)
        let cursorMM = (params.cursor + 0.5) * g.spacing - half
        var clip = SIMD4<Float>(0, 0, 1, 0), clipOn: Float = 0
        if let n = params.clipNormal, simd_length(n) > 1e-6 {
            // voxel-space plane normal -> mm-space normal (inverse transpose of diag(spacing))
            let nm = simd_normalize(n / g.spacing)
            clip = SIMD4(nm, -simd_dot(nm, cursorMM))
            clipOn = 1
        }
        // Cut-face window: head → subdural (W200/L80, shows thin extra-axial blood), else the viewer's.
        let cw = preset == .ctBone ? WindowLevel.subdural : params.window
        let capLo = (cw.low - Self.huMin) / Self.huRange, capHi = (cw.high - Self.huMin) / Self.huRange
        let lo = (params.window.low - Self.huMin) / Self.huRange
        let hi = (params.window.high - Self.huMin) / Self.huRange
        return VolumeUniforms(
            eye: SIMD4(eye, 0),
            right: SIMD4(b.right, tanH * aspect),
            up: SIMD4(b.up, tanH),
            forward: SIMD4(b.fwd, 2 * tanH / Float(max(s.height, 1))),
            halfExtent: SIMD4(half, step),
            dims: SIMD4(SIMD3<Float>(g.dims), 1.0),
            spacing: SIMD4(g.spacing, params.mode == .mip ? 1 : 0),
            clip: clip,
            cursorMM: SIMD4(cursorMM, capLo),
            window: SIMD4(lo, hi, (params.tint && hasLabels) ? 1 : 0, params.showPlanes ? 1 : 0),
            misc: SIMD4(clipOn, capHi, Float(params.selected), 0.07),
            organMask: SIMD4(params.organMask.x, params.organMask.y, 0, 0))
    }

    // MARK: Resources

    nonisolated(unsafe) private static var ct8Cache: (ObjectIdentifier, MTLTexture)?

    private static func unorm8(for src: MTLTexture, device: MTLDevice, lib: MTLLibrary, queue: MTLCommandQueue) -> MTLTexture? {
        if let c = ct8Cache, c.0 == ObjectIdentifier(src) { return c.1 }
        guard let fn = lib.makeFunction(name: "volumeCTToUnorm8"),
              let cps = try? device.makeComputePipelineState(function: fn) else { return nil }
        let d = MTLTextureDescriptor()
        d.textureType = .type3D; d.pixelFormat = .r8Unorm
        d.width = src.width; d.height = src.height; d.depth = src.depth
        d.usage = [.shaderRead, .shaderWrite]; d.storageMode = .private
        guard let dst = device.makeTexture(descriptor: d), let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else { return nil }
        enc.setComputePipelineState(cps)
        enc.setTexture(src, index: 0); enc.setTexture(dst, index: 1)
        let tg = MTLSize(width: 8, height: 8, depth: 4)
        let grid = MTLSize(width: (src.width + 7) / 8, height: (src.height + 7) / 8, depth: (src.depth + 3) / 4)
        enc.dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cb.commit(); cb.waitUntilCompleted()
        ct8Cache = (ObjectIdentifier(src), dst)
        return dst
    }

    /// Slicer preset point lists: opacity (HU, a) and colour (HU, r, g, b).
    private static func slicerPoints(_ p: Preset) -> (op: [(Float, Float)], col: [(Float, Float, Float, Float)]) {
        switch p {
        case .ctAAA:
            return ([(-3024, 0), (143.556, 0), (166.222, 0.686275), (214.389, 0.696078), (419.736, 0.833333), (3071, 0.803922)],
                    [(-3024, 0, 0, 0), (143.556, 0.615686, 0.356863, 0.184314), (166.222, 0.882353, 0.603922, 0.290196),
                     (214.389, 1, 1, 1), (419.736, 1, 0.937033, 0.954531), (3071, 0.827451, 0.658824, 1)])
        case .ctBone:
            return ([(-3024, 0), (-16.4458, 0), (641.385, 0.715686), (3071, 0.705882)],
                    [(-3024, 0, 0, 0), (-16.4458, 0.729412, 0.254902, 0.301961), (641.385, 0.905882, 0.815686, 0.552941),
                     (3071, 1, 1, 1)])
        case .ctSoftTissue:
            return ([(-2048, 0), (-167.01, 0), (-160, 1), (240, 1), (3661, 1)],
                    [(-2048, 0, 0, 0), (-167.01, 0, 0, 0), (-160, 0.0556356, 0.0556356, 0.0556356), (240, 1, 1, 1), (3661, 1, 1, 1)])
        }
    }

    private static func interp<T>(_ pts: [(Float, T)], _ x: Float, _ mix: (T, T, Float) -> T) -> T {
        if x <= pts[0].0 { return pts[0].1 }
        for j in 0..<(pts.count - 1) where x <= pts[j + 1].0 {
            let f = (x - pts[j].0) / max(pts[j + 1].0 - pts[j].0, 1e-6)
            return mix(pts[j].1, pts[j + 1].1, f)
        }
        return pts.last!.1
    }

    /// 1D RGBA transfer function over the same normalised HU axis as the 8-bit volume.
    /// Alpha is opacity per 1 mm (corrected per step in the shader), as Slicer's scalar
    /// opacity is per unit distance.
    private static func makeTransferFunction(_ dev: MTLDevice, preset: Preset) -> MTLTexture {
        let sp = slicerPoints(preset)
        let op = sp.op
        let col = sp.col.map { ($0.0, SIMD3<Float>($0.1, $0.2, $0.3)) }
        // Faint soft-tissue ramp for the abdomen (see header).
        let soft: [(Float, Float)] = preset == .ctAAA ? [(-200, 0), (-80, 0.0015), (20, 0.003), (100, 0.006), (143, 0.01)] : []
        let softCol = SIMD3<Float>(0.80, 0.52, 0.42)
        func sample(_ hu: Float) -> SIMD4<Float> {
            var a = interp(op, hu) { $0 + ($1 - $0) * $2 }
            var c = interp(col, hu) { simd_mix($0, $1, SIMD3(repeating: $2)) }
            if !soft.isEmpty && hu > -200 && hu < 143.556 {
                let sa = interp(soft, hu) { $0 + ($1 - $0) * $2 }
                if sa > a { a = sa; c = hu < 143.556 ? softCol : c }
            }
            return SIMD4(c, a)
        }
        let n = 1024
        var data = [Float16](repeating: 0, count: n * 4)
        for i in 0..<n {
            let hu = huMin + huRange * Float(i) / Float(n - 1)
            let c = sample(hu)
            for k in 0..<4 { data[i * 4 + k] = Float16(c[k]) }
        }
        let d = MTLTextureDescriptor()
        d.textureType = .type1D; d.pixelFormat = .rgba16Float; d.width = n; d.usage = .shaderRead
        let t = dev.makeTexture(descriptor: d)!
        t.replace(region: MTLRegionMake1D(0, n), mipmapLevel: 0, withBytes: data, bytesPerRow: n * 8)
        return t
    }
}
