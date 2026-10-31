import Foundation
import Testing
import BuddyCore

@Suite struct SoundMenuTests {
    private let onlyGlassAndTink: (String) -> Bool = { $0 == "Glass" || $0 == "Tink" }

    @Test func rowTitleNamesTheCurrentSound() {
        #expect(SoundMenu.rowTitle(for: .cardArrived, stored: nil) == "Tarjeta nueva — Madera")
        #expect(SoundMenu.rowTitle(for: .turnDone, stored: nil) == "Turno terminado — Glass")
        #expect(SoundMenu.rowTitle(for: .petClicked, stored: "drop") == "Clic a la mascota — Gota")
        #expect(SoundMenu.rowTitle(for: .hotKeyBlocked, stored: "none") == "Atajo bloqueado — Sin sonido")
        #expect(SoundMenu.rowTitle(for: .hotKeyBlocked, stored: "borrado") == "Atajo bloqueado — Bong")
    }

    @Test func rowsBundledThenMacOSThenSilence() {
        let rows = SoundMenu.rows(for: .cardArrived, stored: "drop", systemAvailable: onlyGlassAndTink)
        #expect(rows == [
            .option(id: "woodblock", title: "Madera", checked: false),
            .option(id: "pluck", title: "Cuerda", checked: false),
            .option(id: "drop", title: "Gota", checked: true),
            .option(id: "click", title: "Clic", checked: false),
            .option(id: "bong", title: "Bong", checked: false),
            .separator,
            .header("macOS"),
            .option(id: "macos.Glass", title: "Glass", checked: false),
            .option(id: "macos.Tink", title: "Tink", checked: false),
            .separator,
            .option(id: "none", title: "Sin sonido", checked: false),
        ])
    }

    @Test func allFourteenMacOSSoundsWhenTheMacHasThem() {
        let rows = SoundMenu.rows(for: .turnDone, stored: nil, systemAvailable: { _ in true })
        #expect(rows.count == 5 + 2 + 14 + 2)
        #expect(rows.filter { if case .option(_, _, true) = $0 { return true }; return false }
                == [.option(id: "macos.Glass", title: "Glass", checked: true)])
    }

    @Test func noMacOSSectionWhenNoneAreAvailable() {
        let rows = SoundMenu.rows(for: .petClicked, stored: nil, systemAvailable: { _ in false })
        #expect(rows == [
            .option(id: "woodblock", title: "Madera", checked: false),
            .option(id: "pluck", title: "Cuerda", checked: false),
            .option(id: "drop", title: "Gota", checked: false),
            .option(id: "click", title: "Clic", checked: true),
            .option(id: "bong", title: "Bong", checked: false),
            .separator,
            .option(id: "none", title: "Sin sonido", checked: false),
        ])
    }

    @Test func silenceIsCheckedWhenChosen() {
        let rows = SoundMenu.rows(for: .hotKeyBlocked, stored: "none", systemAvailable: onlyGlassAndTink)
        #expect(rows.last == .option(id: "none", title: "Sin sonido", checked: true))
        #expect(rows.dropLast().allSatisfy { if case .option(_, _, true) = $0 { return false }; return true })
    }

    @Test func unknownStoredValueChecksTheDefault() {
        let rows = SoundMenu.rows(for: .hotKeyBlocked, stored: "retirado", systemAvailable: onlyGlassAndTink)
        #expect(rows.contains(.option(id: "bong", title: "Bong", checked: true)))
        #expect(rows.last == .option(id: "none", title: "Sin sonido", checked: false))
    }
}
