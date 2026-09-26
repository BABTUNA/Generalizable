// Slice probability track: per-axial-slice model probability as a heat strip beside the
// right-edge scrubber. Same vertical mapping as SliceScrubber (top = highest z; thumb centre
// at 9 + frac·(h-18)), colours from the NiiVue inferno LUT (see AILoader.swift).
import SwiftUI

struct AIProbabilityTrack: View {
    @Bindable var state: ViewerState
    let ai: AIResult

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height, w = geo.size.width
            let n = max(state.sliceCount(for: .axial), 1)
            Canvas { ctx, _ in
                func y(_ z: Int) -> CGFloat { 9 + (n > 1 ? 1 - CGFloat(z) / CGFloat(n - 1) : 0) * max(h - 18, 0) }
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 3),
                         with: .color(.black.opacity(0.35)))
                let rowH = max(max(h - 18, 1) / CGFloat(n) + 0.5, 1)
                for (z, p) in ai.sliceProbability.enumerated() where z < n && p > 0.02 {
                    let c = AILoader.infernoLUT[Int(min(max(p, 0), 1) * 255)]
                    let bw = max(w * CGFloat(p), 1.5)
                    ctx.fill(Path(CGRect(x: w - bw, y: y(z) - rowH / 2, width: bw, height: rowH)),
                             with: .color(Color(red: Double(c.x) / 255, green: Double(c.y) / 255, blue: Double(c.z) / 255)))
                }
                if let pk = ai.peakSlice {
                    let py = y(pk)
                    var tri = Path()
                    tri.move(to: CGPoint(x: -5, y: py - 4)); tri.addLine(to: CGPoint(x: 0, y: py))
                    tri.addLine(to: CGPoint(x: -5, y: py + 4)); tri.closeSubpath()
                    ctx.fill(tri, with: .color(.orange))
                }
                let cy = y(Int(state.slice(for: .axial)))
                ctx.fill(Path(CGRect(x: -2, y: cy - 1, width: w + 4, height: 2)), with: .color(.white))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let f = min(max((v.location.y - 9) / max(h - 18, 1), 0), 1)
                state.setSlice(Float(((1 - f) * CGFloat(n - 1)).rounded()), for: .axial)
            })
            .accessibilityLabel("AI slice probability")
        }
    }
}
