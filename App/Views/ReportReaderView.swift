import SwiftUI
import UniformTypeIdentifiers

struct ReportReaderView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var model = ReportReaderModel()
  @State private var showingImporter = false
  @State private var showingPaste = false

  var body: some View {
    NavigationStack {
      List {
        if let report = model.report {
          reportSections(report)
        } else {
          introduction
        }
        if model.isReading {
          Section {
            ProgressView("Reading on this device…")
              .padding(.vertical, 8)
          }
        }
        importActions
      }
      .navigationTitle("Report glossary")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") {
            model.clear()
            dismiss()
          }
            .labelStyle(.iconOnly)
        }
      }
      .navigationDestination(isPresented: $showingPaste) {
        pasteEditor
      }
      .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf, .plainText], allowsMultipleSelection: false) { result in
        Task { await model.importFile(result) }
      }
      .alert("Couldn’t read this report", isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )) {
        Button("OK", role: .cancel) { model.errorMessage = nil }
      } message: {
        Text(model.errorMessage ?? "Please try another report.")
      }
    }
    .onDisappear { model.clear() }
  }

  private var introduction: some View {
    Section {
      VStack(alignment: .leading, spacing: 18) {
        Image(systemName: "text.page.badge.magnifyingglass")
          .font(.system(size: 42, weight: .light))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)

        Text("Your report,\na little clearer.")
          .font(.largeTitle.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)

        Text("Bring the written report from your scan. Explore plain-language definitions alongside the original words, and prepare questions for your care team.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Label("Read privately on this device", systemImage: "lock")
          .font(.subheadline.weight(.medium))
      }
      .padding(.vertical, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .listRowBackground(Color.clear)
    }
  }

  private var importActions: some View {
    Section {
      Button(model.report == nil ? "Choose a report" : "Choose another report", systemImage: "document.badge.plus") {
        showingImporter = true
      }
      .disabled(model.isReading)

      Button("Paste report text", systemImage: "square.and.pencil") {
        showingPaste = true
      }
      .disabled(model.isReading)

      if model.report != nil {
        Button("Remove this report", systemImage: "trash", role: .destructive) { model.clear() }
          .disabled(model.isReading)
      }
    } footer: {
      Text("PDF or plain text, up to 10 MB. This glossary processes your report on this device without uploading or saving it. Close this reader to clear it. The separate Case library has its own import and storage settings.")
    }
  }

  @ViewBuilder
  private func reportSections(_ report: ImportedReport) -> some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        Label(report.title, systemImage: "text.document")
          .font(.headline)
        Text(report.sourceDescription)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 5)

      NavigationLink {
        ScrollView {
          Text(report.text)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Original wording")
        .navigationBarTitleDisplayMode(.inline)
      } label: {
        Text("Read the full report")
      }
    } footer: {
      Text("PDF text extraction can change spacing and reading order. Check the original document if something looks unclear.")
    }

    Section {
      Text("These are word matches, not findings or a diagnosis. A phrase such as “no cyst” still matches “cyst”. Only your care team can explain what the full report means for you.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      if report.words.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("No glossary matches yet")
            .font(.headline)
          Text("This small glossary doesn’t cover every term. You can still read the original wording and use the questions below.")
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      } else {
        ForEach(report.words) { word in
          DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
              Text(word.meaning)
                .textSelection(.enabled)

              VStack(alignment: .leading, spacing: 5) {
                Text("MATCHED TEXT")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
                Text(word.excerpt)
                  .font(.callout)
                  .textSelection(.enabled)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(12)
              .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

              Link("Definition reference · \(word.sourceName)", destination: word.sourceURL)
                .font(.footnote)
            }
            .padding(.vertical, 8)
          } label: {
            Text(word.term)
              .font(.headline)
          }
        }
      }
    } header: {
      Text("Words found in your report")
    }

    Section("Bring these questions") {
      Text("What does the impression mean in my situation?")
      Text("Which findings, if any, need follow-up?")
      Text("How does this compare with my previous scans?")
      Text("What should happen next, and when?")
    }

    Section {
      Text("The anatomy explorer uses an educational example. It is not created from your report or your scan.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var pasteEditor: some View {
    @Bindable var model = model
    return Form {
      Section {
        TextEditor(text: $model.pastedText)
          .frame(minHeight: 260)
          .accessibilityLabel("Report text")
          .textInputAutocapitalization(.sentences)
          .autocorrectionDisabled()
      } header: {
        Text("Paste the exact wording")
      } footer: {
        Text("You can copy text from your patient portal or report. Include complete sentences so you can read each word in context.")
      }

      Section {
        Button("Read this report", systemImage: "text.page.badge.magnifyingglass") {
          if model.readPastedText() { showingPaste = false }
        }
        .disabled(!model.canReadPastedText)
      } footer: {
        Text("Kept in memory while this glossary is open. This reader does not upload or save your text.")
      }
    }
    .navigationTitle("Paste your report")
    .navigationBarTitleDisplayMode(.inline)
  }
}
