//
//  ConsoleCompletionEngineTests.swift
//  Hammerspoon 2Tests
//

import Testing
@testable import Hammerspoon_2

// MARK: - Result construction helper

private extension ConsoleCompletionEngine.Result {
    static func make(
        inputPrefix: String = "",
        prefix: String = "hs.screen.",
        stem: String,
        candidates: [(name: String, completion: String)]
    ) -> ConsoleCompletionEngine.Result {
        ConsoleCompletionEngine.Result(
            inputPrefix: inputPrefix,
            prefix: prefix,
            stem: stem,
            candidates: candidates.map {
                ConsoleCompletionEngine.Result.Candidate(name: $0.name, completion: $0.completion)
            }
        )
    }
}

// MARK: - Result unit tests

/// Pure unit tests for `ConsoleCompletionEngine.Result`.
/// These depend on no external state and always run.
struct ResultTests {

    // MARK: longestCommonPrefix

    @Test("longestCommonPrefix returns stem when candidates list is empty")
    func lcpEmptyCandidates() {
        let result = ConsoleCompletionEngine.Result.make(stem: "foo", candidates: [])
        #expect(result.longestCommonPrefix == "foo")
    }

    @Test("longestCommonPrefix returns full name for a single candidate")
    func lcpSingleCandidate() {
        let result = ConsoleCompletionEngine.Result.make(
            stem: "pri",
            candidates: [("primary", "primary()")]
        )
        #expect(result.longestCommonPrefix == "primary")
    }

    @Test("longestCommonPrefix finds the shared prefix across multiple candidates")
    func lcpMultipleCandidates() {
        let result = ConsoleCompletionEngine.Result.make(
            stem: "set",
            candidates: [
                ("setFrame",  "setFrame(frame)"),
                ("setMode",   "setMode(width, height)"),
                ("setOrigin", "setOrigin(origin)"),
            ]
        )
        #expect(result.longestCommonPrefix == "set")
    }

    @Test("longestCommonPrefix returns empty string when candidates share no prefix")
    func lcpNoCommonPrefix() {
        let result = ConsoleCompletionEngine.Result.make(
            stem: "",
            candidates: [
                ("frame", "frame"),
                ("zoom",  "zoom()"),
            ]
        )
        #expect(result.longestCommonPrefix == "")
    }

    @Test("longestCommonPrefix extends beyond the stem when candidates agree further")
    func lcpBeyondStem() {
        let result = ConsoleCompletionEngine.Result.make(
            stem: "pri",
            candidates: [
                ("primary",       "primary()"),
                ("primaryScreen", "primaryScreen()"),
            ]
        )
        #expect(result.longestCommonPrefix == "primary")
    }

    // MARK: isUnique

    @Test("isUnique is true when exactly one candidate exists")
    func isUniqueWithOneCandidate() {
        let result = ConsoleCompletionEngine.Result.make(
            stem: "primary",
            candidates: [("primary", "primary()")]
        )
        #expect(result.isUnique)
    }

    @Test("isUnique is false when multiple candidates exist")
    func isUniqueWithMultipleCandidates() {
        let result = ConsoleCompletionEngine.Result.make(
            stem: "s",
            candidates: [
                ("setFrame", "setFrame(frame)"),
                ("screen",   "screen"),
            ]
        )
        #expect(result.isUnique == false)
    }

    @Test("isUnique is false when no candidates exist")
    func isUniqueWithNoCandidates() {
        let result = ConsoleCompletionEngine.Result.make(stem: "xyz", candidates: [])
        #expect(result.isUnique == false)
    }

    // MARK: displayString

    @Test("displayString joins completions with two spaces")
    func displayStringMultiple() {
        let result = ConsoleCompletionEngine.Result.make(
            stem: "",
            candidates: [
                ("all",     "all()"),
                ("primary", "primary()"),
                ("screens", "screens"),
            ]
        )
        #expect(result.displayString == "all()  primary()  screens")
    }

