// Owned by agent duo.
//
// Hinge-first iPhone Duo experience for the Generalizable viewer.
//
// Apple API surface used (verified in the iOS 27.1 SDK shipped with Xcode 27.1, not from memory).
// Paths relative to Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/
// iPhoneOS27.1.sdk/System/Library/Frameworks/:
// - `View.onHingeChange(isEnabled:_:)` (line ~24267), `DeviceHingeContext { hinge: DeviceHinge? }`,
//   `DeviceHinge { status: Status (.closed/.partiallyOpen/.fullyOpen), angle: Angle }` (~16741)
//     SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface
//   (UIKit equivalent: UIKit.framework/Headers/UIHinge.h, UIHingeInteraction.h — angle in radians)
// - `GeometryProxy.reservedRegions(kind: .division)` → `ReservedRegion.frame` (~4843), same
//   SwiftUICore .swiftinterface; UIKit: UIKit.framework/Headers/UIViewReservedRegion.h
// - `View.sceneAccessory { CameraCaptureAccessory { } ; ExternalNonInteractiveAccessory { } }`
//   (~19803, ~20779, ~20802) SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface
//   UIKit: UIKit.framework/Headers/UISceneAccessory.h, UIWindowScene.h. There is no general-purpose
//   "outer display" API: the outer panel is only reachable as a camera-capture accessory (system
//   decides, only while a capture session runs) or an external non-interactive display accessory.
// - `View.sensoryFeedback(_:trigger:condition:)` (~2549), same SwiftUI .swiftinterface — detent haptics.
//
// Layout precedent: split at the hinge's `.division` reserved region, the SDK's own contract for
// "a region where an element should divide into two separate regions" (UIViewReservedRegion.h),
// the same idea as Microsoft's Surface Duo TwoPaneView (microsoft/surface-duo-sdk) and Jetpack
// WindowManager FoldingFeature: separate content on each side of the fold, never across it.
//
// Hinge → anatomy mapping, kept consistent with the team's reference app (repo root):
//   App/Core/CutPlane.swift  `HingeMapping.tilt(forHingeAngle:)`: tilt = 180° − clamp(θ, 90...180);
//     tilt 0° = axial, tilt 90° = coronal, rotating about the patient's left–right axis (+x).
//   App/Core/CutPlane.swift  `HingeMapping.sliceFraction(forHingeAngle:closedDeg: 10, flatDeg: 180)`
//     for scrub mode (closed = inferior, flat = superior), used by App/Duo/HingeScrubDriver.swift.
//   App/Core/CutPlane.swift  `HingeSmoother` (exponential low-pass, alpha 0.35) — ported below.
//   App/Core/DuoFoldGeometry.swift: the upright display rises at elevation e = 180° − θ.
// Here: θ (0 = closed, 180 = flat).
//   Cut:   clipNormal = (0, sin t, cos t) through `state.cursor`, t = tilt. The renderer keeps
//          dot(n,p)+d <= 0 (Shaders/Volume.metal), so at t = 0 the superior half is removed and you
//          look down on the axial cut; at laptop (θ = 90°) the anterior half is removed (coronal).
//   Scrub: θ → axial slice via the team's sliceFraction.
// Posture layout (laptop / tent): upright half = axial 2D slice, flat half = 3D you can touch.

import SwiftUI
import simd

// MARK: - Posture model

enum DuoPosture: Equatable {
    case flat, folded, closed
}

enum HingeMapping: String, CaseIterable, Identifiable {
    case cut = "Cut", scrub = "Scrub"
    var id: String { rawValue }
    var hint: String {
        switch self {
        case .cut: "Fold to cut the 3D through the crosshair · flat = off, 90° = coronal"
        case .scrub: "Fold to scrub axial slices · closed = feet, flat = head"
        }
    }
}

/// Hinge state as the viewer consumes it — real (from `onHingeChange`) or simulated.
struct HingeReading: Equatable {
    /// Fold angle in degrees: 0 = closed, 180 = flat.
    var degrees: Double
    var isReal: Bool

    var posture: DuoPosture {
        if degrees < 12 { return .closed }
        if degrees > 165 { return .flat }
        return .folded
    }
}

enum HingeMath {
    /// Team A2 mapping (App/Core/CutPlane.swift `HingeMapping.tilt`): below 90° the tilt holds at 90°.
    static func tiltDegrees(hinge degrees: Double) -> Double { 180 - min(max(degrees, 90), 180) }

