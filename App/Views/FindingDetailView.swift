import SwiftUI

/// The plain-language card for one finding, with a place to ask a follow-up question.
struct FindingDetailView: View {
  @Environment(CaseLibrary.self) private var library
  var finding: Finding
  var isSample: Bool
  @State private var ask = AskModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        Label(finding.tone.displayName, systemImage: finding.tone.symbolName)
          .font(.caption.weight(.semibold))
          .foregroundStyle(finding.tone.color)
        Text(finding.title)
          .font(.title2.bold())
        Text(finding.plainSummary)
          .font(.body)
      }

      Text(finding.whatItMeans)
        .font(.callout)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 4) {
        Text("What the report says")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Text("\u{201C}\(finding.clinicalPhrase)\u{201D}")
          .font(.callout.italic())
        Text(finding.region.displayName)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if !finding.questionsForDoctor.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("Questions to ask your doctor")
            .font(.subheadline.weight(.semibold))
          ForEach(finding.questionsForDoctor, id: \.self) { question in
            Label(question, systemImage: "questionmark.bubble")
              .font(.callout)
          }
        }
      }

      askSection
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background, in: .rect(cornerRadius: 16))
  }

  private var askSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Ask about this…", text: $ask.question)
          .textFieldStyle(.roundedBorder)
          .submitLabel(.send)
          .onSubmit { ask.ask(about: finding, model: library.model) }
        Button("Ask", systemImage: "arrow.up.circle.fill") {
          ask.ask(about: finding, model: library.model)
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .disabled(ask.question.trimmingCharacters(in: .whitespaces).isEmpty || ask.isStreaming)
      }
      if ask.isStreaming && ask.answer.isEmpty {
        ProgressView()
      }
      if !ask.answer.isEmpty {
        Text(ask.answer)
          .font(.callout)
          .textSelection(.enabled)
        if let source = ask.source {
          Text("Answered by \(source). General information, not medical advice.")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      if let error = ask.errorMessage {
        Label(error, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}
