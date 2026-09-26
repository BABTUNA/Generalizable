// OverviewView.swift
// 3D "peel" view: orthographic raymarch through the label volume, clipped by the cut
// plane, with a turntable camera orbiting the z (superior) axis. See
// docs/contracts/render-interface.md for the exact interface this provides.

import SwiftUI
import MetalKit
import simd

struct OverviewView: View {
    let bundle: CaseBundle
    @Binding var cut: CutPlane
    let visibleLayerIDs: Set<Int>
    let selectedFinding: CaseFinding?

    var body: some View {
        OverviewMetalView(bundle: bundle, cut: $cut, visibleLayerIDs: visibleLayerIDs,
                           selectedFinding: selectedFinding)
    }
}

private struct OverviewMetalView: UIViewRepresentable {
    let bundle: CaseBundle
    @Binding var cut: CutPlane
    let visibleLayerIDs: Set<Int>
    let selectedFinding: CaseFinding?

    func makeCoordinator() -> OverviewRenderer {
        OverviewRenderer(bundle: bundle, cutBinding: $cut)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.device
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30
        view.clearColor = MTLClearColorMake(0.03, 0.03, 0.05, 1)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(OverviewRenderer.handlePan(_:)))
        view.addGestureRecognizer(pan)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.update(cut: cut, visibleLayerIDs: visibleLayerIDs, selectedFinding: selectedFinding)
    }
}

