import Foundation
import Testing
@testable import Burrito

// These tests mutate the shared AgentHarnessStore singleton and its
// UserDefaults-backed selection, so they must not interleave with each
// other at suspension points: a parallel test disabling the selection
// mid-resolve makes the routing assertion flaky.
@MainActor
@Suite(.serialized)
struct AgentHarnessTests {
    @Test("Enabled agent harness routes the selected adapter away from text models")
    func agentSelectionRoutesAdapter() async {
        let store = AgentHarnessStore.shared
        store.disable()
        defer { store.disable() }

        // Wait for the store's initial detection to settle, then seed the
        // executable cache so routing is deterministic regardless of the
        // test host's PATH.
        for _ in 0..<500 {
            if store.states[.claude] != nil { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        AgentCLI.executableCache.withLock {
            $0[.claude] = URL(fileURLWithPath: "/usr/local/bin/claude")
        }

        store.enable(.claude)
        #expect(AgentHarnessStore.currentSelection() == .claude)

        let resolved = await SelectedLanguageModelAdapter.shared.resolve(
            languageIdentifier: "en-US"
        )
        guard case .success(let adapter) = resolved else {
            Issue.record("Expected agent adapter resolution to succeed.")
            return
        }
        #expect(!adapter.supportsToolCalling)
        #expect(await adapter.contextSize >= 100_000)
    }

    @Test("Disabling the agent falls back to the on-device selection path")
    func disablingAgentClearsSelection() async {
        let store = AgentHarnessStore.shared
        store.disable()
        defer { store.disable() }

        store.enable(.opencode)
        #expect(AgentHarnessStore.currentSelection() == .opencode)

        store.disable()
        #expect(AgentHarnessStore.currentSelection() == nil)
    }

    @Test("A stale selection without an executable falls back to the local model")
    func staleSelectionFallsBackToLocalModel() async {
        let store = AgentHarnessStore.shared
        store.disable()
        defer { store.disable() }

        // Cache a nil result for a harness that is not installed here, then
        // select it: resolution must not route through the harness.
        AgentCLI.executableCache.withLock { $0[.aider] = nil }
        store.enable(.aider)
        #expect(AgentHarnessStore.currentSelection() == .aider)

        let resolved = await SelectedLanguageModelAdapter.shared.resolve(
            languageIdentifier: "en-US"
        )
        if case .success(let adapter) = resolved {
            #expect(adapter is FoundationModelAdapter)
        }
        // A failure (Apple Intelligence unavailable on this machine) is also
        // acceptable — the point is that routing did not use the harness.
    }

    @Test("Agent output sanitization strips ANSI escapes and padding")
    func sanitizedOutputStripsANSI() {
        let input = "\u{001B}[32mHello\u{001B}[0m\n\nworld\n\n\n"
        #expect(AgentCLI.sanitizedOutput(input) == "Hello\n\nworld")
    }

    @Test("Harness metadata covers every registered harness")
    func harnessMetadataIsComplete() {
        let printModeFlags = ["-p", "run", "exec", "--message"]
        for harness in AgentHarness.allCases {
            let name = harness.displayName
            let binary = harness.binaryName
            let flags = harness.commandArguments
            let logo = harness.logoAssetName
            #expect(!name.isEmpty)
            #expect(!binary.isEmpty)
            #expect(flags.contains(where: { printModeFlags.contains($0) }))
            #expect(!logo.isEmpty)
        }
    }
}
