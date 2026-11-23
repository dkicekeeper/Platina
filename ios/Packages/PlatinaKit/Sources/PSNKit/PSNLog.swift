#if canImport(os)
import os
#endif

/// Failures of PSN requests in the system log: what Xcode's console and Console.app show, and
/// what a "no connection" banner hides. Paths and error codes only; no tokens, no answers.
enum PSNLog {
    #if canImport(os)
    private static let logger = Logger(subsystem: "dakacom.Platina", category: "PSN")
    #endif

    static func failure(_ message: String) {
        #if canImport(os)
        logger.error("\(message, privacy: .public)")
        #endif
    }
}
