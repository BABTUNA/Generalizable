import SwiftUI

struct ExplorerInspectorView: View {
  @Bindable var session: ExplorerSession
  var section: ExplorerInspectorSection
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        switch section {
        case .finding: findingSections
        case .layers: layerSections
        case .controls: controlSections
        case .help: helpSections
        }
      }
      .navigationTitle(section.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", systemImage: "checkmark") { dismiss() }
        }
      }
    }
    .tint(ExplorerPalette.mint)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private var findingSections: some View {
    Group {
      Section {
        Picker("Focus", selection: Binding(get: { session.pointIndex }, set: { session.selectPoint($0) })) {
          ForEach(Array(session.subject.points.enumerated()), id: \.element.id) { index, point in
            Text(point.title).tag(index)
          }
        }
        .pickerStyle(.menu)
        LabeledContent("Location", value: session.point.location)
        LabeledContent("Measurement", value: session.point.measurement)
      }
      Section("In plain words") {
        Text(session.point.summary).font(.headline)
        Text(session.point.detail).foregroundStyle(.secondary)
      }
      Section(session.subject == .patient ? "A question for your doctor" : "Something to explore") {
        Text(session.point.question)
      }
      Section {
        Text(session.subject == .patient
          ? "Synthetic teaching scan. This is not your anatomy or a diagnosis."
          : "Illustrative model. Dimensions and spacing are simplified.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  private var layerSections: some View {
    Section {
      ForEach(activeLayers) { layer in
        Toggle(isOn: Binding(get: { !session.hiddenLayers.contains(layer) }, set: { visible in
          if visible { session.hiddenLayers.remove(layer) } else { session.hiddenLayers.insert(layer) }
        })) {
          HStack(spacing: 12) {
            Circle().fill(layer.color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(layerTitle(layer))
          }
        }
        .accessibilityHint(session.subject == .patient ? layer.patientDescription : "Show or hide this region of the model")
      }
    } header: {
      Text("\(activeLayers.filter { session.visibleLayers.contains($0) }.count) of \(activeLayers.count) visible")
    } footer: {
      Text(session.mode == .ct
        ? "These controls isolate layers in the 3D model. The CT slice keeps all tissues visible for comparison."
        : "Hide outer layers to see the structure underneath.")
    }
  }

  private var controlSections: some View {
    Group {
      Section(session.hingeMode.title) {
        ExplorerAdjustmentBar(session: session)
        if session.hingeMode == .volume {
          Button("Center volume", systemImage: "viewfinder") { session.cameraReset += 1 }
        } else if session.hingeMode == .hingeSlice {
          VStack(spacing: 6) {
            LabeledContent("Slice position", value: abs(session.sliceOffset) < 0.5 ? "Through focus" : "\(Int(session.sliceOffset)) mm")
            Slider(value: $session.sliceOffset, in: -160...160) { Text("Slice position") }
              .accessibilityValue("\(Int(session.sliceOffset)) millimeters from focus")
          }
        } else {
          Button("Return to finding", systemImage: "scope") {
            session.layerHeight = Double(session.point.anchor.z)
            session.followsFold = false
          }
        }
      }
      if session.hingeMode != .volume {
        Section {
          Toggle("Follow the fold", isOn: Binding(get: { session.followsFold }, set: { follows in
            session.followsFold = follows
            if follows, let angle = session.hingeAngle { session.applyHinge(angle) }
          }))
        } footer: {
          Text(session.hingeAvailable
            ? "Folding iPhone Duo adjusts the active cut. Moving its slider switches to touch control."
            : "On iPhone Duo, folding adjusts the cut. The sliders work on every device.")
        }
        if session.subject == .patient {
          Section {
            Picker("Slice appearance", selection: $session.mode) {
              Text("Color layers").tag(RenderOptions.Mode.layers)
              Text("CT scan").tag(RenderOptions.Mode.ct)
            }
            .pickerStyle(.menu)
          }
        }
      }
      Section {
        Button("Reset view", systemImage: "arrow.counterclockwise") { session.reset() }
      }
    }
  }

  private var helpSections: some View {
    Group {
      ForEach(ExplorerHingeMode.allCases) { mode in
        Section(mode.title) {
          Text(mode.description)
          if mode == .hingeSlice {
            Text("Both screens show a cross-section of the same location. At 180°, the cuts align. At 90°, they are perpendicular. The line marks where the two planes meet.")
              .foregroundStyle(.secondary)
          } else if mode == .layerHeight {
            Text("The cut stays horizontal: 180° places it at the bottom; 90° raises it to the top.")
              .foregroundStyle(.secondary)
          }
        }
      }
      Section("One viewer. Three worlds.") {
        Text("Choose a patient scan, the Sun, or a circuit board. Select a point of interest to move the cut there, then hide layers to reveal what is underneath.")
      }
      Section("About the teaching scan") {
        Text("The colored anatomy and CT are synthetic educational illustrations. Imported reports remain separate from this model; the model is never presented as your scan.")
      }
    }
  }

  private var activeLayers: [TissueLayer] {
    switch session.subject {
    case .patient: TissueLayer.allCases
    case .sun: [.skin, .fat, .muscle, .bone, .blood]
    case .circuit: [.muscle, .organs, .bone, .blood]
    }
  }

  private func layerTitle(_ layer: TissueLayer) -> String {
    switch session.subject {
    case .patient: layer.displayName
    case .sun: SolarVolumeSource.displayName(for: layer)
    case .circuit: CircuitVolumeSource.displayName(for: layer)
    }
  }
}

enum ExplorerInspectorSection: String, Identifiable {
  case finding, layers, controls, help

  var id: String { rawValue }
  var title: String {
    switch self {
    case .finding: "Focus"
    case .layers: "Visible layers"
    case .controls: "View controls"
    case .help: "How to explore"
    }
  }
}
