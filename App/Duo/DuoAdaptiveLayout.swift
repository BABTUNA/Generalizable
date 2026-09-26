// DuoAdaptiveLayout.swift
// Adaptive layout for the slice + controls pair: side by side when horizontally regular
// or landscape, stacked with the slice on top otherwise. Kept deliberately simple —
// the full Duo table/book/tent pose set is future work; this covers iPhone/iPad/Duo
// well enough for the demo.

import SwiftUI

struct DuoAdaptiveLayout<Slice: View, Controls: View>: View {
    @ViewBuilder let slice: Slice
    @ViewBuilder let controls: Controls

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(@ViewBuilder slice: () -> Slice, @ViewBuilder controls: () -> Controls) {
        self.slice = slice()
        self.controls = controls()
    }

    private var sideBySide: Bool {
        horizontalSizeClass == .regular || verticalSizeClass == .compact
    }

    var body: some View {
        Group {
            if sideBySide {
                HStack(spacing: 0) {
                    slice
                    controls
                }
            } else {
                VStack(spacing: 0) {
                    slice
                    controls
                }
            }
        }
    }
}
