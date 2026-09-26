import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
@preconcurrency import Vision

/// Pulls report text out of an imported file: PDFKit for PDFs, Vision text recognition for photos and scans,
/// and plain decoding for text files.
enum TextExtractor {
  enum Failure: LocalizedError {
    case unreadable
    case empty

    var errorDescription: String? {
      switch self {
      case .unreadable: "This file couldn't be opened."
      case .empty: "No text was found in this file. Try a PDF or a clear photo of the report."
      }
    }
  }

  static func text(from url: URL) async throws -> String {
    let type = UTType(filenameExtension: url.pathExtension) ?? .data
    let text: String
    if type.conforms(to: .pdf) {
      guard let doc = PDFDocument(url: url) else { throw Failure.unreadable }
      var pages: [String] = []
      for i in 0..<doc.pageCount {
        if let s = doc.page(at: i)?.string { pages.append(s) }
      }
      let joined = pages.joined(separator: "\n")
      if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        text = try await recognizePDFImages(doc)
      } else {
        text = joined
      }
    } else if type.conforms(to: .image) {
      guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { throw Failure.unreadable }
      text = try await recognize(image)
    } else {
      guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
      text = String(decoding: data, as: UTF8.self)
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw Failure.empty }
    return trimmed
  }

  private static func recognizePDFImages(_ doc: PDFDocument) async throws -> String {
    var out: [String] = []
    for i in 0..<min(doc.pageCount, 10) {
      guard let page = doc.page(at: i) else { continue }
      let bounds = page.bounds(for: .mediaBox)
      let thumb = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
      if let cg = thumb.cgImage { out.append(try await recognize(cg)) }
    }
    return out.joined(separator: "\n")
  }

  nonisolated private static func recognize(_ image: CGImage) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      let request = VNRecognizeTextRequest { request, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        let lines = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { $0.topCandidates(1).first?.string }
        continuation.resume(returning: lines.joined(separator: "\n"))
      }
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      do {
        // Runs synchronously on the caller's background task; the completion handler resumes the continuation.
        try VNImageRequestHandler(cgImage: image).perform([request])
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}
