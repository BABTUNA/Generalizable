import SwiftUI

/// Findings, the selected finding's explanation, layer peeling, and manual cut controls.
struct ControlPanelView: View {
  @Bindable var model: ViewerModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        findingsStrip
        if let finding = model.selectedFinding {
          FindingDetailView(finding: finding, isSample: model.scanCase.kind == .sample)
            .id(finding.id)
        } else {
          Text(model.scanCase.plainSummary)
            .font(.body)
        }
        LayerPeelView(model: model)
        cutControls
        if !model.scanCase.glossary.isEmpty {
          GlossaryView(terms: model.scanCase.glossary)
        }
        Text("Explains; doesn't diagnose. Locations are shown on a model body, not your own images.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Color(.systemGroupedBackground))
  }

  private var findingsStrip: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(model.scanCase.findings.count) finding\(model.scanCase.findings.count == 1 ? "" : "s")")
        .font(.headline)
      if model.scanCase.findings.isEmpty {
        Text(model.scanCase.plainSummary)
          .foregroundStyle(.secondary)
      }
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(Array(model.scanCase.findings.enumerated()), id: \.element.id) { index, finding in
            let selected = finding.id == model.selectedFindingID
            Button {
              withAnimation(.snappy) { model.select(finding) }
            } label: {
              HStack(spacing: 6) {
                Text("\(index + 1)")
                  .font(.caption.bold())
                  .frame(width: 20, height: 20)
                  .background(selected ? Color.white.opacity(0.25) : finding.tone.color.opacity(0.2), in: .circle)
                Text(finding.title)
                  .font(.subheadline.weight(.medium))
                  .lineLimit(1)
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .foregroundStyle(selected ? .white : .primary)
              .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.background), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }

  private var cutControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Cut")
        .font(.headline)
      VStack(alignment: .leading, spacing: 4) {
        Slider(value: $model.manualTilt, in: 0...90) {
          Text("Cut angle")
        } minimumValueLabel: {
          Image(systemName: "arrow.up.and.down.circle")
            .accessibilityLabel("From the feet")
        } maximumValueLabel: {
          Image(systemName: "person")
            .accessibilityLabel("From the front")
        }
        .disabled(model.isHingeDriving)
        Text(model.isHingeDriving ? "The hinge is controlling the angle." : "Angle \(Int(model.manualTilt.rounded()))°. On iPhone Duo, fold the phone instead.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 4) {
        Slider(value: $model.offsetMM, in: -80...80) {
          Text("Move the cut")
        } minimumValueLabel: {
          Image(systemName: "minus")
            .accessibilityLabel("Back")
        } maximumValueLabel: {
          Image(systemName: "plus")
            .accessibilityLabel("Forward")
        }
        Text("Moved \(Int(model.offsetMM.rounded())) mm from the finding. You can also drag the scan.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if model.mode == .ct {
        Picker("Window", selection: $model.windowPreset) {
          ForEach(WindowPreset.allCases) { preset in
            Text(preset.displayName).tag(preset)
          }
        }
        .pickerStyle(.segmented)
      }
    }
    .padding()
    .background(.background, in: .rect(cornerRadius: 16))
  }
}
