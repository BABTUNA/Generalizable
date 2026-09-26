import SwiftUI

struct CTSliceCanvas: View {
  var frame: ScanFrame?
  var overview = false

  var body: some View {
    GeometryReader { geometry in
      if let frame {
        let axis = overview ? frame.key.axis.overviewAxis : frame.key.axis
        let ratio = overview ? frame.overviewAspectRatio : frame.aspectRatio
        let available = CGSize(width: max(1, geometry.size.width - 48), height: max(1, geometry.size.height - 64))
        let width = min(available.width, available.height * ratio)
        let height = width / ratio
        ZStack {
          Color.black
          if let image = overview ? frame.overview : frame.image {
            Image(decorative: image, scale: 1)
              .resizable().interpolation(.high)
              .frame(width: width, height: height)
              .overlay {
                if overview {
                  GeometryReader { imageGeometry in
                    Path { path in
                      if frame.key.axis.rawValue == axis.verticalAxis {
                        let y = imageGeometry.size.height * (1 - frame.fraction)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: imageGeometry.size.width, y: y))
                      } else {
                        let x = imageGeometry.size.width * (1 - frame.fraction)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: imageGeometry.size.height))
                      }
                    }
                    .stroke(ScanStyle.accent, lineWidth: 1.5)
                  }
                }
              }
          }
          VStack {
            HStack(alignment: .top) {
              Text(overview ? "\(axis.title.uppercased()) LOCATOR" : axis.title.uppercased())
                .foregroundStyle(overview ? Color.secondary : ScanStyle.accent)
              Spacer()
              if !overview { Text(String(format: "%03d / %03d", frame.key.index + 1, frame.count)).foregroundStyle(.secondary) }
            }
            Spacer()
            if !overview {
              HStack {
                Text("\(frame.spacing.formatted(.number.precision(.fractionLength(1)))) mm spacing")
                Spacer()
                Text("W \(Int(frame.key.window.width)) · L \(Int(frame.key.window.level))")
              }
              .foregroundStyle(.secondary)
            }
          }
          .font(.caption2.monospaced())
          .padding(14)
          if !overview {
            HStack {
              Text(axis.leftLabel)
              Spacer()
              Text(axis.rightLabel)
            }
            .padding(.horizontal, 10)
            VStack {
              Text(axis.topLabel)
              Spacer()
              Text(axis.bottomLabel)
            }
            .padding(.vertical, 32)
          }
        }
        .font(.caption2.monospaced().weight(.medium))
        .foregroundStyle(.secondary)
      } else {
        ZStack { Color.black; ProgressView("Preparing scan…").tint(ScanStyle.accent) }
      }
    }
    .clipped()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(overview ? "\(frame?.key.axis.overviewAxis.title ?? "Scan") locator" : "\(frame?.key.axis.title ?? "CT") cross-section")
    .accessibilityValue(frame.map { "Slice \($0.key.index + 1) of \($0.count). \($0.key.window.rawValue) window. \(overview ? "Blue line marks the current slice." : "")" } ?? "Loading")
  }
}

enum ScanStyle {
  static var accent: Color { Color(red: 0.37, green: 0.67, blue: 1) }
  static var background: Color { Color(red: 0.045, green: 0.055, blue: 0.07) }
}
