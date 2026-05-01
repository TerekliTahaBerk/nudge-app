import Foundation

enum ReminderInputValidator {
    static let maxUserVisibleCharacters = 280

    struct Result: Equatable {
        let sanitizedText: String
        let isValid: Bool
        let reason: String?
    }

    static func sanitize(_ text: String) -> String {
        let normalized = text.precomposedStringWithCanonicalMapping
        let withoutControlCharacters = normalized.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
        }
        let cleaned = String(String.UnicodeScalarView(withoutControlCharacters))
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if cleaned.count <= maxUserVisibleCharacters {
            return cleaned
        }
        return String(cleaned.prefix(maxUserVisibleCharacters))
    }

    static func validate(_ text: String, allowsEmpty: Bool = false) -> Result {
        let sanitized = sanitize(text)
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if allowsEmpty {
            return Result(sanitizedText: sanitized, isValid: true, reason: nil)
        }
        guard !trimmed.isEmpty else {
            return Result(sanitizedText: sanitized, isValid: false, reason: "empty")
        }
        return Result(sanitizedText: sanitized, isValid: true, reason: nil)
    }
}
