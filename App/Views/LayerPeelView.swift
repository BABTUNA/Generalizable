import SwiftUI

/// Toggles for the seven layers, outside to inside.
struct LayerPeelView: View {
  var model: ViewerModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Layers")
          .font(.headline)
        Spacer()
        Button("Show All") {
          withAnimation(.snappy) { model.hiddenLayers = [] }
        }
        .font(.subheadline)
        .disabled(model.hiddenLayers.isEmpty)
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
        ForEach(TissueLayer.allCases) { layer in
          let visible = !model.hiddenLayers.contains(layer)
          Toggle(isOn: Binding(get: { visible }, set: { _ in model.toggle(layer) })) {
            HStack(spacing: 6) {
              Circle()
                .fill(layer.color)
                .frame(width: 10, height: 10)
              Text(layer.displayName)
                .font(.subheadline)
                .lineLimit(1)
              Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
          }
          .toggleStyle(.button)
          .buttonStyle(.bordered)
          .tint(visible ? layer.color : .secondary)
          .accessibilityHint(layer.patientDescription)
        }
      }
      Text(model.mode == .ct ? "Layers apply in the Layers view. Switch off CT Scan to peel." : "Tap a layer to peel it away.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .background(.background, in: .rect(cornerRadius: 16))
  }
}