    /// Cutting-plane normal for a fold angle (see header). nil when flat (no cut).
    static func clipNormal(degrees: Double) -> SIMD3<Float>? {
        guard degrees <= 165 else { return nil }
        let t = Float(tiltDegrees(hinge: degrees) * .pi / 180)
        return simd_normalize(SIMD3<Float>(0, sin(t), cos(t)))
    }

    /// Team A12 mapping (App/Core/CutPlane.swift `HingeMapping.sliceFraction`, closedDeg 10).
    static func scrubFraction(degrees: Double) -> Float {
        Float(min(max((degrees - 10) / (180 - 10), 0), 1))
    }

    /// Named detents that get a haptic tick.
    static let detents: [(name: String, degrees: Double)] = [
        ("Flat", 180), ("Oblique", 135), ("Laptop", 90), ("Tent", 60),
    ]
    static func detent(at degrees: Double) -> String? {
        detents.first { abs($0.degrees - degrees) <= 3 }?.name
    }
}

/// Port of the team's `HingeSmoother` (App/Core/CutPlane.swift): exponential low-pass so hinge
/// jitter doesn't make the slice/cut flicker.
struct HingeLowPass {
    var alpha: Double = 0.35
    private var smoothed: Double?
    mutating func update(_ x: Double) -> Double {
        let next = smoothed.map { alpha * x + (1 - alpha) * $0 } ?? x
        smoothed = next
        return next
    }
    mutating func reset(_ x: Double) { smoothed = x }
}

// MARK: - Adaptive viewer

/// Wraps a viewer so it adapts to iPhone Duo fold/hinge state. On devices without hinge events
/// a small hinge pill (in the bottom safe area, or on the hinge seam when folded) simulates it.
struct DuoAdaptiveViewer<Content: View>: View {
    @Bindable var state: ViewerState
    @ViewBuilder var content: () -> Content

    @State private var realDegrees: Double?
    @State private var simDegrees: Double = 180
    @State private var simEnabled = false
    @State private var showSimulator = false
    @State private var forcePill = false
    @State private var mapping: HingeMapping = .cut

    private var usingSim: Bool { simEnabled || realDegrees == nil }
    private var reading: HingeReading {
        usingSim ? HingeReading(degrees: simDegrees, isReal: false)
                 : HingeReading(degrees: realDegrees ?? 180, isReal: true)
    }
    /// The pill auto-hides once the real hinge talks (triple-tap brings it back).
    private var pillVisible: Bool { usingSim || forcePill || showSimulator }

    var body: some View {
        GeometryReader { proxy in
            let hinge = DuoHingeGeometry(proxy: proxy)
            let split = hinge.split(in: proxy.size)
            ZStack {
                switch reading.posture {
                case .flat, .closed:
                    content()
                case .folded:
                    foldedLayout(split: split)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topLeading) {
                if pillVisible { pill(split: split, safe: proxy.safeAreaInsets, size: proxy.size) }
            }
            .overlay { if showSimulator { simulatorPanel } }
        }
        .animation(.snappy(duration: 0.25), value: reading.posture)
        .modifier(HingeObserver(degrees: $realDegrees))
        .modifier(DuoAccessories(state: state))
        .onChange(of: reading) { _, r in apply(r) }
        .onChange(of: mapping) { _, _ in apply(reading) }
        .sensoryFeedback(.impact(weight: .medium), trigger: HingeMath.detent(at: reading.degrees)) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: reading.posture)
        // Hidden trigger to re-show the pill on a real Duo; won't collide with slice drags.
        .simultaneousGesture(
            TapGesture(count: 3).onEnded { withAnimation { forcePill.toggle() } }
        )
    }

    // MARK: Hinge → state

    private func apply(_ r: HingeReading) {
        switch mapping {
        case .cut:
            let n = r.posture == .folded ? HingeMath.clipNormal(degrees: r.degrees) : nil
            if state.clipNormal != n { state.clipNormal = n }
        case .scrub:
            if state.clipNormal != nil { state.clipNormal = nil }
            guard r.posture == .folded else { return }
            let maxV = Float(state.sliceCount(for: .axial) - 1)
            state.setSlice(HingeMath.scrubFraction(degrees: r.degrees) * maxV, for: .axial)
        }
    }

    // MARK: Folded (laptop / tent): axial 2D on the upright half, 3D on the flat half

