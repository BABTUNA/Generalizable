// ScanView.swift
// "Scan" viewer mode (BodyMaps-style): axial / sagittal / coronal / 3D panes sharing one
// crosshair, window/level presets, and an organ legend. Reimplemented natively — no code
// copied from bodymaps.wse.jhu.edu / BodyMaps/BodyMaps-website (unlicensed).
//
// Geometry note: mm <-> screen mapping in ScanPaneFrame mirrors SliceMetalView.draw() in
// App/Render/SliceView.swift exactly (same projectedHalfExtent + aspect-fit + view-centre
// logic, and the same NDC convention as Slice.metal's sliceFragment: ndc.y = +1 at the top),
// so the crosshair overlay lines up with what SliceView actually draws.

import SwiftUI
import simd

struct ScanView: View {
    @Bindable var model: ViewerModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var showOrgans = false

    private enum Pane: String, CaseIterable, Identifiable {
        case axial = "Axial", sagittal = "Sagittal", coronal = "Coronal", threeD = "3D"
        var id: String { rawValue }
    }
    @State private var singlePane: Pane = .axial

    private var isCompactPortrait: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    private var mode: SliceMode { showOrgans ? .layers : .ct }

    // Three orthogonal cuts through the shared crosshair (A1 geometry convention, CutPlane.swift):
    // axial = tilt 0; coronal = tilt 90; sagittal = tilt 90 + rotation 90 (screen-right axis
    // rotated off the tilt axis so the plane cuts left/right instead of front/back).
    private var axialCut: CutPlane { CutPlane(pivotMM: model.cut.pivotMM, tiltDegrees: 0) }
    private var coronalCut: CutPlane { CutPlane(pivotMM: model.cut.pivotMM, tiltDegrees: 90) }
    private var sagittalCut: CutPlane { CutPlane(pivotMM: model.cut.pivotMM, tiltDegrees: 90, rotationDegrees: 90) }

    private func moveCrosshair(to p: SIMD3<Float>) {
        model.cut.pivotMM = p
    }

    var body: some View {
        VStack(spacing: 0) {
            if isCompactPortrait {
                Picker("Pane", selection: $singlePane) {
                    ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top], 12)

                singlePaneView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ScrollView { bottomControls.padding() }
                    .frame(maxHeight: 260)
            } else {
                grid
                bottomControls
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var singlePaneView: some View {
        switch singlePane {
        case .axial:
            pane(cut: axialCut, label: "Axial")
        case .sagittal:
            pane(cut: sagittalCut, label: "Sagittal")
        case .coronal:
            pane(cut: coronalCut, label: "Coronal")
        case .threeD:
            OverviewView(bundle: model.bundle, cut: $model.cut,
                         visibleLayerIDs: model.visibleLayerIDs, selectedFinding: model.selectedFinding)
        }
    }

    private var grid: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let cellW = (geo.size.width - spacing) / 2
            let cellH = (geo.size.height - spacing) / 2
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    pane(cut: axialCut, label: "Axial").frame(width: cellW, height: cellH)
                    pane(cut: sagittalCut, label: "Sagittal").frame(width: cellW, height: cellH)
                }
                HStack(spacing: spacing) {
                    pane(cut: coronalCut, label: "Coronal").frame(width: cellW, height: cellH)
                    OverviewView(bundle: model.bundle, cut: $model.cut,
                                 visibleLayerIDs: model.visibleLayerIDs, selectedFinding: model.selectedFinding)
                        .overlay(alignment: .topLeading) { paneLabel("3D") }
                        .frame(width: cellW, height: cellH)
                }
            }
        }
    }

    private func pane(cut: CutPlane, label: String) -> some View {
        ScanPane(bundle: model.bundle, cut: cut, mode: mode,
                 visibleLayerIDs: model.visibleLayerIDs, window: model.windowValues,
                 crosshair: model.cut.pivotMM, label: label, onMove: moveCrosshair)
    }

    private func paneLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(4)
            .background(.black.opacity(0.5))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(4)
    }

    // MARK: - Bottom controls: readout, window presets, organ legend

    private var bottomControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Show organs", isOn: $showOrgans)
                    .toggleStyle(.switch)
                Spacer()
                Text(readoutText).font(.caption.monospaced())
            }

            let presets = model.bundle.meta.windowPresets.keys.sorted()
            if !presets.isEmpty {
                HStack {
                    Picker("Window", selection: $model.windowPreset) {
                        ForEach(presets, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(windowReadout).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }

            if showOrgans {
                organLegend
            }
        }
    }

    private var windowReadout: String {
        let v = model.windowValues
        let level = v.first ?? 0
        let width = v.count > 1 ? v[1] : 0
        return "L \(Int(level)) / W \(Int(width))"
    }

    private var readoutText: String {
        let p = model.cut.pivotMM
        let ijk = voxelIndex(forMM: p)
        let hu = model.bundle.hu(at: ijk)
        return String(format: "%.0f, %.0f, %.0f mm · HU %d", p.x, p.y, p.z, hu)
    }

    /// mm -> nearest voxel index, clamped to the volume. Mirrors CaseBundle.textureCoord(forMM:)
    /// using the public meta fields (CaseBundle's own origin/spacing are private).
    private func voxelIndex(forMM p: SIMD3<Float>) -> SIMD3<Int> {
        let meta = model.bundle.meta
        let origin = SIMD3<Float>(Float(meta.originMM[0]), Float(meta.originMM[1]), Float(meta.originMM[2]))
        let spacing = SIMD3<Float>(Float(meta.spacingMM[0]), Float(meta.spacingMM[1]), Float(meta.spacingMM[2]))
        let dims = SIMD3<Int>(meta.dims[0], meta.dims[1], meta.dims[2])
        let v = (p - origin) / spacing
        func clamp(_ x: Float, _ d: Int) -> Int { min(max(Int(x.rounded()), 0), d - 1) }
        return SIMD3<Int>(clamp(v.x, dims.x), clamp(v.y, dims.y), clamp(v.z, dims.z))
    }

    private var organLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Organs").font(.headline)
            ForEach(model.peelOrderedLayers) { layer in
                Toggle(isOn: Binding(
                    get: { model.isVisible(layer) },
                    set: { model.setVisible(layer, $0) }
                )) {
                    HStack(spacing: 8) {
                        let c = layer.rgba
                        Circle()
                            .fill(Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z)))
                            .frame(width: 12, height: 12)
                        Text(layer.name).font(.caption)
                    }
                }
            }
        }
    }
}
