// ViewerView.swift
// The main viewer screen: DuoLayout(slice: SliceCanvas, controls: <this file's controls panel>).
// Mode switch, layer peel controls, findings/points-of-interest, tilt & slice sliders, reset,
// and the window preset picker. Everything here talks to App/Core types (CaseBundle, CutPlane,
// CaseLayer, CaseFinding) and the render-interface stubs via the RenderBindings typealiases.

import SwiftUI

struct ViewerView: View {
    @Bindable var model: ViewerModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private enum CompactTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case controls = "Controls"
        var id: String { rawValue }
    }

    // `-panel controls` is a screenshot-verification convenience (not part of the scripted-
    // screenshot launch-argument spec) so build_sim.sh can capture the controls tab directly.
    @State private var compactTab: CompactTab = CommandLine.arguments.contains("controls") ? .controls : .overview

    var body: some View {
        DuoLayout {
            SliceCanvas(
                bundle: model.bundle,
                cut: model.cut,
                mode: model.mode,
                visibleLayerIDs: model.visibleLayerIDs,
                selectedFinding: model.selectedFinding,
                window: model.windowValues
            )
        } controls: {
            controlsArea
        }
        .onChange(of: model.cut.tiltDegrees) { _, _ in
            model.clampSliceOffsetToExtent()
        }
    }

    // MARK: - Controls area (overview + panel)

    @ViewBuilder
    private var controlsArea: some View {
        if horizontalSizeClass == .compact {
            VStack(spacing: 0) {
                Picker("Panel", selection: $compactTab) {
                    ForEach(CompactTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top], 12)

                switch compactTab {
                case .overview:
                    overviewCanvas
                case .controls:
                    ScrollView { controlsPanel.padding() }
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    overviewCanvas
                    controlsPanel
                }
                .padding()
            }
        }
    }

    private var overviewCanvas: some View {
        OverviewCanvas(
            bundle: model.bundle,
            cut: $model.cut,
            visibleLayerIDs: model.visibleLayerIDs,
            selectedFinding: model.selectedFinding
        )
        .frame(minHeight: 180)
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            modeSection
            layersSection
            findingsSection
            tiltSection
            sliceSection
            resetAndWindowSection
        }
    }

    // MARK: - Mode

    private var modeSection: some View {
        Picker("View mode", selection: $model.mode) {
            Text("Layers — what patients see").tag(SliceMode.layers)
            Text("CT scan — what doctors see").tag(SliceMode.ct)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("View mode")
    }

    // MARK: - Layers

    private var layersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Layers").font(.headline)

            ForEach(model.peelOrderedLayers) { layer in
                Toggle(isOn: Binding(
                    get: { model.isVisible(layer) },
                    set: { model.setVisible(layer, $0) }
                )) {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(color(for: layer))
                            .frame(width: 14, height: 14)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(layer.name)
                            Text(layer.blurb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityLabel("\(layer.name) layer")
                .accessibilityValue(model.isVisible(layer) ? "Visible" : "Hidden")
            }

            HStack {
                Button("Peel next layer") { model.peelNextLayer() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("All layers") { model.showAllLayers() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func color(for layer: CaseLayer) -> Color {
        let c = layer.rgba
        return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }

    // MARK: - Findings / points of interest

    private var findingsSectionTitle: String {
        (model.bundle.name == "head" || model.bundle.name == "body") ? "Findings" : "Points of interest"
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(findingsSectionTitle).font(.headline)

            if model.bundle.findings.isEmpty {
                Text("No findings in this case")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.bundle.findings) { finding in
                    Button {
                        model.select(finding)
                    } label: {
                        HStack {
                            Text(finding.title)
                            Spacer()
                            if model.selectedFinding?.id == finding.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityLabel(finding.title)
                    .accessibilityAddTraits(model.selectedFinding?.id == finding.id ? .isSelected : [])
                }

                if let selected = model.selectedFinding {
                    selectedFindingDetail(selected)
                }
            }
        }
    }

    private func selectedFindingDetail(_ finding: CaseFinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(finding.title).font(.subheadline).bold()
            Text("≈ \(mmString(2 * finding.radiusMM)) mm")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(finding.explanation)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text("From public research data reads — not a diagnosis")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tilt

    private var tiltSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cut tilt \(Int(model.cut.tiltDegrees.rounded()))°").font(.headline)
            Slider(value: $model.cut.tiltDegrees, in: 0...90, step: 1)
                .accessibilityLabel("Cut tilt")
                .accessibilityValue("\(Int(model.cut.tiltDegrees.rounded())) degrees")

            // TODO(Commander, after L3c merge): wire the real hinge here, e.g.:
            //   @State private var hingeTiltDriver = HingeTiltDriver()
            //   .onAppear {
            //       hingeTiltDriver.bind { model.cut.tiltDegrees = $0 }
            //       hingeTiltDriver.start()
            //   }
            //   .onDisappear { hingeTiltDriver.stop() }
            // `isHingeAvailable` below is a stub (always false) until that lands.
            if isHingeAvailable {
                Text("Fold the Duo to change the cut angle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Stub: no HingeTiltDriver exists in this build yet (App/Duo lands from L3c). See the TODO above.
    private var isHingeAvailable: Bool { false }

    // MARK: - Slice

    private var sliceSection: some View {
        let half = model.halfExtentAlongNormal
        return VStack(alignment: .leading, spacing: 6) {
            Text("Slice offset \(mmString(Double(model.cut.sliceOffsetMM))) mm").font(.headline)
            Slider(value: $model.cut.sliceOffsetMM, in: -half...half)
                .accessibilityLabel("Slice offset")
                .accessibilityValue("\(mmString(Double(model.cut.sliceOffsetMM))) millimeters")
            Button("Return to finding") { model.returnToFinding() }
                .buttonStyle(.bordered)
                .disabled(model.cut.sliceOffsetMM == 0)
        }
    }

    // MARK: - Reset + window preset

    private var resetAndWindowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Reset View") { model.resetView() }
                .buttonStyle(.borderedProminent)

            let presets = model.bundle.meta.windowPresets.keys.sorted()
            if !presets.isEmpty {
                Picker("Window preset", selection: $model.windowPreset) {
                    ForEach(presets, id: \.self) { preset in
                        Text(preset.capitalized).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Window preset")
            }
        }
    }
}

private func mmString(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
}
