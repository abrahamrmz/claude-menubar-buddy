import Foundation
import Testing
import BuddyCore

@Suite struct SoundCatalogTests {
    @Test func bundledSoundsInMenuOrder() {
        #expect(SoundCatalog.bundled.map(\.id) == ["woodblock", "pluck", "drop", "click", "bong"])
        #expect(SoundCatalog.bundled.map(\.title) == ["Madera", "Cuerda", "Gota", "Clic", "Bong"])
        #expect(SoundCatalog.bundled.map(\.source) == [
            .bundled(file: "woodblock", ext: "wav"),
            .bundled(file: "pluck", ext: "wav"),
            .bundled(file: "drop", ext: "wav"),
            .bundled(file: "click", ext: "wav"),
            .bundled(file: "bong", ext: "wav"),
        ])
        #expect(SoundCatalog.bundled.map(\.gain) == [1.0, 0.25, 0.28, 0.28, 0.28])
    }

    @Test func systemSoundsAreTheFourteenOfMacOS() {
        #expect(SoundCatalog.system.count == 14)
        #expect(SoundCatalog.system.first == SoundOption(id: "macos.Basso", title: "Basso",
                                                         source: .system(name: "Basso"), gain: 1.0))
        #expect(SoundCatalog.system.last?.id == "macos.Tink")
        #expect(SoundCatalog.system.allSatisfy { $0.gain == 1.0 })
        #expect(SoundCatalog.all == SoundCatalog.bundled + SoundCatalog.system)
    }

    @Test func idsAreUniqueAndNoneIsNotOne() {
        let ids = SoundCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.contains(SoundCatalog.noneID))
        #expect(SoundCatalog.noneID == "none")
    }

    @Test func gainsStayBetweenZeroAndOne() {
        for option in SoundCatalog.all {
            #expect(option.gain > 0 && option.gain <= 1, "\(option.id): \(option.gain)")
        }
    }

    @Test func eventsDefaultsAndKeys() {
        #expect(SoundEvent.allCases == [.cardArrived, .turnDone, .petClicked, .hotKeyBlocked])
        #expect(SoundEvent.allCases.map(\.title)
                == ["Tarjeta nueva", "Turno terminado", "Clic a la mascota", "Atajo bloqueado"])
        #expect(SoundEvent.allCases.map(\.defaultsKey)
                == ["cardSound", "turnDoneSound", "petClickSound", "blockedSound"])
        #expect(SoundEvent.allCases.map(\.defaultSoundID)
                == ["woodblock", "macos.Glass", "click", "bong"])
    }

    @Test func everyDefaultIsInTheCatalog() {
        for event in SoundEvent.allCases {
            #expect(SoundCatalog.option(id: event.defaultSoundID) != nil, "\(event)")
        }
    }

    @Test func optionLookup() {
        #expect(SoundCatalog.option(id: "drop")?.title == "Gota")
        #expect(SoundCatalog.option(id: "macos.Ping")?.source == .system(name: "Ping"))
        #expect(SoundCatalog.option(id: "Ping") == nil)
        #expect(SoundCatalog.option(id: "none") == nil)
    }

    @Test func resolveKnownIDs() {
        let drop = SoundCatalog.option(id: "drop")!
        let ping = SoundCatalog.option(id: "macos.Ping")!
        #expect(SoundCatalog.resolve(stored: "drop", for: .cardArrived) == .sound(drop))
        #expect(SoundCatalog.resolve(stored: "macos.Ping", for: .petClicked) == .sound(ping))
    }

    @Test func resolveNoneIsSilenceForEveryEvent() {
        for event in SoundEvent.allCases {
            #expect(SoundCatalog.resolve(stored: "none", for: event) == .silent)
        }
    }

    @Test func unknownEmptyOrMissingFallsBackToTheDefaultNeverToSilence() {
        let woodblock = SoundCatalog.option(id: "woodblock")!
        let glass = SoundCatalog.option(id: "macos.Glass")!
        for stored in [nil, "", "macos.Nope", "Ping", "NONE", "gota"] as [String?] {
            #expect(SoundCatalog.resolve(stored: stored, for: .cardArrived) == .sound(woodblock),
                    "\(stored ?? "nil")")
            #expect(SoundCatalog.resolve(stored: stored, for: .turnDone) == .sound(glass),
                    "\(stored ?? "nil")")
        }
    }

    @Test func onlyTheBlockedHotKeyCutsTheCardSound() {
        #expect(SoundCatalog.eventsToStop(before: .hotKeyBlocked) == [.cardArrived])
        #expect(SoundCatalog.eventsToStop(before: .cardArrived).isEmpty)
        #expect(SoundCatalog.eventsToStop(before: .turnDone).isEmpty)
        #expect(SoundCatalog.eventsToStop(before: .petClicked).isEmpty)
    }
}
