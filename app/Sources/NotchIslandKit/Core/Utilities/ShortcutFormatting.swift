// File: Sources/NotchIslandKit/Core/Utilities/ShortcutFormatting.swift
import AppKit

struct KeyboardShortcutDefinition: Codable, Equatable {
    /// Virtual key code (Carbon `kVK_*`).
    var keyCode: UInt16
    /// Raw `NSEvent.ModifierFlags` intersected with device-independent mask.
    var modifierFlagsRaw: UInt

    init(keyCode: UInt16, modifierFlagsRaw: UInt) {
        self.keyCode = keyCode
        self.modifierFlagsRaw = modifierFlagsRaw
    }
}

extension KeyboardShortcutDefinition {
    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRaw).intersection(.deviceIndependentFlagsMask)
    }

    /// Human-readable symbolic form, e.g. "⌥⌘Space".
    var displayString: String {
        var s = ""
        let m = modifierFlags
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        s += Self.keyName(for: keyCode)
        return s
    }

    /// Minimal virtual-keycode → label map covering common keys.
    static func keyName(for code: UInt16) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Esc"
        case 48: return "Tab"
        case 51: return "Delete"
        case 123: return "←"; case 124: return "→"; case 125: return "↓"; case 126: return "↑"
        case 0: return "A"; case 11: return "B"; case 8: return "C"; case 2: return "D"
        case 14: return "E"; case 3: return "F"; case 5: return "G"; case 4: return "H"
        case 34: return "I"; case 38: return "J"; case 40: return "K"; case 37: return "L"
        case 46: return "M"; case 45: return "N"; case 31: return "O"; case 35: return "P"
        case 12: return "Q"; case 15: return "R"; case 1: return "S"; case 17: return "T"
        case 32: return "U"; case 9: return "V"; case 13: return "W"; case 7: return "X"
        case 16: return "Y"; case 6: return "Z"
        case 18: return "1"; case 19: return "2"; case 20: return "3"; case 21: return "4"
        case 23: return "5"; case 22: return "6"; case 26: return "7"; case 28: return "8"
        case 25: return "9"; case 29: return "0"
        default: return "key\(code)"
        }
    }

    /// Whether the combination is safe to register (needs at least one modifier
    /// so it doesn't clobber plain typing).
    var isValidGlobalShortcut: Bool {
        let m = modifierFlags
        return m.contains(.command) || m.contains(.control) || m.contains(.option)
    }
}
