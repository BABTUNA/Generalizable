import SwiftUI

/// A side view of the body with the current cut drawn through it, so you can see the cut swing as the phone folds.
/// The reference line is 3D Slicer's slice-intersection display (vtkMRMLSliceIntersectionRepresentation2D).
struct SideMapView: View {
  var model: ViewerModel

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      ZStack {
        if let image = model.sideImage {
          Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: size.width, height: size.height)
        }
        if let (a, b) = model.sidePlane.intersectionSegment(with: model.plane, imageSize: size) {
          Path { path in
            path.move(to: a)
            path.addLine(to: b)
          }
          .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
          .shadow(color: .accentColor.opacity(0.8), radius: 4)
        }
        Circle()
          .fill(.white)
          .frame(width: 6, height: 6)
          .position(model.sidePlane.imagePoint(of: model.pivot, imageSize: size))
      }
      .clipShape(.rect(cornerRadius: 8))
    }
    .padding(4)
    .background(.black.opacity(0.55), in: .rect(cornerRadius: 12))
    .overlay(alignment: .bottom) {
      Text("Side")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.8))
        .padding(.bottom, 6)
    }
    .accessibilityElement()
    .accessibilityLabel("Side view of the body showing where the cut passes. \(model.viewDescription).")
  }
}
