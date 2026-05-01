import Foundation

enum DebugLog {
    static func plan(_ message: String) {
        #if DEBUG
        print("[JGR][Plan] \(message)")
        #endif
    }

    static func trigger(_ message: String) {
        #if DEBUG
        print("[JGR][Trigger] \(message)")
        #endif
    }

    static func notification(_ message: String) {
        #if DEBUG
        print("[JGR][Notification] \(message)")
        #endif
    }
}
