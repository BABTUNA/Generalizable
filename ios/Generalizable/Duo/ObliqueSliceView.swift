// The lid's cross-section (Layer Lens design, artifact PzfR7pyW3vmAhbzrGqz47A `render()`):
// the lid shows the plane through the bottom slice's cut line (through state.cursor), tilted
// t = 180° − hinge about the patient's left–right axis. t = 0 → the same axial slice as the
// bottom screen; t = 90° → front view (coronal). In-plane up = (0, cos t, sin t), so anterior
// rotates to superior as the lid opens toward you.
// Reslice model: vtkImageReslice (VTK, Imaging/Core/vtkImageReslice.h: ResliceAxes = origin +
// in-plane direction cosines) and NiiVue's mm-space slice shader
// (niivue/niivue packages/niivue/src/shader-srcs.ts, vertSliceMMShader). Shader: Shaders/Oblique.metal.
import SwiftUI
import MetalKit
import simd

struct ObliqueSliceView: View {
    @Bindable var state: ViewerState
    /// Lid tilt from the bottom slice, degrees (0 = axial, 90 = coronal).
    var tilt: Double
    /// Hinge angle for the caption.
    var hinge: Double
    var findings: [CaseFinding] = []

    private var tiltDegrees: Int { Int(tilt.rounded()) }
    private var viewName: String {
        tiltDegrees < 2 ? "AXIAL SLICE" : abs(tiltDegrees - 90) < 2 ? "FRONT VIEW (CORONAL)" : "TILTED SLICE"
    }

    var body: some View {
        ZStack {
            ObliqueMetalView(params: ObliqueParams(state: state, tilt: Float(tilt)), loaded: state.loaded)
            GeometryReader { geo in
                // The hinge line: where the lid meets the bottom slice (dashed amber, as in the design).
                if tiltDegrees > 1 {
                    Path { p in p.move(to: CGPoint(x: 0, y: geo.size.height / 2)); p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2)) }
                        .stroke(Color(red: 0.95, green: 0.70, blue: 0.24), style: StrokeStyle(lineWidth: 1.6, dash: [7, 5]))
                }
            }
            .allowsHitTesting(false)
            GeometryReader { geo in rings(in: geo.size) }.allowsHitTesting(false)
        }
        .background(Color.black)
        .overlay(alignment: .topLeading) { LensTag(text: "\(viewName)  \(tiltDegrees)°").padding(10) }
        .overlay(alignment: .bottomLeading) {
            LensTag(text: "hinge · \(Int(hinge.rounded()))°", color: Color(red: 0.27, green: 0.81, blue: 0.88)).padding(10)
        }
        .overlay(alignment: .leading) { edge("R") }
        .overlay(alignment: .trailing) { edge("L") }
    }

    /// Layer Lens `render()` lid rings: a finding's sphere meets the tilted plane at distance
    /// d = q·n from it, where q is the finding relative to the cursor; its in-plane position is
    /// (q·right, q·up). Same plane basis and field of view as ObliqueRenderer.draw.
    @ViewBuilder private func rings(in size: CGSize) -> some View {
        let g = state.geometry
        let t = Float(tilt * .pi / 180)
        let right = SIMD3<Float>(-1, 0, 0), up = SIMD3<Float>(0, cos(t), sin(t)), n = SIMD3<Float>(0, -sin(t), cos(t))
        let half = 0.5 * simd_reduce_max(g.extentMM) * 1.05
        let ptsPerMM = CGFloat(min(size.width, size.height) / 2) / CGFloat(half)
        ForEach(Array(findings.enumerated()), id: \.element.id) { k, f in
            if let v = f.voxel(in: g) {
                let q = (v - state.cursor) * g.spacing
                let r = Float(f.radiusMM ?? 10), d = simd_dot(q, n)
                if abs(d) < r {
                    LensRing(center: CGPoint(x: size.width / 2 + CGFloat(simd_dot(q, right)) * ptsPerMM,
                                             y: size.height / 2 - CGFloat(simd_dot(q, up)) * ptsPerMM),
                             radius: CGFloat((r * r - d * d).squareRoot()) * ptsPerMM, number: k + 1, label: f.title)
                }
            }
        }
    }

    private func edge(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5)).padding(8)
    }
}

struct ObliqueParams: Equatable {
    var cursor: SIMD3<Float>
    var tilt: Float
    var winLow: Float, winHigh: Float
    var labelOpacity: Float
    var showLabels: Bool
    var mask: [UInt32]
    var selected: UInt8
    var showAI: Bool
    var aiOpacity: Float

    @MainActor init(state: ViewerState, tilt: Float) {
        cursor = state.cursor
        self.tilt = tilt
        winLow = state.window.low; winHigh = state.window.high
        labelOpacity = state.labelOpacity
        showLabels = state.showLabels
        var m = [UInt32](repeating: 0, count: 8)
        for o in state.visibleOrgans { let v = Int(o.rawValue); m[v >> 5] |= 1 << UInt32(v & 31) }
        mask = m
        selected = state.selectedOrgan?.rawValue ?? 0
        showAI = state.showAI
        aiOpacity = state.aiOpacity
    }
}

private struct ObliqueMetalView: UIViewRepresentable {
    var params: ObliqueParams
    let loaded: LoadedCase

