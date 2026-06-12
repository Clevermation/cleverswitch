import Foundation
import Testing

@testable import CleverSwitchKit

private struct FixedHTTP: HTTPClient {
    let response: HTTPResponse
    func send(_ request: URLRequest) async throws -> HTTPResponse { response }
}

@Suite("CLI-Update (Varianten-Erkennung)")
struct CLIUpdateTests {
    private let home = "/Users/test"

    @Test("bun-Shim wird erkannt (Pfad enthält .bun)")
    func detectsBun() {
        let variant = CLIUpdateChecker.detectVariant(
            binaryPath: "/Users/test/.bun/bin/codex",
            resolvedPath: "/Users/test/.bun/install/global/node_modules/@openai/codex/bin/codex.js",
            firstLine: "#!/usr/bin/env node", home: home)
        #expect(variant == .bun)
    }

    @Test("Homebrew wird erkannt (Prefix bzw. Caskroom)")
    func detectsBrew() {
        #expect(
            CLIUpdateChecker.detectVariant(
                binaryPath: "/opt/homebrew/bin/codex",
                resolvedPath: "/opt/homebrew/Caskroom/codex/0.139.0/codex",
                firstLine: nil, home: home) == .brew)
        #expect(
            CLIUpdateChecker.detectVariant(
                binaryPath: "/usr/local/bin/codex",
                resolvedPath: "/usr/local/bin/codex",
                firstLine: nil, home: home) == .brew)
    }

    @Test("npm-Shim wird erkannt (Node-Shebang ohne bun-Pfad)")
    func detectsNpm() {
        let variant = CLIUpdateChecker.detectVariant(
            binaryPath: "/Users/test/.npm-global/bin/claude",
            resolvedPath:
                "/Users/test/.npm-global/lib/node_modules/@anthropic-ai/claude-code/cli.js",
            firstLine: "#!/usr/bin/env node", home: home)
        #expect(variant == .npm)
    }

    @Test("nativer Installer wird erkannt (~/.local/bin, Mach-O ohne Shebang)")
    func detectsNative() {
        // claude: Symlink nach ~/.local/share/claude/versions/…
        #expect(
            CLIUpdateChecker.detectVariant(
                binaryPath: "/Users/test/.local/bin/claude",
                resolvedPath: "/Users/test/.local/share/claude/versions/2.1.175",
                firstLine: nil, home: home) == .native)
        // codex: Standalone-Releases unter ~/.codex/packages/standalone
        #expect(
            CLIUpdateChecker.detectVariant(
                binaryPath: "/Users/test/.local/bin/codex",
                resolvedPath: "/Users/test/.codex/packages/standalone/releases/0.139.0/codex",
                firstLine: nil, home: home) == .native)
    }

    @Test("Versions-Parsing: claude- und codex-Format + Müll")
    func parsesVersions() {
        #expect(CLIUpdateChecker.parseVersion("2.1.175 (Claude Code)") == "2.1.175")
        #expect(CLIUpdateChecker.parseVersion("codex-cli 0.136.0") == "0.136.0")
        #expect(CLIUpdateChecker.parseVersion("v1.2.3\n") == "1.2.3")
        #expect(CLIUpdateChecker.parseVersion("kein treffer hier") == nil)
        #expect(CLIUpdateChecker.parseVersion("") == nil)
    }

    @Test("Update-Befehl passt zur Variante (npm explizit @latest!)")
    func updateCommands() {
        func cmd(_ v: CLIVariant) -> String? {
            CLIUpdateChecker.updateCommand(
                variant: v, cliName: "codex", npmPackage: "@openai/codex", brewCask: "codex")
        }
        #expect(cmd(.native) == "codex update")
        #expect(cmd(.npm) == "npm install -g @openai/codex@latest")
        #expect(cmd(.bun) == "bun install -g @openai/codex")
        #expect(cmd(.brew) == "brew upgrade --cask codex")
        #expect(cmd(.unknown) == nil)
    }

    @Test("updateAvailable: nur wenn latest echt neuer ist")
    func updateAvailableSemantics() {
        var status = CLIStatus(
            binaryPath: "/x", variant: .bun, installedVersion: "0.136.0",
            latestVersion: "0.139.0")
        #expect(status.updateAvailable)
        status = CLIStatus(
            binaryPath: "/x", variant: .bun, installedVersion: "0.139.0",
            latestVersion: "0.139.0")
        #expect(!status.updateAvailable)
        status = CLIStatus(
            binaryPath: "/x", variant: .bun, installedVersion: nil, latestVersion: "1.0.0")
        #expect(!status.updateAvailable)
    }

    @Test("latestVersion liest das npm-latest-JSON")
    func latestFromRegistry() async {
        let http = FixedHTTP(
            response: HTTPResponse(
                status: 200,
                body: Data(#"{"name":"@openai/codex","version":"0.139.0"}"#.utf8)))
        let latest = await CLIUpdateChecker.latestVersion(npmPackage: "@openai/codex", http: http)
        #expect(latest == "0.139.0")
    }
}