    @ViewBuilder
    private func foldedLayout(split: DuoHingeGeometry.Split) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black
            SliceView(plane: .axial, state: state)
                .frame(width: split.first.width, height: split.first.height)
                .clipped()
                .overlay(alignment: .topLeading) { badge("Axial · \(sliceLabel)") }
                .offset(x: split.first.minX, y: split.first.minY)
            threeD
                .frame(width: split.second.width, height: split.second.height)
                .clipped()
                .overlay(alignment: .topLeading) { badge("3D · \(cutLabel)") }
                .overlay(alignment: .bottom) { hintLine }
                .offset(x: split.second.minX, y: split.second.minY)
            HingeSeam(rect: split.seam, vertical: split.vertical, degrees: reading.degrees)
                .allowsHitTesting(false)
        }
    }

    /// Cut mode needs the ray-caster (it honours `clipNormal`); meshes don't clip.
    @ViewBuilder private var threeD: some View {
        if mapping == .cut || state.volumeMode != .meshes {
            VolumeView(state: state)
        } else {
            MeshView(state: state)
        }
    }

    private var cutLabel: String {
        mapping == .scrub ? "hinge scrubs axial" : "cut \(Int(HingeMath.tiltDegrees(hinge: reading.degrees).rounded()))° from axial"
    }
    private var sliceLabel: String {
        "\(Int(state.slice(for: .axial)) + 1)/\(state.sliceCount(for: .axial))"
    }

    private var hintLine: some View {
        Label(mapping.hint, systemImage: "rectangle.portrait.and.arrow.forward")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(.bottom, 8)
            .allowsHitTesting(false)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
            .allowsHitTesting(false)
    }

    // MARK: Hinge pill (simulator / demo fallback)

    /// Folded: centred on the hinge seam (no imagery there). Flat: in the bottom safe-area strip
    /// beside the home indicator, trailing, so it never sits on a pane.
    private func pill(split: DuoHingeGeometry.Split, safe: EdgeInsets, size: CGSize) -> some View {
        let label = HStack(spacing: 5) {
            Image(systemName: reading.isReal ? "laptopcomputer" : "hand.draw")
            Text(reading.posture == .flat && !reading.isReal ? "Fold" : "\(Int(reading.degrees.rounded()))°")
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 9).frame(height: 22)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        let pillW: CGFloat = 64, pillH: CGFloat = 22
        let origin: CGPoint
        if reading.posture == .folded {
            origin = split.vertical
                ? CGPoint(x: split.seam.midX - pillW / 2, y: size.height - safe.bottom - pillH - 8)
                : CGPoint(x: size.width - pillW - 12, y: split.seam.midY - pillH / 2)
        } else {
            // Bottom safe-area strip (home-indicator row); fall back to just inside the edge.
            let y = safe.bottom >= pillH ? size.height + (safe.bottom - pillH) / 2 : size.height - pillH - 2
            origin = CGPoint(x: size.width - pillW - 14, y: y)
        }
        return Button { withAnimation(.snappy) { showSimulator.toggle() } } label: { label }
            .buttonStyle(.plain)
            .frame(width: pillW, height: pillH)
            .offset(x: origin.x, y: origin.y)
            .accessibilityLabel("Hinge control")
    }

    private var simulatorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Hinge", systemImage: "rectangle.portrait.and.arrow.forward").font(.headline)
                Spacer()
                Text(reading.isReal ? "device hinge" : "simulated")
                    .font(.caption).foregroundStyle(.secondary)
                Button { withAnimation { showSimulator = false } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            HStack {
                Text("\(Int(simDegrees))°").monospacedDigit().frame(width: 44, alignment: .leading)
                Slider(value: $simDegrees, in: 0...180, step: 1) { _ in simEnabled = true }
            }
            HStack(spacing: 8) {
                ForEach(HingeMath.detents, id: \.name) { d in
                    Button(d.name) { simEnabled = true; withAnimation(.smooth) { simDegrees = d.degrees } }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            Picker("Mapping", selection: $mapping) {
                ForEach(HingeMapping.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Text("Folded: top = axial slice, bottom = 3D. \(mapping.hint).")
                .font(.caption2).foregroundStyle(.secondary)
            if realDegrees != nil {
                Toggle("Override device hinge", isOn: $simEnabled).font(.caption)
            }
        }
        .padding(14)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 12)
        .padding()
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

// MARK: - Hinge geometry (division reserved region)

struct DuoHingeGeometry {
    /// Hinge rect in the wrapper's local coordinates, if the system reports one.
    var division: CGRect?

    init(proxy: GeometryProxy) {
        if #available(iOS 27.1, *) {
            division = proxy.reservedRegions(kind: .division).first?.frame
        } else {
            division = nil
        }
    }

    struct Split { var first: CGRect; var second: CGRect; var seam: CGRect; var vertical: Bool }

    func split(in size: CGSize) -> Split {
        let bounds = CGRect(origin: .zero, size: size)
        let seam: CGRect
        if let d = division, !d.isEmpty || d.width > 0 || d.height > 0 {
            seam = d
        } else if size.width > size.height {
            seam = CGRect(x: size.width / 2 - 1, y: 0, width: 2, height: size.height)   // book
        } else {
            seam = CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2)   // laptop
        }
        let vertical = seam.height >= seam.width   // hinge runs top→bottom: side-by-side panes
        if vertical {
            let a = CGRect(x: 0, y: 0, width: max(seam.minX, 0), height: size.height)
            let b = CGRect(x: seam.maxX, y: 0, width: max(size.width - seam.maxX, 0), height: size.height)
            return Split(first: a.intersection(bounds), second: b.intersection(bounds), seam: seam, vertical: true)
        } else {
            let a = CGRect(x: 0, y: 0, width: size.width, height: max(seam.minY, 0))
            let b = CGRect(x: 0, y: seam.maxY, width: size.width, height: max(size.height - seam.maxY, 0))
            return Split(first: a.intersection(bounds), second: b.intersection(bounds), seam: seam, vertical: false)
        }
    }
}

/// A glowing seam along the hinge, tinted by how deep the cut is.
private struct HingeSeam: View {
    var rect: CGRect
    var vertical: Bool
    var degrees: Double
    var body: some View {
        let t = 1 - min(max(degrees / 180, 0), 1)
        let glow = Color(hue: 0.52 - 0.4 * t, saturation: 0.9, brightness: 1)
        Rectangle()
            .fill(glow.opacity(0.9))
            .frame(width: vertical ? max(rect.width, 2) : rect.width,
                   height: vertical ? rect.height : max(rect.height, 2))
            .shadow(color: glow, radius: 8)
            .offset(x: rect.minX, y: rect.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Real hinge events (iOS 27.1+)

private struct HingeObserver: ViewModifier {
    @Binding var degrees: Double?
    @State private var lowPass = HingeLowPass()
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, new in
                if let h = new.hinge {
                    // Status is authoritative for the endpoints; the angle can be coarse.
                    if h.status == .closed { lowPass.reset(0); degrees = 0 }
                    else if h.status == .fullyOpen { lowPass.reset(180); degrees = 180 }
                    else { degrees = lowPass.update(min(max(h.angle.degrees, 0), 180)) }
                } else {
                    degrees = nil
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Outer / external display content

private struct DuoAccessories: ViewModifier {
    let state: ViewerState
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.sceneAccessory {
                // Outer panel while a camera capture session runs (system decides placement).
                CameraCaptureAccessory { PatientFacingView(state: state) }
                // AirPlay / external display: colleague- or patient-facing, non-interactive.
                ExternalNonInteractiveAccessory { PatientFacingView(state: state) }
            }
        } else {
            content
        }
    }
}

/// Patient/colleague-facing view: the 3D anatomy with the findings called out.
struct PatientFacingView: View {
    @Bindable var state: ViewerState
    var body: some View {
        let lesions = state.visibleOrgans.filter(\.isLesion).sorted { $0.rawValue < $1.rawValue }
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            MeshView(state: state)
            VStack(alignment: .leading, spacing: 4) {
                if let ai = state.loaded.ai {
                    let p = ai.series.first { $0.name == ai.headlineClass }?.probability ?? 0
                    Text("\(ai.headlineClass.capitalized) hemorrhage · AI \(String(format: "%.1f", p * 100))%")
                        .font(.largeTitle.weight(.bold))
                }
                Text(state.loaded.info.title).font(.headline)
                if lesions.isEmpty {
                    Text("No lesion labelled").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(lesions) { o in
                        Label(o.displayName, systemImage: "circle.fill")
                            .foregroundStyle(o.color)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
        }
        .foregroundStyle(.white)
    }
}
