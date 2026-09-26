import Foundation
import Observation

/// The patient's cases: the bundled sample plus imported reports, saved as JSON in Documents.
@MainActor
@Observable
final class CaseLibrary {
  var importedCases: [ScanCase] = []
  var isImporting = false
  var importMessage: String?
  var model: ClaudeModel {
    didSet { UserDefaults.standard.set(model.rawValue, forKey: "claudeModel") }
  }

  var hasAPIKey: Bool = APIKeyStore.shared.read() != nil

  private let fileURL = URL.documentsDirectory.appending(path: "cases.json")

  init() {
    model = UserDefaults.standard.string(forKey: "claudeModel").flatMap(ClaudeModel.init(rawValue:)) ?? .opus
    if let data = try? Data(contentsOf: fileURL), let cases = try? JSONDecoder().decode([ScanCase].self, from: data) {
      importedCases = cases
    }
  }

  func refreshKeyState() {
    hasAPIKey = APIKeyStore.shared.read() != nil
  }

  /// Imports a file picked by the user. Accesses the security-scoped URL only while copying the text out.
  func importFile(at url: URL) async -> ScanCase? {
    isImporting = true
    importMessage = nil
    defer { isImporting = false }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let text = try await TextExtractor.text(from: url)
      return await add(text: text, fileName: url.lastPathComponent)
    } catch {
      importMessage = error.localizedDescription
      return nil
    }
  }

  /// Interprets the bundled sample report, for trying the import flow without a file.
  func importSampleReport() async -> ScanCase? {
    guard let url = Bundle.main.url(forResource: "SampleReport", withExtension: "txt"),
          let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    isImporting = true
    defer { isImporting = false }
    return await add(text: text, fileName: "Sample radiology report.txt")
  }

  private func add(text: String, fileName: String) async -> ScanCase {
    let (scanCase, warning) = await ReportInterpreter.interpret(text: text, fileName: fileName, model: model)
    importMessage = warning
    importedCases.insert(scanCase, at: 0)
    save()
    return scanCase
  }

  func delete(_ offsets: IndexSet) {
    importedCases.remove(atOffsets: offsets)
    save()
  }

  private func save() {
    if let data = try? JSONEncoder().encode(importedCases) {
      try? data.write(to: fileURL, options: .atomic)
    }
  }
}
