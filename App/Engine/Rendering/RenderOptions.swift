import Foundation

/// What a slice image should show.
struct RenderOptions: Equatable, Hashable {
  enum Mode: String, Equatable, Hashable {
    /// Coloured, named layers: what a patient can read.
    case layers
    /// Grayscale synthetic CT: what a radiologist reads.
    case ct
  }

  var mode: Mode = .layers
  var hiddenLayers: Set<TissueLayer> = []
  var windowPreset: WindowPreset = .abdomen
}
