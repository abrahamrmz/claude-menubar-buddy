import CryptoKit
import Foundation
import Testing
import BuddyCore

// The repo is public, so every sound it ships needs a checkable source and a
// free license. This audit reads the checked-in Resources/Sounds via
// #filePath (like MoodPolicyTests does for the GIFs) and fails the moment a
// file, the catalog and CREDITS.md drift apart.
@Suite struct SoundFilesAuditTests {
    private static let soundsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ClaudeMenuBarBuddyTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("Sources/ClaudeMenuBarBuddy/Resources/Sounds")

    private static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "ogg", "oga", "flac"]

    private func catalogFiles() -> Set<String> {
        Set(SoundCatalog.bundled.compactMap { option in
            if case .bundled(let file, let ext) = option.source { return "\(file).\(ext)" }
            return nil
        })
    }

    private func audioFilesOnDisk() throws -> Set<String> {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.soundsDir.path)
        return Set(names.filter { Self.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) })
    }

    /// CREDITS.md: a "## <file>" line opens each file's section; its
    /// "- key: value" lines follow.
    private func credits() throws -> [String: [String: String]] {
        let text = try String(contentsOf: Self.soundsDir.appendingPathComponent("CREDITS.md"), encoding: .utf8)
        var sections: [String: [String: String]] = [:]
        var current: String?
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                let name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                sections[name] = [:]
                current = name
            } else if let name = current, line.hasPrefix("- "), let colon = line.firstIndex(of: ":") {
                let key = line[line.index(line.startIndex, offsetBy: 2)..<colon]
                    .trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                sections[name]?[key] = value
            }
        }
        return sections
    }

    @Test func everyBundledSoundHasItsFile() throws {
        let onDisk = try audioFilesOnDisk()
        for name in catalogFiles() {
            #expect(onDisk.contains(name), "falta \(name) en Resources/Sounds")
        }
    }

    @Test func everyFileOnDiskIsInTheCatalogAndNoneIsOgg() throws {
        let catalog = catalogFiles()
        for name in try audioFilesOnDisk() {
            #expect(catalog.contains(name), "\(name) no está en SoundCatalog.bundled")
            let ext = (name as NSString).pathExtension.lowercased()
            #expect(ext != "ogg" && ext != "oga", "\(name): macOS no reproduce OGG")
        }
    }

    @Test func everyFileHasItsCreditsWithAFreeLicense() throws {
        let credits = try credits()
        let onDisk = try audioFilesOnDisk()
        for name in onDisk {
            let entry = try #require(credits[name], "\(name) no tiene sección en CREDITS.md")
            let license = entry["licencia"] ?? ""
            #expect(license.contains("CC0") || license.lowercased().contains("dominio público"),
                    "\(name): licencia \"\(license)\"")
            #expect((entry["descarga"] ?? "").hasPrefix("https://"), "\(name): sin URL de descarga")
            #expect((entry["sha256 original"] ?? "").count == 64, "\(name): sin sha256 original")
        }
        for name in credits.keys {
            #expect(onDisk.contains(name), "CREDITS.md habla de \(name), que no existe")
        }
    }

    @Test func checksumsMatchCredits() throws {
        let credits = try credits()
        for name in try audioFilesOnDisk() {
            let data = try Data(contentsOf: Self.soundsDir.appendingPathComponent(name))
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(credits[name]?["sha256 en el repo"] == hash,
                    "\(name) no coincide con su sha256 de CREDITS.md")
        }
    }
}
