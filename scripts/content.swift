#!/usr/bin/env swift
// Keeps the GitHub page, the site and llms.txt in step with docs/features.json.
//   swift scripts/content.swift           writes every generated block
//   swift scripts/content.swift --check   changes nothing; fails if a block is stale or the touchpoints disagree
//   swift scripts/content.swift --assets  prints build script, fixed and versioned file of each released platform
//   swift scripts/content.swift --title   prints this version's release title, from CHANGELOG.md
//   swift scripts/content.swift --notes   prints this version's release notes: its CHANGELOG.md entry and the downloads
// A generated block sits between <!-- nuva:NAME --> and <!-- /nuva:NAME -->; the text around it is written by hand.
import Foundation

struct Localized<T: Decodable>: Decodable { let en: T; let pt: T }

struct Badge: Decodable { let label: String; let alt: String; let link: String }
struct Platform: Decodable {
    let id: String
    let name: Localized<String>
    let status: String
    let `public`: Bool
    let asset: String
    let buildScript: String
    let termsMention: String?
    let releaseNote: String?
    let requires: Localized<[String]>
    let schemaOS: Localized<String>
    let badge: BadgeSet
    let requirementBadges: [RequirementBadge]
    struct BadgeSet: Decodable { let en: Badge; let pt: Badge; let color: String; let logo: String }
    struct RequirementBadge: Decodable { let label: String; let alt: String }
    var released: Bool { status == "released" }
}
struct Feature: Decodable {
    let id: String
    let en: String
    let pt: String
    let status: [String: String]
    let why: [String: String]
    enum Keys: String, CodingKey { case id, en, pt, why }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        en = try c.decode(String.self, forKey: .en)
        pt = try c.decode(String.self, forKey: .pt)
        why = try c.decodeIfPresent([String: String].self, forKey: .why) ?? [:]
        // Every other key is a platform id.
        let all = try decoder.singleValueContainer().decode([String: JSONValue].self)
        status = all.compactMapValues { if case .string(let s) = $0 { s } else { nil } }
            .filter { !["id", "en", "pt"].contains($0.key) }
    }
}
enum JSONValue: Decodable {
    case string(String), other
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self = (try? c.decode(String.self)).map(JSONValue.string) ?? .other
    }
}
struct Matrix: Decodable { let platforms: [Platform]; let features: [Feature] }

