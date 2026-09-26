import Foundation
import Observation
import PDFKit
import UniformTypeIdentifiers

/// A temporary, on-device copy of the words in a report. It is never a diagnosis.
struct ImportedReport: Sendable {
  var title: String
  var text: String
  var sourceDescription: String
  var words: [WordMeaning]

  static var maximumBytes: Int { 10 * 1_024 * 1_024 }
  static var maximumCharacters: Int { 200_000 }

  static func pasted(_ text: String) throws -> ImportedReport {
    try make(title: "Pasted report", text: text, sourceDescription: "Text you provided")
  }

  static func read(from url: URL) throws -> ImportedReport {
    let hasAccess = url.startAccessingSecurityScopedResource()
    defer {
      if hasAccess { url.stopAccessingSecurityScopedResource() }
    }

    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
    guard values.isRegularFile != false else { throw ImportFailure.unsupported }
    if let size = values.fileSize, size > maximumBytes { throw ImportFailure.tooLarge }

    // Read at most the limit plus one byte, including when a provider omits its file size.
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
    guard data.count <= maximumBytes else { throw ImportFailure.tooLarge }

    let isPDF = contentType?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf"
    if isPDF {
      guard let document = PDFDocument(data: data) else { throw ImportFailure.unreadablePDF }
      guard !document.isLocked else { throw ImportFailure.lockedPDF }
      guard document.pageCount <= 200 else { throw ImportFailure.tooLong }
      var pages: [String] = []
      var characterCount = 0
      for index in 0..<document.pageCount {
        let pageText = document.page(at: index)?.string ?? ""
        characterCount += pageText.count
        guard characterCount <= maximumCharacters else { throw ImportFailure.tooLong }
        pages.append(pageText)
      }
      let text = pages.joined(separator: "\n\n")
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ImportFailure.imageOnlyPDF
      }
      return try make(
        title: url.lastPathComponent,
        text: text,
        sourceDescription: "Text extracted from PDF · \(document.pageCount) \(document.pageCount == 1 ? "page" : "pages")"
      )
    }

