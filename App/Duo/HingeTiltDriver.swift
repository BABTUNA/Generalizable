// HingeTiltDriver.swift
// Drives the cut-plane tilt from a HingeAngleSource (App/Core/CutPlane.swift), via the
// A2 mapping + smoother. Defaults to ManualOnlyHingeSource, so `isHingeAvailable` is
// false and the manual control remains the only way to set tilt on non-Duo hardware.
// The real Duo-backed source (App/Duo/DuoHingeSource.swift, #available(iOS 27.1)) is
// added later by Bitrig and passed in here — this driver doesn't know or care which
// source it's wrapping.

import Foundation
import Observation

@Observable
final class HingeTiltDriver {
    private let source: HingeAngleSource
    private var smoother = HingeSmoother()
    private var setTilt: ((Double) -> Void)?

    private(set) var isHingeAvailable: Bool = false
    private(set) var lastHingeAngle: Double?

    init(source: HingeAngleSource = ManualOnlyHingeSource()) {
        self.source = source
    }

    func bind(_ setTilt: @escaping (Double) -> Void) {
        self.setTilt = setTilt
    }

    func start() {
        source.onAngle = { [weak self] angle in
            guard let self else { return }
            self.isHingeAvailable = true
            self.lastHingeAngle = angle
            let tilt = HingeMapping.tilt(forHingeAngle: angle)
            let smoothed = self.smoother.update(tilt)
            self.setTilt?(smoothed)
        }
        source.start()
    }

    func stop() {
        source.stop()
        source.onAngle = nil
    }
}
