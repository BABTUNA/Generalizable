import SwiftUI

struct SliceCanvasView: View {
  var session: ExplorerSession
  var isThumbnail = false
  var isReference = false
  var showsAnnotations = true

  private var displayedFrame: ExplorerSliceFrame? { isReference ? session.referenceFrame : session.frame }
  private var otherFrame: ExplorerSliceFrame? { isReference ? session.frame : session.referenceFrame }

  var body: some View {
    GeometryReader { geometry in
      let side = min(geometry.size.width, geometry.size.height)
      ZStack {
        RoundedRectangle(cornerRadius: isThumbnail ? 10 : 20).fill(Color.black.opacity(0.5))
        if let frame = displayedFrame {
          Image(decorative: frame.image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
          if let other = otherFrame,
             let segment = frame.plane.intersectionSegment(with: other.plane, imageSize: CGSize(width: side, height: side)) {
            Path { path in
              path.move(to: segment.0)
              path.addLine(to: segment.1)
            }
            .stroke(ExplorerPalette.mint.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
          }
          if abs(frame.plane.distance(to: frame.point.anchor)) < 7 {
            let point = frame.plane.imagePoint(of: frame.point.anchor, imageSize: CGSize(width: side, height: side))
            ZStack {
              Circle().stroke(.white, lineWidth: 1.2).frame(width: isThumbnail ? 13 : 24)
              Circle().fill(ExplorerPalette.mint).frame(width: 4, height: 4)
            }
            .position(x: point.x, y: point.y)
          }
        } else {
          ProgressView().tint(ExplorerPalette.mint)
        }
        if !isThumbnail, showsAnnotations, let frame = displayedFrame {
          VStack {
            HStack {
              Text(frame.subject == .patient ? "R" : "X−")
              Spacer()
              Text(isReference ? "REFERENCE · 0°" : (frame.height.map { "Z \(Int($0)) mm" } ?? "\(Int(frame.angle))°"))
              Spacer()
              Text(frame.subject == .patient ? "L" : "X+")
            }
            Spacer()
            Text(frame.height.map { "Horizontal slice · \(Int($0)) mm" } ?? (abs(frame.offset) < 0.5 ? frame.point.title : "\(Int(frame.offset)) mm from focus"))
              .padding(9)
              .background(.ultraThinMaterial, in: Capsule())
          }
          .font(.caption.monospaced())
          .foregroundStyle(.white.opacity(0.75))
          .padding(12)
        }
      }
      .frame(width: side, height: side)
      .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(isReference ? "Reference" : "Live") \(displayedFrame?.mode == .ct ? "grayscale CT" : "colored") cross-section")
    .accessibilityValue(accessibleValue)
  }

  private var accessibleValue: String {
    guard let frame = displayedFrame else { return "Preparing slice" }
    if let height = frame.height { return "Horizontal slice at \(Int(height)) millimeters from the bottom" }
    return "\(Int(frame.angle)) degree cut, \(Int(frame.offset)) millimeters from \(frame.point.title)"
  }
}
