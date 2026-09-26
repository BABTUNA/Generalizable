// ViewerModel.swift
// @Observable view state for the viewer screen: bundle, cut plane, mode, hidden layers,
// selected finding, window preset. Owns the A1 cut-plane behaviour (via App/Core/CutPlane) and
// the peel/reset actions; the actual rendering lives behind SliceCanvas / OverviewCanvas.

import Foundation
import Observation

@Observable
final class ViewerModel {
    let bundle: CaseBundle
    var cut: CutPlane
    var mode: SliceMode
    var hiddenLayerIDs: Set<Int>
    var selectedFinding: CaseFinding?
    var windowPreset: String

    init(bundle: CaseBundle, launchArgs: LaunchArguments = .parsed) {
        self.bundle = bundle

        // Initial cut: pivot = bundle.centerMM, tilt 0; select the first finding if any.
        var initialCut = CutPlane(pivotMM: bundle.centerMM, tiltDegrees: 0)
        var initialFinding = bundle.findings.first
        if let rawSelect = launchArgs.selectFindingID,
           let match = bundle.findings.first(where: { LaunchArguments.matches($0, rawSelect) }) {
            initialFinding = match
        }
        if let finding = initialFinding {
            initialCut.select(finding)
        }
        if let tilt = launchArgs.tiltDegrees {
            initialCut.tiltDegrees = min(max(tilt, 0), 90)
        }

        self.cut = initialCut
        self.selectedFinding = initialFinding
        self.mode = launchArgs.mode?.lowercased() == "ct" ? .ct : .layers
        self.hiddenLayerIDs = launchArgs.hiddenLayerIDs ?? []

        let preferredPreset = bundle.name == "head" ? "brain" : "soft"
        if bundle.meta.windowPresets.keys.contains(preferredPreset) {
            self.windowPreset = preferredPreset
        } else {
            self.windowPreset = bundle.meta.windowPresets.keys.sorted().first ?? "soft"
        }
    }

    // MARK: - Layers

    /// Layers ordered outside-to-inside (A4 peel order).
    var peelOrderedLayers: [CaseLayer] {
        bundle.layers.sorted { $0.peelOrder < $1.peelOrder }
    }

    var visibleLayerIDs: Set<Int> {
        Set(bundle.layers.map(\.id)).subtracting(hiddenLayerIDs)
    }

    func isVisible(_ layer: CaseLayer) -> Bool {
        !hiddenLayerIDs.contains(layer.id)
    }

    func setVisible(_ layer: CaseLayer, _ visible: Bool) {
        if visible {
            hiddenLayerIDs.remove(layer.id)
        } else {
            hiddenLayerIDs.insert(layer.id)
        }
        // Toggling layer visibility never changes the cut (A4 "Peeling").
    }

    /// Hides the outermost layer that is still visible.
    func peelNextLayer() {
        guard let next = peelOrderedLayers.first(where: { !hiddenLayerIDs.contains($0.id) }) else { return }
        hiddenLayerIDs.insert(next.id)
    }

    func showAllLayers() {
        hiddenLayerIDs.removeAll()
    }

    // MARK: - Findings

    /// A1: selecting a finding sets the pivot to its anchor and resets the slice offset to 0.
    func select(_ finding: CaseFinding) {
        selectedFinding = finding
        cut.select(finding)
    }

    func returnToFinding() {
        cut.sliceOffsetMM = 0
    }

    // MARK: - Cut geometry

    /// Half the volume's extent projected onto the current cut normal (support function of the
    /// axis-aligned extent box along `cut.normal`), used to bound the slice-offset slider.
    var halfExtentAlongNormal: Float {
        let half = bundle.extentMM * 0.5
        let n = cut.normal
        let value = abs(n.x) * half.x + abs(n.y) * half.y + abs(n.z) * half.z
        return max(value, 1)
    }

    func clampSliceOffsetToExtent() {
        let half = halfExtentAlongNormal
        cut.sliceOffsetMM = min(max(cut.sliceOffsetMM, -half), half)
    }

    func resetView() {
        cut = CutPlane(pivotMM: bundle.centerMM, tiltDegrees: 0)
        if let finding = bundle.findings.first {
            selectedFinding = finding
            cut.select(finding)
        } else {
            selectedFinding = nil
        }
    }

    // MARK: - Rendering inputs

    var windowValues: [Double] {
        bundle.meta.windowPresets[windowPreset] ?? [0, 0]
    }
}
