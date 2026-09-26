// RenderStubs.swift
// DEMO ONLY. Placeholder views with the exact init signatures of the contract's SliceView,
// OverviewView and DuoAdaptiveLayout (docs/contracts/render-interface.md), so App/UI can be built
// and screenshotted before L3c's real renderer lands. Referenced only via the typealiases in
// App/UI/RenderBindings.swift — never reference these type names directly elsewhere.

import SwiftUI

struct SliceViewStub: View {
    let bundle: CaseBundle
    let cut: CutPlane
    let mode: SliceMode
    let visibleLayerIDs: Set<Int>
    let selectedFinding: CaseFinding?
    let window: [Double]

    init(bundle: CaseBundle, cut: CutPlane, mode: SliceMode, visibleLayerIDs: Set<Int>,
         selectedFinding: CaseFinding?, window: [Double]) {
        self.bundle = bundle
        self.cut = cut
        self.mode = mode
        self.visibleLayerIDs = visibleLayerIDs
        self.selectedFinding = selectedFinding
        self.window = window
    }

    var body: some View {
        StubPlaceholder(title: "SliceView (stub)", lines: [
            "Case: \(bundle.name)",
            "Mode: \(mode == .layers ? "layers" : "ct")",
            "Tilt \(Int(cut.tiltDegrees.rounded()))°  Offset \(mmString(cut.sliceOffsetMM)) mm",
            "Hidden layers: \(bundle.layers.count - visibleLayerIDs.count) of \(bundle.layers.count)",
            "Finding: \(selectedFinding?.title ?? "none")",
            "Window: \(window.map { mmString($0) }.joined(separator: " / "))",
        ])
    }
}

struct OverviewViewStub: View {
    let bundle: CaseBundle
    @Binding var cut: CutPlane
    let visibleLayerIDs: Set<Int>
    let selectedFinding: CaseFinding?

    init(bundle: CaseBundle, cut: Binding<CutPlane>, visibleLayerIDs: Set<Int>,
         selectedFinding: CaseFinding?) {
        self.bundle = bundle
        self._cut = cut
        self.visibleLayerIDs = visibleLayerIDs
        self.selectedFinding = selectedFinding
    }

    var body: some View {
        StubPlaceholder(title: "OverviewView (stub)", lines: [
            "Case: \(bundle.name)",
            "Mode: 3D peel",
            "Tilt \(Int(cut.tiltDegrees.rounded()))°  Offset \(mmString(cut.sliceOffsetMM)) mm",
            "Hidden layers: \(bundle.layers.count - visibleLayerIDs.count) of \(bundle.layers.count)",
            "Finding: \(selectedFinding?.title ?? "none")",
        ])
    }
}

struct DuoAdaptiveLayoutStub<Slice: View, Controls: View>: View {
    private let slice: Slice
    private let controls: Controls

    init(@ViewBuilder slice: () -> Slice, @ViewBuilder controls: () -> Controls) {
        self.slice = slice()
        self.controls = controls()
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                HStack(spacing: 0) {
                    slice.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    controls.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    slice.frame(maxWidth: .infinity, maxHeight: proxy.size.height * 0.4)
                    Divider()
                    controls.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

private func mmString(_ value: Float) -> String {
    mmString(Double(value))
}

private func mmString(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
}

private struct StubPlaceholder: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5])))
        .padding(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(([title] + lines).joined(separator: ". "))
    }
}
