import Foundation
import Testing
import BuddyCore

@Suite struct SSEParserTests {
    private func feed(_ parts: [String]) -> [String] {
        var p = SSEParser()
        return parts.flatMap { p.feed(Data($0.utf8)) }
    }

    @Test func oneEvent() {
        #expect(feed(["data: {\"a\":1}\n\n"]) == ["{\"a\":1}"])
    }

    @Test func twoEventsInOneChunk() {
        #expect(feed(["data: 1\n\ndata: 2\n\n"]) == ["1", "2"])
    }

    @Test func eventSplitAcrossChunks() {
        #expect(feed(["da", "ta: {\"x\":", "true}\n", "\n"]) == ["{\"x\":true}"])
    }

    @Test func splitInsideAMultibyteCharacter() {
        let bytes = Array("data: adiós\n\n".utf8)
        let cut = bytes.firstIndex(of: 0xC3)! + 1          // between the two bytes of "ó"
        var p = SSEParser()
        var out = p.feed(Data(bytes[..<cut]))
        out += p.feed(Data(bytes[cut...]))
        #expect(out == ["adiós"])
    }

    @Test func heartbeatsAndOtherFieldsAreIgnored() {
        #expect(feed([": heartbeat\n\nevent: x\nid: 7\ndata: ok\n\n: heartbeat\n\n"]) == ["ok"])
    }

    @Test func crlfAndNoSpaceAfterColon() {
        #expect(feed(["data:sin-espacio\r\n\r\n"]) == ["sin-espacio"])
    }

    @Test func multiLineDataIsJoinedWithNewline() {
        #expect(feed(["data: a\ndata: b\n\n"]) == ["a\nb"])
    }

    @Test func incompleteEventIsHeldBack() {
        var p = SSEParser()
        #expect(p.feed(Data("data: a\n".utf8)).isEmpty)
        #expect(p.feed(Data("\n".utf8)) == ["a"])
    }
}