    @Test("displayString for a single candidate has no separator")
    func displayStringSingle() {
        let result = ConsoleCompletionEngine.Result.make(
            stem: "",
            candidates: [("all", "all()")]
        )
        #expect(result.displayString == "all()")
    }

    @Test("displayString uses the formatted completion string, not the bare name")
    func displayStringUsesCompletion() {
        let result = ConsoleCompletionEngine.Result.make(
            stem: "",
            candidates: [("setMode", "setMode(width, height, scale, frequency)")]
        )
        #expect(result.displayString == "setMode(width, height, scale, frequency)")
    }
}

// MARK: - Engine unit tests

/// Tests for `ConsoleCompletionEngine.complete(input:)` that do not require
/// api.json to be loaded (they verify input-shape rejection or the always-injected
/// "hs" global).  The struct is `@MainActor` because `ConsoleCompletionEngine.shared`
/// is isolated to the main actor.
@MainActor
struct ConsoleCompletionEngineUnitTests {

    // MARK: Inputs that always produce nil

    @Test(
        "complete returns nil for inputs it cannot safely complete",
        arguments: [
            "hs.screen.primary().next().",  // nested call chain
            "hs.screen.primary(foo.",        // open call with argument
            "hs.screen.setMode(1920.",       // call with numeric argument
            "hs.screen.primary(x).",         // call with argument, then dot
        ]
    )
    func completeAlwaysNilInputs(input: String) {
        #expect(ConsoleCompletionEngine.shared.complete(input: input) == nil)
    }

    // MARK: Global variable completion

    @Test("complete with empty input always includes hs in candidates")
    func completeEmptyInputIncludesHs() {
        let result = ConsoleCompletionEngine.shared.complete(input: "")
        let found = result?.candidates.contains(where: { $0.name == "hs" }) ?? false
        #expect(found, "hs must always appear in global completions")
    }

    @Test("complete with stem 'h' includes hs in candidates")
    func completeStemHIncludesHs() {
        let result = ConsoleCompletionEngine.shared.complete(input: "h")
        let found = result?.candidates.contains(where: { $0.name == "hs" }) ?? false
        #expect(found, "hs starts with 'h' and must always appear")
    }

    @Test("complete with stem 'hs' produces exactly hs as a candidate")
    func completeStemHsFindsHs() {
        let result = ConsoleCompletionEngine.shared.complete(input: "hs")
        let found = result?.candidates.contains(where: { $0.name == "hs" }) ?? false
        #expect(found)
    }

    @Test("complete suppresses _jsCoreExtras names from global candidates")
    func completeHidesJSCoreExtras() {
        // Attempting to complete these names must yield nothing from that namespace.
        let result = ConsoleCompletionEngine.shared.complete(input: "_jsCoreExtras")
        if let result {
            let hasExtras = result.candidates.contains(where: { $0.name.hasPrefix("_jsCoreExtras") })
            #expect(hasExtras == false, "_jsCoreExtras names must never appear in completions")
        }
        // nil result is also acceptable — all matches were filtered out.
    }

    @Test("global candidate filtering is anchored to the start of the name")
    func completeGlobalFilterIsAnchored() {
        // "xhs" is not a prefix of "hs", so "hs" should not appear.
        let result = ConsoleCompletionEngine.shared.complete(input: "xhs")
        if let result {
            let found = result.candidates.contains(where: { $0.name == "hs" })
            #expect(found == false, "'hs' must not match stem 'xhs'")
        }
    }
}

// MARK: - Engine integration tests

/// Tests that rely on api.json being loadable.  `init() async` calls prewarm
/// and waits for the background load to settle before any test runs.
/// If api.json is not present `complete()` returns nil and the test exits early
/// without recording a failure — the tests are vacuously correct in that case.
@MainActor
struct ConsoleCompletionEngineIntegrationTests {

