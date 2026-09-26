enum ExplorerHingeMode: String, CaseIterable, Identifiable {
  case volume, hingeSlice, layerHeight

  var id: String { rawValue }
  var title: String {
    switch self {
    case .volume: "Volume"
    case .hingeSlice: "Hinge slice"
    case .layerHeight: "Layer height"
    }
  }
  var description: String {
    switch self {
    case .volume: "A centered, three-dimensional view. Drag to orbit."
    case .hingeSlice: "Two linked cross-sections. One stays flat; the other turns with the fold."
    case .layerHeight: "Keep the cut flat. Fold to travel up and down the volume."
    }
  }
}
