#!/usr/bin/env swift
// Checks that every app's interface text exists in Portuguese and English, with the same placeholders.
//   swift scripts/strings.swift      (never writes; scripts/check-content.sh runs it)
// Mac: Resources/Localizable.xcstrings (the Portuguese text is the key). Android TV: res/values (English)
// and res/values-pt. Windows, when windows/ is there: windows/NuVa.Core/Strings.json (Portuguese → English).
// The same Portuguese text translated differently on the Mac and on Windows is shown as a warning.
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
func read(_ path: String) -> Data? { try? Data(contentsOf: root.appendingPathComponent(path)) }
var problems: [String] = []
var warnings: [String] = []

/// The placeholders of a string, in order, written the same way on every platform: %@, %lld, %1$s, {0} → "*".
func placeholders(_ s: String) -> Int {
    s.matches(of: try! Regex(#"%(\d+\$)?(lld|ld|d|@|s|f|\.\d+f)|\{\d+\}"#)).count
}

// MARK: - Mac

var macEnglish: [String: String] = [:]
if let data = read("Resources/Localizable.xcstrings"),
   let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
   let strings = catalog["strings"] as? [String: [String: Any]] {
    for (key, entry) in strings where entry["shouldTranslate"] as? Bool != false {
        let en = (entry["localizations"] as? [String: Any])?["en"] as? [String: Any]
        // A plain string, or plural variations: every unit has to be translated.
        var units: [[String: Any]] = []
        if let unit = en?["stringUnit"] as? [String: Any] { units = [unit] }
        if let variations = en?["variations"] as? [String: [String: [String: Any]]] {
            units = variations.values.flatMap(\.values).compactMap { $0["stringUnit"] as? [String: Any] }
        }
        if units.isEmpty { problems.append("Mac: \"\(key)\" has no English"); continue }
        for unit in units {
            let value = unit["value"] as? String ?? ""
            if unit["state"] as? String != "translated" || value.isEmpty {
                problems.append("Mac: \"\(key)\" isn't translated to English (\(unit["state"] ?? "no state"))")
            } else if en?["stringUnit"] != nil, placeholders(value) != placeholders(key) {
                problems.append("Mac: \"\(key)\" and its English have different placeholders")
            }
        }
        if let unit = en?["stringUnit"] as? [String: Any], let value = unit["value"] as? String { macEnglish[key] = value }
    }
} else {
    problems.append("Resources/Localizable.xcstrings is missing or isn't valid")
}

// MARK: - Android TV

/// name → text of every translatable string, plural and array in a strings.xml.
func androidStrings(_ path: String) -> [String: String]? {
    guard let data = read(path), let doc = try? XMLDocument(data: data) else { return nil }
    var out: [String: String] = [:]
    for node in (try? doc.nodes(forXPath: "/resources/*")) ?? [] {
        guard let e = node as? XMLElement, let name = e.attribute(forName: "name")?.stringValue,
              e.attribute(forName: "translatable")?.stringValue != "false" else { continue }
        out[name] = e.stringValue ?? ""
    }
    return out
}
let res = "android/app/src/main/res"
if let en = androidStrings("\(res)/values/strings.xml"), let pt = androidStrings("\(res)/values-pt/strings.xml") {
    for name in Set(en.keys).subtracting(pt.keys).sorted() { problems.append("Android TV: \(name) has no Portuguese (values-pt)") }
    for name in Set(pt.keys).subtracting(en.keys).sorted() { problems.append("Android TV: \(name) is only in Portuguese (values-pt)") }
    for (name, text) in en where pt[name].map({ placeholders($0) != placeholders(text) }) ?? false {
        problems.append("Android TV: \(name) has different placeholders in English and Portuguese")
    }
} else {
    problems.append("\(res)/values/strings.xml or values-pt/strings.xml is missing or isn't valid")
}

// MARK: - Windows

let windows = "windows/NuVa.Core/Strings.json"
if FileManager.default.fileExists(atPath: root.appendingPathComponent("windows").path) {
    if let data = read(windows), let table = try? JSONDecoder().decode([String: String].self, from: data) {
        for (key, value) in table.sorted(by: { $0.key < $1.key }) {
            if value.isEmpty { problems.append("Windows: \"\(key)\" has no English") }
            else if placeholders(value) != placeholders(key) { problems.append("Windows: \"\(key)\" and its English have different placeholders") }
            if let mac = macEnglish[key], mac != value, placeholders(key) == 0 {
                warnings.append("\"\(key)\" is \"\(mac)\" on the Mac and \"\(value)\" on Windows")
            }
        }
    } else {
        problems.append("\(windows) is missing or isn't valid")
    }
}

warnings.forEach { print("! \($0)") }
if problems.isEmpty {
    print("Every string is in Portuguese and English.")
} else {
    problems.forEach { print("✗ \($0)") }
    exit(1)
}
