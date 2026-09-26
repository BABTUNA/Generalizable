import SwiftUI

/// Feeds iPhone Duo hinge changes into the viewer. `onHingeChange` is iOS 27.1+; older systems ignore it.
/// Following Apple's guidance, derived state is reset whenever the hinge leaves the partially open state.
struct HingeReader: ViewModifier {
  var model: ViewerModel

  func body(content: Content) -> some View {
    if #available(iOS 27.1, *) {
      content.onHingeChange { _, context in
        guard let hinge = context.hinge else {
          model.updateHinge(angleDegrees: nil, partiallyOpen: false, hasHinge: false)
          return
        }
        model.updateHinge(angleDegrees: hinge.angle.degrees, partiallyOpen: hinge.status == .partiallyOpen, hasHinge: true)
      }
    } else {
      content
    }
  }
}
