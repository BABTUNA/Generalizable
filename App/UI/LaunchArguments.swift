// LaunchArguments.swift
// Parses scripted-screenshot launch arguments (PRD / task spec):
//   -case <name>   opens that case directly
//   -tilt <deg>    initial cut tilt in degrees
//   -hide <ids>    comma-separated layer ids to hide
//   -mode ct|layers
//   -select <id>   finding id to select

import Foundation

struct LaunchArguments {
    let caseName: String?
    let tiltDegrees: Double?
    let hiddenLayerIDs: Set<Int>?
    let mode: String?
    let selectFindingID: String?

    static var parsed: LaunchArguments { parse(CommandLine.arguments) }

    static func parse(_ args: [String]) -> LaunchArguments {
        func value(after flag: String) -> String? {
            guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
            return args[idx + 1]
        }

        let hiddenIDs: Set<Int>? = value(after: "-hide").map { raw in
            Set(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        }

        return LaunchArguments(
            caseName: value(after: "-case"),
            tiltDegrees: value(after: "-tilt").flatMap(Double.init),
            hiddenLayerIDs: hiddenIDs,
            mode: value(after: "-mode"),
            selectFindingID: value(after: "-select")
        )
    }

    /// Matches a `-select` launch-arg value against a decoded `CaseFinding`. A finding whose
    /// JSON `id` was numeric compares directly. A finding whose JSON `id` was a string (e.g.
    /// "core") was hashed into `CaseFinding.id` by `App/Core/CaseBundle.swift`'s private
    /// `stableHash` — this mirrors that exact FNV-1a algorithm so `-select core` still resolves.
    /// Keep this in sync if that hash ever changes (App/Core is not ours to edit or import from
    /// here beyond its public `CaseFinding.id`).
    static func matches(_ finding: CaseFinding, _ raw: String) -> Bool {
        if let asInt = Int(raw) { return finding.id == asInt }
        return finding.id == stableHash(raw)
    }

    private static func stableHash(_ s: String) -> Int {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a offset basis
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x1000_0000_1b3
        }
        return Int(h & 0x7fff_ffff)
    }
}
