// RenderTestView.swift
// L3c's own test harness. Only pointed to from ContentView.swift on this branch (per
// docs/contracts/render-interface.md) — the Commander drops that wiring at merge.
//
// Launch arguments (scripts/build_sim.sh), so screenshots can be scripted:
//   -case <name>          default "body" if bundled, else "sun"
//   -tilt <degrees>        default 0
//   -mode ct|layers        default layers
//   -hide <comma ids>      label ids to hide, e.g. "1,2"

import SwiftUI

private func launchArgValue(_ flag: String) -> String? {
    let args = ProcessInfo.processInfo.arguments
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

struct RenderTestView: View {
    @State private var bundle: CaseBundle?
    @State private var loadError: String?
    @State private var cut: CutPlane
    @State private var mode: SliceMode
    @State private var hiddenIDs: Set<Int>
    @State private var tiltDegrees: Double

    private let caseName: String
    private let hingeDriver = HingeTiltDriver()

    init() {
        let requested = launchArgValue("-case")
        let available = Set(CaseBundle.availableBundled())
        let name: String
        if let requested, available.contains(requested) {
            name = requested
        } else if available.contains("body") {
            name = "body"
        } else {
            name = "sun"
        }
        caseName = name

        let tilt = Double(launchArgValue("-tilt") ?? "0") ?? 0
        _tiltDegrees = State(initialValue: tilt)
        _cut = State(initialValue: CutPlane(tiltDegrees: tilt))

        let modeArg = launchArgValue("-mode") ?? "layers"
        _mode = State(initialValue: modeArg == "ct" ? .ct : .layers)

        let hideArg = launchArgValue("-hide") ?? ""
        let hideSet = Set(hideArg.split(separator: ",").compactMap { Int($0) })
        _hiddenIDs = State(initialValue: hideSet)
    }

    var body: some View {
        Group {
            if let bundle {
                DuoAdaptiveLayout {
                    SliceView(bundle: bundle, cut: cut, mode: mode,
                              visibleLayerIDs: visibleLayerIDs(for: bundle),
                              selectedFinding: bundle.findings.first,
                              window: bundle.meta.windowPresets["soft"] ?? [40, 400])
                        .frame(minWidth: 200, minHeight: 200)
                } controls: {
                    controlsView(bundle: bundle)
                        .frame(minWidth: 200, minHeight: 200)
                }
                .onAppear {
                    hingeDriver.bind { newTilt in
                        cut.tiltDegrees = newTilt
                        tiltDegrees = newTilt
                    }
                    hingeDriver.start()
                }
            } else if let loadError {
                Text("Failed to load case \"\(caseName)\": \(loadError)")
                    .foregroundStyle(.red)
                    .padding()
            } else {
                ProgressView("Loading \(caseName)…")
                    .onAppear(perform: loadBundle)
            }
        }
        .onChange(of: bundle == nil) { _, _ in
            guard let bundle else { return }
            if let finding = bundle.findings.first {
                cut.select(finding)
                cut.tiltDegrees = tiltDegrees
            } else {
                cut.pivotMM = bundle.centerMM
            }
        }
    }

    private func visibleLayerIDs(for bundle: CaseBundle) -> Set<Int> {
        Set(bundle.layers.map { $0.id }).subtracting(hiddenIDs)
    }

    private func controlsView(bundle: CaseBundle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caseName).font(.headline)

            OverviewView(bundle: bundle, cut: $cut, visibleLayerIDs: visibleLayerIDs(for: bundle),
                         selectedFinding: bundle.findings.first)
                .frame(maxWidth: .infinity, minHeight: 320, maxHeight: 420)
                .clipped()

            Picker("Mode", selection: $mode) {
                Text("Layers").tag(SliceMode.layers)
                Text("CT").tag(SliceMode.ct)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Tilt \(Int(tiltDegrees))°")
                Slider(value: $tiltDegrees, in: 0...90, step: 1)
                    .onChange(of: tiltDegrees) { _, newValue in
                        cut.tiltDegrees = newValue
                    }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(bundle.layers) { layer in
                        Toggle(layer.name, isOn: Binding(
                            get: { !hiddenIDs.contains(layer.id) },
                            set: { isOn in
                                if isOn { hiddenIDs.remove(layer.id) } else { hiddenIDs.insert(layer.id) }
                            }
                        ))
                    }
                }
            }
        }
        .padding()
    }

    private func loadBundle() {
        do {
            bundle = try CaseBundle.bundled(caseName)
        } catch {
            loadError = "\(error)"
        }
    }
}
