#if os(macOS)
import AppKit
#else
import UIKit
#endif

func systemSymbol(_ name: String?) -> String? {
    guard let name else { return nil }
    #if os(macOS)
    return NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil ? nil : name
    #else
    return UIImage(systemName: name) == nil ? nil : name
    #endif
}
