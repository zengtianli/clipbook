import Foundation

@main struct LinkTitleTest {
    static func main() async {
        let start = Date()
        let title = await LinkTitle.fetch(CommandLine.arguments[1])
        precondition(title == "bounded response", "title missing")
        precondition(Date().timeIntervalSince(start) < 2, "download ignored byte limit")
        print("PASS: ignored Range response returns title before delayed body finishes")
    }
}
