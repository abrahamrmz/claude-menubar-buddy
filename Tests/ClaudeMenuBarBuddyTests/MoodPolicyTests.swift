import Foundation
import Testing
import BuddyCore

// The limit ladder, the degradation chains, and — the part that used to be
// checked by hand at every pet retirement — an audit of every species × mood
// against the GIFs actually in the repo. The audit reads the checked-in
// Resources directory via #filePath, so it needs no bundle and fails the
// moment art and policy drift apart (a new mood without GIFs, a retired pet
// still in species.txt, a chain ending on art nobody generated).
struct MoodPolicyTests {
    // MARK: - The 5-hour ladder

    @Test func ladderThresholds() {
        #expect(MoodPolicy.petMood(forFiveHourPct: nil) == "idle")  // stale data = unknown, not asleep
        #expect(MoodPolicy.petMood(forFiveHourPct: 0) == "idle")
        #expect(MoodPolicy.petMood(forFiveHourPct: 49) == "idle")
        #expect(MoodPolicy.petMood(forFiveHourPct: 50) == "tired")
        #expect(MoodPolicy.petMood(forFiveHourPct: 69) == "tired")
        #expect(MoodPolicy.petMood(forFiveHourPct: 70) == "stressed")
        #expect(MoodPolicy.petMood(forFiveHourPct: 84) == "stressed")
        #expect(MoodPolicy.petMood(forFiveHourPct: 85) == "critical")
        #expect(MoodPolicy.petMood(forFiveHourPct: 99) == "critical")
        #expect(MoodPolicy.petMood(forFiveHourPct: 100) == "asleep")
        #expect(MoodPolicy.petMood(forFiveHourPct: 120) == "asleep")
    }

    // MARK: - Degradation chains

    /// Every chain must be resolvable for a pet that only ships the CORE ten
    /// (see generate_pets.py) — thinking, sad, excited and meditate all have
    /// to land on core art, or a core-only pet freezes on its previous GIF.
    @Test func chainsDegradeToCoreArt() {
        let core: Set = ["idle", "pending", "working", "tired", "stressed",
                         "critical", "asleep", "heart", "celebrate", "meditate"]
        for mood in MoodPolicy.allMoods {
            let candidates = MoodPolicy.gifCandidates(mood)
            #expect(candidates.first == mood, "a chain must try the real mood first")
            #expect(candidates.contains { core.contains($0) } || core.contains(mood),
                    "\(mood) has no candidate a CORE-only pet can draw")
        }
    }

    /// Meditation must never degrade to asleep: the Z means "limit reached",
    /// which is a much worse thing than a tidy-up.
    @Test func meditateNeverBecomesAsleep() {
        #expect(!MoodPolicy.gifCandidates("meditate").contains("asleep"))
    }

    @Test func resolutionWalksTheChain() {
        let koalaOnly: Set = ["koala_thinking", "koala_working", "koala_idle"]
        #expect(MoodPolicy.gifName(species: "koala", mood: "thinking",
                                   available: koalaOnly.contains) == "koala_thinking")
        // No thinking art → the chain's next stop.
        let noThinking: Set = ["piglet_working", "piglet_idle"]
        #expect(MoodPolicy.gifName(species: "piglet", mood: "thinking",
                                   available: noThinking.contains) == "piglet_working")
        // Nothing at all → the idle fallback, never a frozen previous GIF.
        #expect(MoodPolicy.gifName(species: "ghost", mood: "sad",
                                   available: { _ in false }) == "ghost_idle")
    }

    // MARK: - Retired species heal to the default

    @Test func orphanedSpeciesFallsBack() {
        let shipped: Set = ["koala_idle", "panda_idle"]
        // "buddy" and "cat" are real leftovers in real installs (Fase 4.x).
        #expect(MoodPolicy.resolvedSpecies(stored: "buddy", fallback: "koala",
                                           available: shipped.contains) == "koala")
        #expect(MoodPolicy.resolvedSpecies(stored: "cat", fallback: "koala",
                                           available: shipped.contains) == "koala")
        #expect(MoodPolicy.resolvedSpecies(stored: "panda", fallback: "koala",
                                           available: shipped.contains) == "panda")
    }

    // MARK: - Audit against the checked-in art

    private static let resourcesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ClaudeMenuBarBuddyTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("Sources/ClaudeMenuBarBuddy/Resources")

    private func shippedGifs() throws -> Set<String> {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.resourcesDir.path)
        return Set(files.filter { $0.hasSuffix(".gif") }.map { String($0.dropLast(4)) })
    }

    private func shippedSpecies() throws -> [String] {
        let text = try String(contentsOf: Self.resourcesDir.appendingPathComponent("species.txt"),
                              encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    /// Every species × every mood resolves to a GIF that exists — the 4×13
    /// sweep the 4.x retirement verified by hand, on every `swift test` now.
    @Test func everySpeciesMoodComboResolvesToShippedArt() throws {
        let gifs = try shippedGifs()
        let species = try shippedSpecies()
        #expect(!species.isEmpty, "species.txt is empty or missing")
        for pet in species {
            for mood in MoodPolicy.allMoods {
                let resolved = MoodPolicy.gifName(species: pet, mood: mood,
                                                  available: gifs.contains)
                #expect(gifs.contains(resolved),
                        "\(pet) × \(mood) resolves to \(resolved).gif, which does not exist")
            }
        }
    }

    /// The reverse direction: no shipped GIF belongs to a species that isn't
    /// in species.txt (a retired pet leaving art behind) or wears a mood the
    /// policy doesn't know (art generated for a mood the app can never ask
    /// for — allMoods and generate_pets.py drifting apart).
    @Test func noShippedArtIsUnreachable() throws {
        let species = try shippedSpecies()
        for gif in try shippedGifs() {
            guard let pet = species.first(where: { gif.hasPrefix($0 + "_") }) else {
                Issue.record("\(gif).gif belongs to no species in species.txt")
                continue
            }
            let mood = String(gif.dropFirst(pet.count + 1))
            #expect(MoodPolicy.allMoods.contains(mood),
                    "\(gif).gif wears mood \"\(mood)\", which MoodPolicy doesn't know")
        }
    }

    /// The default species must ship idle art — it's the floor every
    /// fallback lands on.
    @Test func defaultSpeciesHasIdleArt() throws {
        #expect(try shippedGifs().contains("koala_idle"))
    }
}
