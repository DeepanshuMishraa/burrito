import Foundation
import Testing
@testable import Burrito

@MainActor
struct AgentHarnessTests {
    @Test("Enabled agent harness routes the selected adapter away from text models")
    func agentSelectionRoutesAdapter() async {
        let store = AgentHarnessStore.shared
        store.disable()
        defer { store.disable() }

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
