import SwiftUI

struct ExplorerAdjustmentBar: View {
  @Bindable var session: ExplorerSession

  var body: some View {
    Group {
      switch session.hingeMode {
      case .volume:
        Text("Drag to rotate · Pinch to zoom")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .multilineTextAlignment(.center)
      case .hingeSlice:
        VStack(spacing: 4) {
          readout("Hinge angle", value: "\(Int((180 - session.tiltDegrees).rounded()))°")
          Slider(value: Binding(get: { 180 - session.tiltDegrees }, set: {
            session.followsFold = false
            session.tiltDegrees = 180 - $0
          }), in: 90...180) {
            Text("Hinge angle")
          } minimumValueLabel: {
            Text("90°").font(.caption2)
          } maximumValueLabel: {
            Text("180°").font(.caption2)
          }
          .accessibilityValue("\(Int((180 - session.tiltDegrees).rounded())) degree hinge, \(Int(session.tiltDegrees.rounded())) degree cut")
        }
      case .layerHeight:
        VStack(spacing: 4) {
          readout("Layer height", value: "\(Int(session.layerHeight)) mm")
          Slider(value: Binding(get: { session.layerHeight }, set: {
            session.followsFold = false
            session.layerHeight = $0
          }), in: 0...576) {
            Text("Layer height")
          } minimumValueLabel: {
            Text("Bottom").font(.caption2)
          } maximumValueLabel: {
            Text("Top").font(.caption2)
          }
          .accessibilityValue("\(Int(session.layerHeight)) millimeters from the bottom")
        }
      }
    }
    .tint(ExplorerPalette.mint)
  }

  private func readout(_ title: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Text(value).fontWeight(.semibold).monospacedDigit()
    }
    .font(.subheadline)
    .accessibilityHidden(true)
  }
}