final class OverviewRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let ctTexture: MTLTexture
    private let labelTexture: MTLTexture
    private let occupancyTexture: MTLTexture
    private let colorBuffer: MTLBuffer

    private let bundle: CaseBundle
    private var cutBinding: Binding<CutPlane>
    private var cut = CutPlane()
    private var visibleLayerIDs: Set<Int> = []
    private var selectedFinding: CaseFinding?
    private var yaw: Float = 0
    weak var view: MTKView?

    init(bundle: CaseBundle, cutBinding: Binding<CutPlane>) {
        self.bundle = bundle
        self.cutBinding = cutBinding
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("OverviewRenderer: no Metal device")
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("OverviewRenderer: could not make command queue")
        }
        self.queue = queue

        guard let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "overviewVertex"),
              let fragmentFn = library.makeFunction(name: "overviewFragment") else {
            fatalError("OverviewRenderer: missing shader functions")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("OverviewRenderer: pipeline creation failed: \(error)")
        }

        do {
            let textures = try bundle.makeTextures(device: device)
            self.ctTexture = textures.ct
            self.labelTexture = textures.labels
        } catch {
            fatalError("OverviewRenderer: texture upload failed: \(error)")
        }

        guard let occTexture = OccupancyVolume.makeTexture(device: device, bundle: bundle) else {
            fatalError("OverviewRenderer: could not make occupancy texture")
        }
        self.occupancyTexture = occTexture

        guard let buffer = device.makeBuffer(length: 256 * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared) else {
            fatalError("OverviewRenderer: could not make color buffer")
        }
        self.colorBuffer = buffer
        self.visibleLayerIDs = Set(bundle.layers.map { $0.id })
        super.init()
        rebuildColorTable()
    }

    func update(cut: CutPlane, visibleLayerIDs: Set<Int>, selectedFinding: CaseFinding?) {
        let visibilityChanged = visibleLayerIDs != self.visibleLayerIDs
        self.cut = cut
        self.visibleLayerIDs = visibleLayerIDs
        self.selectedFinding = selectedFinding
        if visibilityChanged { rebuildColorTable() }
    }

    private func rebuildColorTable() {
        let table = LayerTables.opacityTable(layers: bundle.layers, visibleLayerIDs: visibleLayerIDs)
        let pointer = colorBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 256)
        for i in 0..<256 { pointer[i] = table[i] }
        OccupancyVolume.update(texture: occupancyTexture, bundle: bundle, visibleLayerIDs: visibleLayerIDs)
    }

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .changed || recognizer.state == .began else {
            if recognizer.state == .ended || recognizer.state == .cancelled {
                recognizer.setTranslation(.zero, in: recognizer.view)
            }
            return
        }
        let translation = recognizer.translation(in: recognizer.view)
        recognizer.setTranslation(.zero, in: recognizer.view)

        yaw += Float(translation.x) * 0.006

        let avgSpacing = Float((bundle.meta.spacingMM.reduce(0, +)) / Double(max(bundle.meta.spacingMM.count, 1)))
        let pivotDelta = -Float(translation.y) * avgSpacing * 0.6
        var newCut = cutBinding.wrappedValue
        newCut.dragPivot(byMM: SIMD3<Float>(0, 0, pivotDelta))
        cutBinding.wrappedValue = newCut
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        // Anterior view: camera in front of the patient (+y) looking toward -y. Radiological
        // convention (CutPlane.uAxis): patient's right (RAS +x) on the viewer's left, so
        // screen-right is -x, matching SliceView.
        let forwardBase = SIMD3<Float>(0, -1, 0)
        let rightBase = SIMD3<Float>(-1, 0, 0)
        let upBase = SIMD3<Float>(0, 0, 1)
        let c = cos(yaw), s = sin(yaw)
        func rotateZ(_ v: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3<Float>(v.x * c - v.y * s, v.x * s + v.y * c, v.z)
        }
        let camForward = rotateZ(forwardBase)
        let camRight = rotateZ(rightBase)
        let camUp = upBase

        let diag = length(bundle.extentMM)
        let camPos = bundle.centerMM - camForward * diag

        let aspect = Float(max(view.drawableSize.width, 1) / max(view.drawableSize.height, 1))
        let rawHalfW = LayerTables.projectedHalfExtent(extentMM: bundle.extentMM, direction: camRight) * 1.15
        let rawHalfH = LayerTables.projectedHalfExtent(extentMM: bundle.extentMM, direction: camUp) * 1.15
        var halfH = max(rawHalfH, rawHalfW / aspect)
        var halfW = halfH * aspect
        if halfW < rawHalfW { halfW = rawHalfW; halfH = halfW / aspect }

        let (scale, offset) = LayerTables.textureScaleOffset(bundle: bundle)
        let boxMin = bundle.centerMM - bundle.extentMM * 0.5
        let boxMax = bundle.centerMM + bundle.extentMM * 0.5

        let avgSpacing = Float((bundle.meta.spacingMM.reduce(0, +)) / Double(max(bundle.meta.spacingMM.count, 1)))
        let stepMM = max(avgSpacing * 0.5, 0.25)
        let maxSteps: Float = 400

        let level = Float(bundle.meta.windowPresets["soft"]?.first ?? 40)
        let width = Float(bundle.meta.windowPresets["soft"]?.last ?? 400)

        var uniforms = OverviewUniforms(
            camRight: SIMD4<Float>(camRight, 0),
            camUp: SIMD4<Float>(camUp, 0),
            camForward: SIMD4<Float>(camForward, 0),
            camPos: SIMD4<Float>(camPos, 0),
            texScale: SIMD4<Float>(scale, 0),
            texOffset: SIMD4<Float>(offset, 0),
            cutOrigin: SIMD4<Float>(cut.originMM, 0),
            cutNormal: SIMD4<Float>(cut.normal, 0),
            cutUAxis: SIMD4<Float>(cut.uAxis, 0),
            cutVAxis: SIMD4<Float>(cut.vAxis, 0),
            findingCenter: SIMD4<Float>(selectedFinding?.center ?? .zero, 0),
            boxMin: SIMD4<Float>(boxMin, 0),
            boxMax: SIMD4<Float>(boxMax, 0),
            params0: SIMD4<Float>(halfW, halfH, stepMM, maxSteps),
            params1: SIMD4<Float>(Float(selectedFinding?.radiusMM ?? 0),
                                   selectedFinding != nil ? 1 : 0,
                                   0, level),
            params2: SIMD4<Float>(width, 0, 0, 0)
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OverviewUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(colorBuffer, offset: 0, index: 1)
        encoder.setFragmentTexture(ctTexture, index: 0)
        encoder.setFragmentTexture(labelTexture, index: 1)
        encoder.setFragmentTexture(occupancyTexture, index: 2)
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
