// HingeScrubDriver.swift
// DEMO ONLY. PRD A12: in Scan mode the iPhone Duo hinge scrubs through the CT slices.
// Wraps a HingeAngleSource (App/Core/CutPlane.swift). The source comes from
// HingeSourceFactory, which Bitrig points at the real DuoHingeSource once the iOS 27.1 SDK
// is available. Until then ManualOnlyHingeSource is used, so `isHingeAvailable` stays false
// and the on-screen fold control drives the same value.

import Foundation
import Observation

@Observable
final class HingeScrubDriver {
    private let source: HingeAngleSource
    private var smoother: HingeSmoother = { var s = HingeSmoother(); s.alpha = 0.5; return s }()
    private var onFraction: ((Double) -> Void)?

    /// True once a real hinge reading has arrived.
    private(set) var isHingeAvailable = false
    /// Latest opening angle in degrees (0 = closed, 180 = flat), from the hinge or the control.
    private(set) var openingDegrees: Double = 180

    init(source: HingeAngleSource = HingeSourceFactory.make()) {
        self.source = source
    }

    func bind(_ onFraction: @escaping (Double) -> Void) { self.onFraction = onFraction }

    func start() {
        source.onAngle = { [weak self] degrees in
            guard let self else { return }
            self.isHingeAvailable = true
            self.apply(openingDegrees: self.smoother.update(degrees))
        }
        source.start()
    }

    func stop() {
        source.stop()
        source.onAngle = nil
    }

    /// Used by the on-screen fold control (and by the hinge, via start()).
    func apply(openingDegrees d: Double) {
        openingDegrees = min(max(d, 0), 180)
        onFraction?(HingeMapping.sliceFraction(forHingeAngle: openingDegrees))
    }
}

/// The single plug-in point for the real hinge. Bitrig: once the iOS 27.1 SDK is available, return
/// `DuoHingeSource()` here behind `if #available(iOS 27.1, *)`. It must call `onAngle` with the
/// OPENING angle in DEGREES: convert UIKit/SwiftUI radians via HingeConvention (PRD A10).
enum HingeSourceFactory {
    static func make() -> HingeAngleSource {
        ManualOnlyHingeSource()
    }
}
