/// Direction of a piece of user text, decided by its first strong letter, so
/// a Hebrew title aligns right and an English one left regardless of the
/// system language (spec §9.4).
public enum TextDirection: Sendable, Equatable {
    case leftToRight
    case rightToLeft

    public static func of(_ text: String) -> TextDirection {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF:
                return .rightToLeft // Hebrew, Arabic and their presentation forms
            default:
                if scalar.properties.isAlphabetic { return .leftToRight }
            }
        }
        return .leftToRight
    }
}
