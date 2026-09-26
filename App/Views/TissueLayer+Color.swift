import SwiftUI

extension TissueLayer {
  var color: Color {
    Color(red: Double(rgba.x) / 255, green: Double(rgba.y) / 255, blue: Double(rgba.z) / 255)
  }
}

extension Finding.Tone {
  var color: Color {
    switch self {
    case .reassuring: .green
    case .routine: .blue
    case .attention: .orange
    }
  }
}