    func makeCoordinator() -> ObliqueRenderer { ObliqueRenderer(loaded: loaded) }

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: VolumeTextures.device)
        v.colorPixelFormat = .bgra8Unorm
        v.framebufferOnly = true
        v.enableSetNeedsDisplay = true
        v.isPaused = true
        v.clearColor = MTLClearColorMake(0, 0, 0, 1)
        v.delegate = context.coordinator
        context.coordinator.params = params
        return v
    }

    func updateUIView(_ v: MTKView, context: Context) {
        if context.coordinator.params != params {
            context.coordinator.params = params
            v.setNeedsDisplay()
        }
    }
}

private struct ObliqueUniforms {
    var originMM: SIMD3<Float>, rightMM: SIMD3<Float>, upMM: SIMD3<Float>, spacing: SIMD3<Float>
    var winLow: Float, winHigh: Float, labelOpacity: Float, aiOpacity: Float
    var hasLabels: Int32, hasAI: Int32, selected: Int32
    var mask: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
}

private struct OVert { var position: SIMD2<Float>; var ndc: SIMD2<Float> }

final class ObliqueRenderer: NSObject, MTKViewDelegate {
    var params: ObliqueParams?
    private let loaded: LoadedCase
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let tex: VolumeTextures
    private let blankLabels: MTLTexture
    private let blankHeat: MTLTexture

    init(loaded: LoadedCase) {
        self.loaded = loaded
        let dev = VolumeTextures.device
        queue = dev.makeCommandQueue()!
        let lib = dev.makeDefaultLibrary()!
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = lib.makeFunction(name: "obliqueVertex")
        d.fragmentFunction = lib.makeFunction(name: "obliqueFragment")
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try! dev.makeRenderPipelineState(descriptor: d)
        tex = VolumeTextures.shared(for: loaded)
        blankLabels = Self.blank3D(dev, .r8Uint)
        blankHeat = Self.blank3D(dev, .r8Unorm)
    }

    private static func blank3D(_ dev: MTLDevice, _ fmt: MTLPixelFormat) -> MTLTexture {
        let d = MTLTextureDescriptor()
        d.textureType = .type3D; d.pixelFormat = fmt; d.width = 1; d.height = 1; d.depth = 1
        d.usage = .shaderRead
        let t = dev.makeTexture(descriptor: d)!
        var z: UInt8 = 0
        t.replace(region: MTLRegionMake3D(0, 0, 0, 1, 1, 1), mipmapLevel: 0, slice: 0,
                  withBytes: &z, bytesPerRow: 1, bytesPerImage: 1)
        return t
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }

    func draw(in view: MTKView) {
        guard let p = params, let rpd = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        let g = loaded.ct.geometry
        let size = view.drawableSize
        guard size.width > 0, size.height > 0 else { enc.endEncoding(); cb.commit(); return }

        // Screen-right = patient left (radiological, like the axial SliceView); screen-up rotates
        // from anterior (t = 0, axial) to superior (t = 90°, coronal).
        let t = p.tilt * .pi / 180
        let right = SIMD3<Float>(-1, 0, 0)
        let up = SIMD3<Float>(0, cos(t), sin(t))
        // Square field of view covering the whole volume, aspect-fitted into the view.
        let half = 0.5 * simd_reduce_max(g.extentMM) * 1.05
        let aspect = Float(size.width / size.height)
        let sx: Float = aspect >= 1 ? 1 / aspect : 1
        let sy: Float = aspect >= 1 ? 1 : aspect
        let verts: [OVert] = [
            OVert(position: [-sx, -sy], ndc: [-1, -1]), OVert(position: [sx, -sy], ndc: [1, -1]),
            OVert(position: [-sx, sy], ndc: [-1, 1]), OVert(position: [sx, sy], ndc: [1, 1]),
        ]
        let m = p.mask
        var u = ObliqueUniforms(
            originMM: (p.cursor + 0.5) * g.spacing, rightMM: right * half, upMM: up * half, spacing: g.spacing,
            winLow: p.winLow, winHigh: p.winHigh,
            labelOpacity: p.showLabels ? p.labelOpacity : 0, aiOpacity: p.aiOpacity,
            hasLabels: (p.showLabels && tex.labels != nil) ? 1 : 0,
            hasAI: (p.showAI && tex.aiHeatmap != nil) ? 1 : 0,
            selected: Int32(p.selected),
            mask: (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7]))

        enc.setRenderPipelineState(pipeline)
        enc.setVertexBytes(verts, length: MemoryLayout<OVert>.stride * verts.count, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<ObliqueUniforms>.stride, index: 0)
        enc.setFragmentTexture(tex.ct, index: 0)
        enc.setFragmentTexture(tex.labels ?? blankLabels, index: 1)
        enc.setFragmentTexture(tex.organLUT, index: 2)
        enc.setFragmentTexture(tex.aiHeatmap ?? blankHeat, index: 3)
        enc.setFragmentTexture(tex.aiLUT, index: 4)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}

/// Small mono tag on a translucent chip, the caption style from the Layer Lens design.
struct LensTag: View {
    var text: String
    var color: Color = .white.opacity(0.95)
    var fill: Color = Color(red: 0.02, green: 0.035, blue: 0.043).opacity(0.72)
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(fill))
    }
}