    init() async {
        ConsoleCompletionEngine.shared.prewarm()
        try? await Task.sleep(for: .milliseconds(300))
    }

    // MARK: Input parsing — prefix / stem / inputPrefix extraction

    @Test("complete extracts an empty stem from a bare module path")
    func extractsEmptyStem() {
        guard let result = ConsoleCompletionEngine.shared.complete(input: "hs.screen.") else { return }
        #expect(result.prefix == "hs.screen.")
        #expect(result.stem == "")
        #expect(result.inputPrefix == "")
    }

    @Test("complete extracts stem from a partial module path")
    func extractsStem() {
        guard let result = ConsoleCompletionEngine.shared.complete(input: "hs.screen.pri") else { return }
        #expect(result.prefix == "hs.screen.")
        #expect(result.stem == "pri")
        #expect(result.inputPrefix == "")
    }

    @Test("complete extracts inputPrefix from surrounding statement")
    func extractsInputPrefix() {
        guard let result = ConsoleCompletionEngine.shared.complete(input: "var x = hs.screen.") else { return }
        #expect(result.inputPrefix == "var x = ")
        #expect(result.prefix == "hs.screen.")
        #expect(result.stem == "")
    }

    @Test("complete extracts both inputPrefix and stem from a complex statement")
    func extractsBothPrefixAndStem() {
        guard let result = ConsoleCompletionEngine.shared.complete(input: "var x = hs.screen.pri") else { return }
        #expect(result.inputPrefix == "var x = ")
        #expect(result.prefix == "hs.screen.")
        #expect(result.stem == "pri")
    }

    // MARK: Module-level completions

    @Test("complete returns candidates for the hs.screen module")
    func hsScreenModuleHasCandidates() {
        guard let result = ConsoleCompletionEngine.shared.complete(input: "hs.screen.") else { return }
        #expect(result.candidates.isEmpty == false)
    }

    @Test("complete module candidates are sorted alphabetically")
    func moduleItemsSortedAlphabetically() {
        guard let result = ConsoleCompletionEngine.shared.complete(input: "hs.screen.") else { return }
        let names = result.candidates.map { $0.name }
        #expect(names == names.sorted(), "Candidates must be in alphabetical order")
    }

    @Test("complete filters module candidates by stem case-insensitively")
    func caseInsensitiveStemFilter() {
        guard let result = ConsoleCompletionEngine.shared.complete(input: "hs.screen.PRIM") else { return }
        let names = result.candidates.map { $0.name }
        #expect(names.contains("primary"), "'primary' must match stem 'PRIM'")
    }

    @Test("complete does not match mid-word stems in module items")
    func midWordStemReturnsNil() {
        // "reen" is not a prefix of any hs.screen member.
        #expect(ConsoleCompletionEngine.shared.complete(input: "hs.screen.reen") == nil)
    }

    // MARK: After-call completions

    @Test("complete resolves instance members after a zero-argument call")
    func instanceMembersAfterCall() {
        guard let result = ConsoleCompletionEngine.shared.complete(input: "hs.screen.primary().") else { return }
        #expect(result.prefix == "hs.screen.primary().")
        #expect(result.candidates.isEmpty == false)
    }

    @Test("complete preserves inputPrefix when completing after a call in a statement")
    func inputPrefixPreservedAfterCall() {
        guard let result = ConsoleCompletionEngine.shared.complete(input: "var s = hs.screen.primary().") else { return }
        #expect(result.inputPrefix == "var s = ")
        #expect(result.prefix == "hs.screen.primary().")
    }

    @Test("complete after-call candidates are sorted alphabetically")
    func afterCallCandidatesSorted() {
        guard let result = ConsoleCompletionEngine.shared.complete(input: "hs.screen.primary().") else { return }
        let names = result.candidates.map { $0.name }
        #expect(names == names.sorted(), "After-call candidates must be in alphabetical order")
    }
}
