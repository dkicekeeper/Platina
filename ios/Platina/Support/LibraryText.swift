import Foundation
import DesignSupport
import PlatinaCore

// The words for the core's values: shelves, orders, plans, durations.

extension GameShelf {
    var title: String {
        switch self {
        case .all: String(localized: "shelf.all")
        case .inProgress: String(localized: "shelf.inProgress")
        case .platinum: String(localized: "shelf.platinum")
        case .completed: String(localized: "shelf.completed")
        case .notStarted: String(localized: "shelf.notStarted")
        case .shelved: String(localized: "shelf.shelved")
        }
    }
}

extension GameSort {
    var title: String {
        switch self {
        case .recent: String(localized: "sort.recent")
        case .progress: String(localized: "sort.progress")
        case .name: String(localized: "sort.name")
        case .playTime: String(localized: "sort.playTime")
        }
    }
}

extension GamePlanStatus {
    var title: String {
        switch self {
        case .none: String(localized: "plan.none")
        case .chasing: String(localized: "plan.chasing")
        case .later: String(localized: "plan.later")
        case .skip: String(localized: "plan.skip")
        }
    }

    var systemImage: String {
        switch self {
        case .none: "circle.dashed"
        case .chasing: "scope"
        case .later: "pause.circle"
        case .skip: "xmark.circle"
        }
    }
}

enum PlayTimeText {
    /// "38 h, 12 min".
    static func duration(_ seconds: TimeInterval) -> String {
        Formatting.elapsedTime(seconds)
    }

    /// Whole hours, for a counter.
    static func hours(_ seconds: TimeInterval) -> String {
        Int((seconds / 3600).rounded(.down)).formatted()
    }
}
