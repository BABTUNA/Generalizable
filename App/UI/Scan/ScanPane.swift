// ScanPane.swift
// One 2D pane in ScanView: SliceView plus a tap/drag-to-move crosshair overlay. The mm <->
// screen mapping here must match SliceMetalView.draw() (App/Render/SliceView.swift) and
// sliceFragment (App/Render/Slice.metal) exactly, or the crosshair overlay drifts from what
// the shader actually draws.

import SwiftUI
import simd

/// Mirrors the framing SliceMetalView.draw() computes: fit the whole cross-section to the
/// view (aspect-corrected, 5% padding), centred on the volume centre projected into the plane.
private struct ScanPaneFrame {
    let halfU: Float
    let halfV: Float
    let viewCentre: SIMD3<Float>

    init(bundle: CaseBundle, cut: CutPlane, size: CGSize) {
        let aspect = Float(size.width / max(size.height, 1))
        let rawHalfU = LayerTables.projectedHalfExtent(extentMM: bundle.extentMM, direction: cut.uAxis) * 1.05
        let rawHalfV = LayerTables.projectedHalfExtent(extentMM: bundle.extentMM, direction: cut.vAxis) * 1.05
        var hV = max(rawHalfV, rawHalfU / aspect)
        var hU = hV * aspect
        if hU < rawHalfU { hU = rawHalfU; hV = hU / aspect }
        halfU = hU
        halfV = hV

        let toCentre = bundle.centerMM - cut.originMM
        viewCentre = cut.originMM
            + simd_dot(toCentre, cut.uAxis) * cut.uAxis
            + simd_dot(toCentre, cut.vAxis) * cut.vAxis
    }

    /// Screen point (SwiftUI local coords, y down) for an mm point, via the same NDC
    /// convention as Slice.metal (ndc.y = +1 at the top).
    func screenPoint(forMM p: SIMD3<Float>, cut: CutPlane, size: CGSize) -> CGPoint {
        let d = p - viewCentre
        let ndcX = simd_dot(d, cut.uAxis) / halfU
        let ndcY = simd_dot(d, cut.vAxis) / halfV
        return CGPoint(x: (CGFloat(ndcX) + 1) / 2 * size.width,
                        y: (1 - CGFloat(ndcY)) / 2 * size.height)
    }

    /// Inverse: a tap/drag point in this pane -> an mm point lying on `cut`'s plane.
    func mm(forScreen point: CGPoint, cut: CutPlane, size: CGSize) -> SIMD3<Float> {
        let ndcX = Float(point.x / max(size.width, 1)) * 2 - 1
        let ndcY = 1 - Float(point.y / max(size.height, 1)) * 2
        return viewCentre + ndcX * halfU * cut.uAxis + ndcY * halfV * cut.vAxis
    }
}

struct ScanPane: View {
    let bundle: CaseBundle
    let cut: CutPlane
    let mode: SliceMode
    let visibleLayerIDs: Set<Int>
    let window: [Double]
    let crosshair: SIMD3<Float>
    let label: String
    let onMove: (SIMD3<Float>) -> Void

    var body: some View {
        GeometryReader { geo in
            let frame = ScanPaneFrame(bundle: bundle, cut: cut, size: geo.size)
            let center = frame.screenPoint(forMM: crosshair, cut: cut, size: geo.size)

            ZStack {
                SliceView(bundle: bundle, cut: cut, mode: mode, visibleLayerIDs: visibleLayerIDs,
                          selectedFinding: nil, window: window)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: center.y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: center.y))
                    path.move(to: CGPoint(x: center.x, y: 0))
                    path.addLine(to: CGPoint(x: center.x, y: geo.size.height))
                }
                .stroke(Color.yellow.opacity(0.8), lineWidth: 1)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onMove(frame.mm(forScreen: value.location, cut: cut, size: geo.size))
                    }
            )
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.caption2)
                    .padding(4)
                    .background(.black.opacity(0.5))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
            .clipped()
        }
    }
}
