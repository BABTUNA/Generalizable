// SliceView.swift
// Full-screen 2D cut-plane slice through the CT / label volume. See
// docs/contracts/render-interface.md for the exact interface this provides.

import SwiftUI
import MetalKit
import simd

struct SliceView: View {
    let bundle: CaseBundle
    let cut: CutPlane
    let mode: SliceMode
    let visibleLayerIDs: Set<Int>
    let selectedFinding: CaseFinding?
    let window: [Double]

    var body: some View {
        SliceMetalView(bundle: bundle, cut: cut, mode: mode,
                        visibleLayerIDs: visibleLayerIDs,
                        selectedFinding: selectedFinding, window: window)
    }
}

private struct SliceMetalView: UIViewRepresentable {
    let bundle: CaseBundle
    let cut: CutPlane
    let mode: SliceMode
    let visibleLayerIDs: Set<Int>
    let selectedFinding: CaseFinding?
    let window: [Double]

    func makeCoordinator() -> SliceRenderer {
        SliceRenderer(bundle: bundle)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.device
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.update(cut: cut, mode: mode, visibleLayerIDs: visibleLayerIDs,
                                    selectedFinding: selectedFinding, window: window)
    }
}

final class SliceRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let ctTexture: MTLTexture
    private let labelTexture: MTLTexture
    private let colorBuffer: MTLBuffer

    private let bundle: CaseBundle
    private var cut = CutPlane()
    private var mode: SliceMode = .layers
    private var visibleLayerIDs: Set<Int> = []
    private var selectedFinding: CaseFinding?
    private var window: [Double] = [40, 400]

    init(bundle: CaseBundle) {
        self.bundle = bundle
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("SliceRenderer: no Metal device")
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("SliceRenderer: could not make command queue")
        }
        self.queue = queue

        guard let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "sliceVertex"),
              let fragmentFn = library.makeFunction(name: "sliceFragment") else {
            fatalError("SliceRenderer: missing shader functions")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("SliceRenderer: pipeline creation failed: \(error)")
        }

        do {
            let textures = try bundle.makeTextures(device: device)
            self.ctTexture = textures.ct
            self.labelTexture = textures.labels
        } catch {
            fatalError("SliceRenderer: texture upload failed: \(error)")
        }

        guard let buffer = device.makeBuffer(length: 256 * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared) else {
            fatalError("SliceRenderer: could not make color buffer")
        }
        self.colorBuffer = buffer
        self.visibleLayerIDs = Set(bundle.layers.map { $0.id })
        super.init()
        rebuildColorTable()
    }

    func update(cut: CutPlane, mode: SliceMode, visibleLayerIDs: Set<Int>,
                selectedFinding: CaseFinding?, window: [Double]) {
        let visibilityChanged = visibleLayerIDs != self.visibleLayerIDs
        self.cut = cut
        self.mode = mode
        self.visibleLayerIDs = visibleLayerIDs
        self.selectedFinding = selectedFinding
        self.window = window
        if visibilityChanged {
            rebuildColorTable()
        }
    }

    private func rebuildColorTable() {
        let table = LayerTables.visibilityTable(layers: bundle.layers, visibleLayerIDs: visibleLayerIDs)
        let pointer = colorBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 256)
        for i in 0..<256 { pointer[i] = table[i] }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        let aspect = Float(max(view.drawableSize.width, 1) / max(view.drawableSize.height, 1))
        let (scale, offset) = LayerTables.textureScaleOffset(bundle: bundle)

        let rawHalfU = LayerTables.projectedHalfExtent(extentMM: bundle.extentMM, direction: cut.uAxis) * 1.05
        let rawHalfV = LayerTables.projectedHalfExtent(extentMM: bundle.extentMM, direction: cut.vAxis) * 1.05
        var halfV = max(rawHalfV, rawHalfU / aspect)
        var halfU = halfV * aspect
        if halfU < rawHalfU { halfU = rawHalfU; halfV = halfU / aspect }

        let level = Float(window.first ?? 40)
        let width = Float(window.count > 1 ? window[1] : 400)

        var uniforms = SliceUniforms(
            originMM: SIMD4<Float>(cut.originMM, 0),
            uAxis: SIMD4<Float>(cut.uAxis, 0),
            vAxis: SIMD4<Float>(cut.vAxis, 0),
            texScale: SIMD4<Float>(scale, 0),
            texOffset: SIMD4<Float>(offset, 0),
            findingCenter: SIMD4<Float>(selectedFinding?.center ?? .zero, 0),
            params0: SIMD4<Float>(halfU, halfV, level, width),
            params1: SIMD4<Float>(Float(selectedFinding?.radiusMM ?? 0),
                                   selectedFinding != nil ? 1 : 0,
                                   mode == .layers ? 1 : 0,
                                   0),
            params2: SIMD4<Float>(Float(2 * halfU) / Float(max(view.drawableSize.width, 1)),
                                   Float(2 * halfV) / Float(max(view.drawableSize.height, 1)),
                                   0, 0)
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SliceUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(colorBuffer, offset: 0, index: 1)
        encoder.setFragmentTexture(ctTexture, index: 0)
        encoder.setFragmentTexture(labelTexture, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

private extension SIMD4 where Scalar == Float {
    init(_ xyz: SIMD3<Float>, _ w: Float) {
        self.init(xyz.x, xyz.y, xyz.z, w)
    }
}