    guard contentType?.conforms(to: .plainText) == true || url.pathExtension.lowercased() == "txt" else {
      throw ImportFailure.unsupported
    }
    var decoded = String(data: data, encoding: .utf8)
    if decoded == nil, data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
      decoded = String(data: data, encoding: .utf16)
    }
    guard let text = decoded, !text.contains("\0") else { throw ImportFailure.unreadableText }
    return try make(title: url.lastPathComponent, text: text, sourceDescription: "Original text file")
  }

  private static func make(title: String, text: String, sourceDescription: String) throws -> ImportedReport {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportFailure.empty }
    guard text.count <= maximumCharacters else { throw ImportFailure.tooLong }
    let words = vocabulary.compactMap { definition -> WordMeaning? in
      guard let range = text.range(of: definition.pattern, options: [.regularExpression, .caseInsensitive]) else {
        return nil
      }
      let start = text.index(range.lowerBound, offsetBy: -110, limitedBy: text.startIndex) ?? text.startIndex
      let end = text.index(range.upperBound, offsetBy: 150, limitedBy: text.endIndex) ?? text.endIndex
      var match = definition
      match.excerpt = (start == text.startIndex ? "" : "…") + String(text[start..<end]) + (end == text.endIndex ? "" : "…")
      return match
    }
    return ImportedReport(title: title, text: text, sourceDescription: sourceDescription, words: words)
  }

  struct WordMeaning: Identifiable, Sendable {
    var term: String
    var meaning: String
    var pattern: String
    var sourceName: String
    var sourceURL: URL
    var excerpt: String = ""
    var id: String { term }
  }

  // Brief, general definitions checked against the linked public references.
  // Matching deliberately does not infer whether a condition is present or absent.
  private static var vocabulary: [WordMeaning] {
    [
      WordMeaning(term: "Nodule", meaning: "A growth or lump. The word alone does not say what caused it.", pattern: #"\bnodules?\b"#, sourceName: "National Cancer Institute", sourceURL: URL(string: "https://www.cancer.gov/publications/dictionaries/cancer-terms/def/nodule")!),
      WordMeaning(term: "Cyst", meaning: "A closed pocket of tissue that can contain fluid or other material.", pattern: #"\bcysts?\b"#, sourceName: "National Cancer Institute", sourceURL: URL(string: "https://www.cancer.gov/publications/dictionaries/cancer-terms/def/cyst")!),
      WordMeaning(term: "Lesion", meaning: "An area of tissue that is abnormal or damaged. It is a broad description, with many possible causes.", pattern: #"\blesions?\b"#, sourceName: "National Cancer Institute", sourceURL: URL(string: "https://www.cancer.gov/publications/dictionaries/cancer-terms/def/lesion")!),
      WordMeaning(term: "Benign", meaning: "A medical term meaning noncancerous. Read the complete sentence to understand how the report uses it.", pattern: #"\bbenign\b"#, sourceName: "National Cancer Institute", sourceURL: URL(string: "https://www.cancer.gov/publications/dictionaries/cancer-terms/def/benign")!),
      WordMeaning(term: "Calcification", meaning: "Calcium deposited in body tissue. The meaning depends on where and how it appears.", pattern: #"\bcalcifications?\b"#, sourceName: "National Cancer Institute", sourceURL: URL(string: "https://www.cancer.gov/publications/dictionaries/cancer-terms/def/calcification")!),
      WordMeaning(term: "Aneurysm", meaning: "An area of an artery that bulges or widens.", pattern: #"\baneurysms?\b"#, sourceName: "MedlinePlus", sourceURL: URL(string: "https://medlineplus.gov/aneurysms.html")!)
    ]
  }
}

@MainActor
@Observable
final class ReportReaderModel {
  var report: ImportedReport?
  var pastedText = ""
  var isReading = false
  var errorMessage: String?
  private var importGeneration = UUID()

  var canReadPastedText: Bool {
    !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isReading
  }

  func readPastedText() -> Bool {
    do {
      report = try ImportedReport.pasted(pastedText)
      pastedText = ""
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func importFile(_ result: Result<[URL], Error>) async {
    guard !isReading else { return }
    let generation = importGeneration
    do {
      guard let url = try result.get().first else { return }
      isReading = true
      defer {
        if generation == importGeneration { isReading = false }
      }
      let imported = try await Task.detached(priority: .userInitiated) {
        try ImportedReport.read(from: url)
      }.value
      guard generation == importGeneration else { return }
      report = imported
    } catch {
      guard generation == importGeneration else { return }
      if (error as NSError).code != NSUserCancelledError {
        errorMessage = (error as? ImportFailure)?.errorDescription
          ?? "This file could not be opened. Try a downloaded PDF or plain-text file, or paste the report's text."
      }
    }
  }

  func clear() {
    importGeneration = UUID()
    report = nil
    pastedText = ""
    errorMessage = nil
    isReading = false
  }
}

private enum ImportFailure: LocalizedError {
  case tooLarge, tooLong, unsupported, unreadablePDF, lockedPDF, imageOnlyPDF, unreadableText, empty

  var errorDescription: String? {
    switch self {
    case .tooLarge:
      "Choose a report of 10 MB or less, or paste the relevant text."
    case .tooLong:
      "This report is too long to display. Choose a PDF with no more than 200 pages, or paste fewer than 200,000 characters."
    case .unsupported:
      "Choose a PDF or a plain-text (.txt) report. Scan images and DICOM files cannot be read here."
    case .unreadablePDF:
      "This PDF could not be read. Try another copy, or paste the report's text."
    case .lockedPDF:
      "This PDF is password-protected. Open an unlocked copy, or paste the report's text."
    case .imageOnlyPDF:
      "This PDF has no selectable text. It may contain scanned pages. Copy the text from your patient portal and paste it here."
    case .unreadableText:
      "This text file uses an unsupported format. Try a UTF-8 text file, or paste the report's text."
    case .empty:
      "There is no text to read yet. Choose another report or paste some text."
    }
  }
}
