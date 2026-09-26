// AnalysisCard.swift
// DEMO ONLY. Shows the cached Hugging Face vision-model description for a case
// (App/Cases/<case>/analysis.json, written by scripts/ml/hf_analyze.py). The app never calls the
// network: the result is precomputed so the demo works offline. Research description only —
// no diagnosis, no prognosis.

import SwiftUI

struct CaseAnalysis: Decodable {
    struct Result: Decodable {
        var structures: [String]?
        var observations: [String]?
        var image_quality: String?
        var confidence: String?
        var caveat: String?
    }
    var model: String
    var created_utc: String?
    var views: [String]?
    var result: Result

    static func bundled(_ caseName: String) -> CaseAnalysis? {
        guard let url = Bundle.main.resourceURL?
                .appendingPathComponent("Cases/\(caseName)/analysis.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CaseAnalysis.self, from: data)
    }
}

struct AnalysisCard: View {
    let caseName: String
    @State private var analysis: CaseAnalysis?
    @State private var expanded = true

    var body: some View {
        Group {
            if let a = analysis {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("AI description", systemImage: "sparkles")
                            .font(.headline)
                        Spacer()
                        if let c = a.result.confidence {
                            Text("confidence: \(c)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let s = a.result.structures, !s.isEmpty {
                        Text("Sees: " + s.joined(separator: ", "))
                            .font(.subheadline)
                    }
                    ForEach(Array((a.result.observations ?? []).enumerated()), id: \.offset) { _, o in
                        Text("• " + o).font(.subheadline)
                    }
                    Text("\(a.model.split(separator: "/").last.map(String.init) ?? a.model) via Hugging Face, on \((a.views ?? []).joined(separator: " + ")) slices. \(a.result.caveat ?? "Automated research description — not a diagnosis.")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("AI description, research only, not a diagnosis")
            }
        }
        .task(id: caseName) { analysis = CaseAnalysis.bundled(caseName) }
    }
}
