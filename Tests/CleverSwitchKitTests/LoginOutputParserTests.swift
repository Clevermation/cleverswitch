import Foundation
import Testing

@testable import CleverSwitchKit

@Suite("Login-Output-Parser")
struct LoginOutputParserTests {
    @Test("findet die echte Claude-Authorize-URL aus dem CLI-Output")
    func findsClaudeURL() {
        let output = """
            CleverSwitch — sign in to Claude Code
            Opening browser to sign in…
            If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback&scope=org%3Acreate_api_key+user%3Aprofile&code_challenge=zCTnq69SfGJrxl8&code_challenge_method=S256&state=BfKiwvu2rkqo
            Paste code here if prompted >
            """
        let url = LoginOutputParser.authorizeURL(in: output)
        #expect(url?.scheme == "https")
        #expect(url?.host == "claude.com")
        #expect(url?.absoluteString.contains("code_challenge_method=S256") == true)
    }

    @Test("findet die OpenAI-Authorize-URL (Codex)")
    func findsCodexURL() {
        let output = "Starting login… visit https://auth.openai.com/oauth/authorize?client_id=app_x&state=y to continue"
        #expect(LoginOutputParser.authorizeURL(in: output)?.host == "auth.openai.com")
    }

    @Test("keine URL -> nil")
    func noURL() {
        #expect(LoginOutputParser.authorizeURL(in: "just some text, no link here") == nil)
    }

    @Test("erkennt die Code-Aufforderung")
    func detectsCodePrompt() {
        #expect(LoginOutputParser.asksForCode("Paste code here if prompted >"))
        #expect(LoginOutputParser.asksForCode("Please enter the code from your browser"))
        #expect(LoginOutputParser.asksForCode("Opening browser…") == false)
    }
}
