#if os(macOS)
import AppKit

func diag90(_ line: String) {
    let path = NSTemporaryDirectory() + "crew-diag.log"
    let text = "\(Date.now.timeIntervalSinceReferenceDate) \(line)\n"
    print("DIAG90 \(path) \(line)")
    guard let handle = FileHandle(forWritingAtPath: path) else {
        FileManager.default.createFile(atPath: path, contents: Data(text.utf8))
        return
    }
    handle.seekToEndOfFile()
    handle.write(Data(text.utf8))
    try? handle.close()
}

@MainActor let diag90Monitor: Any? = {
    diag90("launch doubleClickInterval=\(NSEvent.doubleClickInterval)")
    return NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
        let responder = event.window?.firstResponder.map { String(describing: type(of: $0)) } ?? "-"
        diag90("\(event.type == .leftMouseDown ? "down" : "up") clickCount=\(event.clickCount) ts=\(event.timestamp) loc=\(event.locationInWindow) win=\(event.window?.title ?? "-") key=\(event.window?.isKeyWindow ?? false) fr=\(responder)")
        return event
    }
}()
#endif
