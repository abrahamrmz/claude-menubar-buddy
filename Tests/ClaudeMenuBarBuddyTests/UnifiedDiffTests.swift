import Testing
import BuddyCore

@Suite struct UnifiedDiffTests {
    @Test func additionOnly() {
        let patch = "Index: notas.txt\n===================================================================\n--- notas.txt\n+++ notas.txt\n@@ -1,2 +1,3 @@\n hola\n adiós\n+adiós 2\n"
        #expect(UnifiedDiff.buddyHint(files: ["notas.txt"], patches: [patch]) == "notas.txt\n+++ pone\nadiós 2")
    }

    @Test func replacement() {
        let patch = "--- a.swift\n+++ a.swift\n@@ -1,2 +1,2 @@\n-let x = 1\n+let x = 2\n keep\n"
        #expect(UnifiedDiff.buddyHint(files: ["a.swift"], patches: [patch]) == "a.swift\n--- quita\nlet x = 1\n+++ pone\nlet x = 2")
    }

    @Test func twoHunksAndTwoFiles() {
        let p1 = "@@ -1 +1 @@\n-a\n+b\n@@ -9 +9 @@\n-c\n"
        let p2 = "@@ -0,0 +1 @@\n+nuevo\n"
        #expect(UnifiedDiff.buddyHint(files: ["f1", "f2"], patches: [p1, p2])
                == "f1\n--- quita\na\n+++ pone\nb\n--- quita\nc\nf2\n+++ pone\nnuevo")
    }

    @Test func noPatchIsJustTheFiles() {
        #expect(UnifiedDiff.buddyHint(files: ["a", "b"], patches: []) == "a\nb")
    }
}
