// Compact AI result card shown on the axial pane.
import SwiftUI

struct AICard: View {
    @Bindable var state: ViewerState
    let ai: AIResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(.orange).font(.caption)
                Text(headline).font(.caption.weight(.semibold).monospacedDigit()).lineLimit(1)
                Button { jumpToPeak() } label: { Image(systemName: "scope").font(.caption) }
                    .accessibilityLabel("Jump to peak")
                Button { state.showAI.toggle() } label: {
                    Image(systemName: state.showAI ? "eye.fill" : "eye.slash").font(.caption)
                }
                .accessibilityLabel(state.showAI ? "Hide AI heatmap" : "Show AI heatmap")
            }
            .buttonStyle(.plain)
            Text("AI · research model, not a diagnosis").font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .fixedSize()
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "aiJumpToPeak") { jumpToPeak() } }
        #endif
    }

    private var headline: String {
        let name = ai.headlineClass.capitalized
        guard let p = ai.headlineProbability else { return name }
        return "\(name) \(String(format: "%.1f", p * 100))%"
    }

    func jumpToPeak() { AICard.jumpToPeak(state: state, ai: ai) }

    static func jumpToPeak(state: ViewerState, ai: AIResult) {
        guard let z = ai.peakSlice else { return }
        var c = state.cursor
        c.z = Float(z)
        if let xy = ai.heatCentroid(z: z) { c.x = xy.x.rounded(); c.y = xy.y.rounded() }
        state.cursor = state.geometry.clamp(c)
        state.showAI = true
    }
}
