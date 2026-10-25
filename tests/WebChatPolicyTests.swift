import Foundation

@main
enum WebChatPolicyTests {
    static func main() {
        // Allowed: the hosts themselves
        precondition(isChatGPTHost("chatgpt.com"))
        precondition(isChatGPTHost("chat.openai.com"))
        precondition(isChatGPTHost("openai.com"))
        precondition(isChatGPTHost("oaiusercontent.com"))

        // Allowed: subdomains, and case is irrelevant
        precondition(isChatGPTHost("api.chatgpt.com"))
        precondition(isChatGPTHost("cdn.oaistatic.com"))
        precondition(isChatGPTHost("ChatGPT.com"))
        precondition(isChatGPTHost("AUTH.OPENAI.COM"))

        // Rejected: lookalikes. The suffix match is anchored on a dot, so a host that
        // merely ends in the same letters must not pass.
        precondition(!isChatGPTHost("notchatgpt.com"))
        precondition(!isChatGPTHost("fakeopenai.com"))
        precondition(!isChatGPTHost("chatgpt.com.evil.net"))
        precondition(!isChatGPTHost("openai.com.attacker.io"))
        precondition(!isChatGPTHost("xchatgpt.com"))

        // Rejected: nothing, and everything else
        precondition(!isChatGPTHost(nil))
        precondition(!isChatGPTHost(""))
        precondition(!isChatGPTHost("google.com"))
        precondition(!isChatGPTHost("localhost"))

        // Main-frame policy: only http(s) on an allowed host stays in the island.
        precondition(webChatKeepsInIsland(URL(string: "https://chatgpt.com/")!))
        precondition(webChatKeepsInIsland(URL(string: "https://auth.openai.com/login")!))
        precondition(webChatKeepsInIsland(URL(string: "http://chatgpt.com/")!))
        precondition(!webChatKeepsInIsland(URL(string: "https://example.com/")!))
        precondition(!webChatKeepsInIsland(URL(string: "file:///etc/hosts")!))
        precondition(!webChatKeepsInIsland(URL(string: "javascript:alert(1)")!))
        precondition(!webChatKeepsInIsland(URL(string: "vscode://file/etc/hosts")!))
        precondition(!webChatKeepsInIsland(nil))

        print("Web chat policy: 25 cases passed")
    }
}