let check = CommandLine.arguments.contains("--check")
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
func read(_ path: String) -> String? { try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
var problems: [String] = []

guard let data = read("docs/features.json")?.data(using: .utf8),
      let matrix = try? JSONDecoder().decode(Matrix.self, from: data) else {
    print("docs/features.json is missing or isn't valid"); exit(1)
}
let version = read("project.yml").flatMap { yml in
    yml.firstMatch(of: try! Regex(#"MARKETING_VERSION: *"?([0-9.]+)"?"#)).flatMap { $0[1].substring.map(String.init) }
} ?? "?"
let shown = matrix.platforms.filter(\.public)
let released = matrix.platforms.filter(\.released)

// MARK: - Release (read-only modes for scripts/release.sh)

/// "NuVa.dmg" → "NuVa-1.11.dmg": the file the update notices look for.
func versioned(_ asset: String) -> String {
    let ext = (asset as NSString).pathExtension
    return (asset as NSString).deletingPathExtension + "-\(version)." + ext
}
/// The CHANGELOG.md entry for this version: its heading and its text.
func changelogEntry() -> (title: String, body: String)? {
    guard let log = read("CHANGELOG.md") else { return nil }
    let entries = log.components(separatedBy: "\n## ").dropFirst()
    guard let entry = entries.first(where: { $0.hasPrefix(version + " ") || $0.hasPrefix(version + "\n") }) else { return nil }
    let lines = entry.split(separator: "\n", omittingEmptySubsequences: false)
    return (String(lines[0]), lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
}
if CommandLine.arguments.contains("--assets") {
    for p in released { print([p.buildScript, p.asset, versioned(p.asset)].joined(separator: "\t")) }
    exit(0)
}
if CommandLine.arguments.contains("--title") || CommandLine.arguments.contains("--notes") {
    guard let entry = changelogEntry() else { print("CHANGELOG.md has no entry for \(version)"); exit(1) }
    if CommandLine.arguments.contains("--title") { print(entry.title); exit(0) }
    let downloads = released.filter(\.public).map { p in
        "- \(p.name.en): **\(p.asset)** (\(p.requires.en.joined(separator: ", ")))." + (p.releaseNote.map { " " + $0 } ?? "")
    }
    print(entry.body + "\n\n**Download**\n" + downloads.joined(separator: "\n"))
    exit(0)
}

// MARK: - The matrix itself

var seen = Set<String>()
for f in matrix.features {
    if !seen.insert(f.id).inserted { problems.append("features.json: \(f.id) appears twice") }
    for p in matrix.platforms {
        switch f.status[p.id] {
        case "yes", "planned": break
        case "n/a": if f.why[p.id] == nil { problems.append("features.json: \(f.id) is n/a on \(p.id) without a why") }
        case let s?: problems.append("features.json: \(f.id) on \(p.id) is \"\(s)\" (yes, planned or n/a)")
        case nil: problems.append("features.json: \(f.id) has no status for \(p.id)")
        }
    }
    for key in f.status.keys where !matrix.platforms.contains(where: { $0.id == key }) {
        problems.append("features.json: \(f.id) names an unknown platform \(key)")
    }
}

// MARK: - Blocks

func cell(_ status: String?, pt: Bool) -> String {
    switch status {
    case "yes": "✓"
    case "planned": pt ? "mais tarde" : "later"
    default: "—"
    }
}
func table(pt: Bool) -> String {
    let rows = matrix.features.filter { f in shown.contains { f.status[$0.id] != "n/a" } }
    var lines = ["| | " + shown.map { pt ? $0.name.pt : $0.name.en }.joined(separator: " | ") + " |",
                 "|---|" + String(repeating: ":-:|", count: shown.count)]
    for f in rows {
        lines.append("| \(pt ? f.pt : f.en) | " + shown.map { cell(f.status[$0.id], pt: pt) }.joined(separator: " | ") + " |")
    }
    lines.append("")
    lines.append(pt ? "*Mais tarde*: a caminho. —: não se aplica nessa plataforma."
                    : "*Later*: on its way. —: doesn't apply on that platform.")
    return lines.joined(separator: "\n")
}
func downloadBadges(pt: Bool) -> String {
    released.filter(\.public).map { p in
        let b = pt ? p.badge.pt : p.badge.en
        let file = p.asset.replacingOccurrences(of: "-", with: "--")
        return "  <a href=\"\(b.link)\"><img src=\"https://img.shields.io/badge/\(b.label)-\(file)-\(p.badge.color)?style=for-the-badge&logo=\(p.badge.logo)&logoColor=white\" alt=\"\(b.alt)\"></a>"
    }.joined(separator: "\n")
}
func requirementBadges() -> String {
    released.filter(\.public).flatMap(\.requirementBadges).map {
        "  <img src=\"https://img.shields.io/badge/\($0.label)-2B2D30?style=flat-square\" alt=\"\($0.alt)\">"
    }.joined(separator: "\n")
}
func siteMeta(pt: Bool) -> String {
    let needs = released.filter(\.public).flatMap { pt ? $0.requires.pt : $0.requires.en }
    let parts = [pt ? "Versão <span class=\"version\">\(version)</span>" : "Version <span class=\"version\">\(version)</span>"]
        + needs + [pt ? "gratuita, MIT" : "free, MIT"]
    return "    <p class=\"meta\">" + parts.joined(separator: " · ") + "</p>"
}
func llmsPlatforms() -> String {
    "## What each app does\n\n" + table(pt: false)
}
func llmsDownloads() -> String {
    released.filter(\.public).map {
        "- [Download \($0.asset)](https://github.com/martinsmdnuno/nuva/releases/latest/download/\($0.asset))"
    }.joined(separator: "\n")
}
func schemaOS(pt: Bool) -> String {
    released.filter(\.public).map { pt ? $0.schemaOS.pt : $0.schemaOS.en }.joined(separator: "; ")
}

struct Target { let file: String; let blocks: [String: String]; let jsonKeys: [String: String] }
let targets = [
    Target(file: "README.md", blocks: [
        "downloads": downloadBadges(pt: false), "requirements": requirementBadges(), "platforms": table(pt: false),
        "downloads-pt": downloadBadges(pt: true), "platforms-pt": table(pt: true),
    ], jsonKeys: [:]),
    Target(file: "site/index.html", blocks: ["meta": siteMeta(pt: false)],
           jsonKeys: ["operatingSystem": schemaOS(pt: false), "softwareVersion": version]),
    Target(file: "site/pt/index.html", blocks: ["meta": siteMeta(pt: true)],
           jsonKeys: ["operatingSystem": schemaOS(pt: true), "softwareVersion": version]),
    Target(file: "site/llms.txt", blocks: ["platforms": llmsPlatforms(), "downloads": llmsDownloads()], jsonKeys: [:]),
]

for t in targets {
    guard var text = read(t.file) else { problems.append("\(t.file) is missing"); continue }
    let before = text
    for (name, content) in t.blocks.sorted(by: { $0.key < $1.key }) {
        let open = "<!-- nuva:\(name) -->", close = "<!-- /nuva:\(name) -->"
        guard let a = text.range(of: open), let b = text.range(of: close, range: a.upperBound..<text.endIndex) else {
            problems.append("\(t.file): no \(open) … \(close) markers"); continue
        }
        let fresh = "\n" + content + "\n"
        if String(text[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) != fresh.trimmingCharacters(in: .whitespacesAndNewlines) {
            if check { problems.append("\(t.file): block \(name) is stale") }
        }
        // Keep the closing marker's indentation as it is.
        let lineStart = text[..<b.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? b.lowerBound
        text.replaceSubrange(a.upperBound..<lineStart, with: fresh)
    }
    for (key, value) in t.jsonKeys.sorted(by: { $0.key < $1.key }) {
        let pattern = try! Regex("\"\(key)\": \"[^\"]*\"")
        guard let m = text.firstMatch(of: pattern) else { problems.append("\(t.file): no \"\(key)\" in its JSON-LD"); continue }
        let fresh = "\"\(key)\": \"\(value)\""
        if check && String(text[m.range]) != fresh { problems.append("\(t.file): \"\(key)\" is stale") }
        text.replaceSubrange(m.range, with: fresh)
    }
    if !check && text != before {
        try! text.write(to: root.appendingPathComponent(t.file), atomically: true, encoding: .utf8)
        print("wrote \(t.file)")
    }
}

// MARK: - Checks across touchpoints (they never write)

// One version: the Android app reads project.yml; the changelog's newest entry is this version.
if let gradle = read("android/app/build.gradle.kts"), !gradle.contains("project.yml") {
    problems.append("android/app/build.gradle.kts no longer takes its version from project.yml")
}
// The newest entry may be ahead: the next release's entry is written before scripts/release.sh bumps project.yml.
func numbers(_ v: Substring) -> [Int] { v.split(separator: ".").compactMap { Int($0) } }
if let log = read("CHANGELOG.md") {
    let entries = log.matches(of: try! Regex(#"\n## ([0-9.]+)"#)).compactMap { $0[1].substring }
    if let top = entries.first, numbers(top).lexicographicallyPrecedes(numbers(Substring(version))) {
        problems.append("CHANGELOG.md: newest entry is \(top), older than \(version) in project.yml")
    }
    if !entries.contains(Substring(version)) { problems.append("CHANGELOG.md has no entry for \(version)") }
}

// Every download link names a file a released platform's build script makes and the release uploads.
let release = read("CLAUDE.md")?.split(separator: "\n").first { $0.contains("gh release create vX") } ?? ""
for p in released {
    if read(p.buildScript).map({ !$0.contains(p.asset) }) ?? true { problems.append("\(p.buildScript) doesn't make \(p.asset)") }
    if !release.contains(p.asset) { problems.append("CLAUDE.md: the gh release create line doesn't upload \(p.asset)") }
}
let assets = Set(released.map(\.asset))
let pages = ["README.md", "site/llms.txt", "TERMS.md"] + (FileManager.default.enumerator(atPath: root.appendingPathComponent("site").path)?
    .compactMap { $0 as? String }.filter { $0.hasSuffix(".html") }.map { "site/" + $0 } ?? [])
for page in pages {
    for m in (read(page) ?? "").matches(of: try! Regex(#"releases/latest/download/([A-Za-z0-9._-]+)"#)) {
        guard let file = m[1].substring.map(String.init), !assets.contains(file) else { continue }
        problems.append("\(page): links to \(file), which no release carries")
    }
}

// Terms and privacy name every released platform, in English and in Portuguese.
if let terms = read("TERMS.md") {
    let halves = terms.components(separatedBy: "\n# Termos e privacidade")
    for p in released { if let name = p.termsMention {
        if !halves[0].contains(name) { problems.append("TERMS.md (English) doesn't mention \(name)") }
        if halves.count < 2 || !halves[1].contains(name) { problems.append("TERMS.md (Português) doesn't mention \(name)") }
    } }
}

if problems.isEmpty {
    print(check ? "Content is in step with docs/features.json (version \(version))." : "Done (version \(version)).")
} else {
    problems.forEach { print("✗ \($0)") }
    exit(1)
}
