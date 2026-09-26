// RenderBindings.swift
// Owned by L3b (UI). This is the ONE file the Commander edits to swap the stub
// SliceView/OverviewView/DuoAdaptiveLayout for L3c's real implementations after the merge.
// See docs/contracts/render-interface.md.

import SwiftUI

// MARK: - Contract type temporarily duplicated here

/// `SliceMode` is defined by L3c's real `App/Render/SliceView.swift` per the render-interface
/// contract ("what patients see" / "what doctors see"). This copy exists only so App/UI can
/// compile against the stubs before L3c's branch merges.
///
/// COMMANDER: delete this enum once `App/Render/SliceView.swift` lands — the real file defines
/// the same type, and keeping both would be a duplicate-symbol build error.
enum SliceMode {
    case layers
    case ct
}

// MARK: - Swap point
//
// COMMANDER: after merging L3c's branch, change these three lines (and delete the
// `SliceMode` enum above) to point at the real views:
//
//   typealias SliceCanvas = SliceView
//   typealias OverviewCanvas = OverviewView
//   typealias DuoLayout = DuoAdaptiveLayout

typealias SliceCanvas = SliceViewStub
typealias OverviewCanvas = OverviewViewStub
typealias DuoLayout = DuoAdaptiveLayoutStub
