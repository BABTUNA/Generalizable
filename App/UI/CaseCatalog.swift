// CaseCatalog.swift
// Cheap, list-screen-only reads of each bundled case's layers.json / meta.json — deliberately not
// a full CaseBundle.load (which also reads ct.raw/labels.raw and can be tens of MB), since the
// case list and credits sheet only need names, layer counts, and source/license strings.

import Foundation

struct CaseSummary: Identifiable, Hashable {
    let id: String
    let displayName: String
    let layerCount: Int
}

struct CaseCredit: Identifiable, Hashable {
    let id: String
    let displayName: String
    let source: String
    let license: String
}

enum CaseCatalog {
    /// Display order and names (task spec). Only entries whose bundle actually exists are shown.
    private static let order: [(name: String, displayName: String)] = [
        ("head", "Head CT"),
        ("body", "Body CT"),
        ("sun", "The Sun"),
        ("circuit", "Circuit board"),
    ]

    static func displayName(for name: String) -> String {
        order.first(where: { $0.name == name })?.displayName ?? name.capitalized
    }

    static func availableSummaries() -> [CaseSummary] {
        availableEntries().map { entry in
            CaseSummary(id: entry.name, displayName: entry.displayName, layerCount: layerCount(for: entry.name))
        }
    }

    static func credits() -> [CaseCredit] {
        availableEntries().compactMap { entry in
            guard let meta = readMetaSourceLicense(for: entry.name) else { return nil }
            return CaseCredit(id: entry.name, displayName: entry.displayName, source: meta.source, license: meta.license)
        }
    }

    private static func availableEntries() -> [(name: String, displayName: String)] {
        let available = Set(CaseBundle.availableBundled())
        return order.filter { available.contains($0.name) }
    }

    private static func casesDirectory() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Cases")
    }

    private static func layerCount(for name: String) -> Int {
        guard let url = casesDirectory()?.appendingPathComponent("\(name)/layers.json"),
              let data = try? Data(contentsOf: url),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return 0 }
        return array.count
    }

    private struct MetaSourceLicense: Decodable {
        let source: String
        let license: String
    }

    private static func readMetaSourceLicense(for name: String) -> MetaSourceLicense? {
        guard let url = casesDirectory()?.appendingPathComponent("\(name)/meta.json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(MetaSourceLicense.self, from: data)
    }
}
