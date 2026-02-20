import Cocoa

let symbol = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)
print("isTemplate: \(symbol?.isTemplate ?? false)")
