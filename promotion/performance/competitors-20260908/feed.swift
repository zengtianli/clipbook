import AppKit
for i in 1...100 {
 NSPasteboard.general.clearContents()
 NSPasteboard.general.setString(String(format:"Benchmark %04d — synthetic clipboard text. Keyboard friendly, low memory, responsive search.",i),forType:.string)
 Thread.sleep(forTimeInterval:0.6)
}
print("100 synthetic text items sent at 600 ms intervals")
