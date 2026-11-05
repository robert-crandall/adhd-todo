import Foundation

public enum TaskPool: String, Codable, Sendable, CaseIterable {
    case life = "Life"
    case computerWork = "Computer / Work"
}

public enum TaskContext: String, Codable, Sendable, CaseIterable, Identifiable {
    case outside = "Outside"
    case errands = "Errands"
    case anywhere = "Anywhere"
    case computer = "Computer"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .outside: return "sun.max"
        case .errands: return "cart"
        case .anywhere: return "sparkles"
        case .computer: return "desktopcomputer"
        }
    }
}

public enum TaskEffort: String, Codable, Sendable, CaseIterable, Identifiable {
    case quick = "Quick"
    case medium = "Medium"
    case big = "Big"

    public var id: String { rawValue }

    public var defaultMinutes: Int {
        switch self {
        case .quick: return 5
        case .medium: return 20
        case .big: return 45
        }
    }
}

public enum TaskSeason: String, Codable, Sendable, CaseIterable, Identifiable {
    case any = "Any"
    case spring = "Spring"
    case summer = "Summer"
    case fall = "Fall"
    case winter = "Winter"

    public var id: String { rawValue }
}

public enum TaskStatus: String, Codable, Sendable {
    case active
    case done
    case snoozed
}

public enum HomeLayoutMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case list = "List"
    case cards = "Cards"
    case zen = "Zen Deck"

    public var id: String { rawValue }
}

public enum SidebarSection: String, Codable, Sendable, CaseIterable, Identifiable {
    case lifeDraw = "home"
    case computerWork = "work"
    case pull = "pull"
    case brainDump = "braindump"
    case mcp = "mcp"
    case pools = "pool"

    public var id: String { rawValue }
}

public struct TaskNote: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var date: String
    public var text: String

    public init(id: String = UUID().uuidString, date: String, text: String) {
        self.id = id
        self.date = date
        self.text = text
    }
}

public struct TaskStep: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var done: Bool

    public init(id: String = UUID().uuidString, text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }
}

public struct TaskItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var context: TaskContext
    public var effort: TaskEffort
    public var season: TaskSeason
    public var anchorMonth: Int?
    public var notes: String
    public var previousNotes: [TaskNote]
    public var steps: [TaskStep]
    public var status: TaskStatus
    public var snoozedUntil: String?
    public var cooldownUntil: String?
    public var lastSurfacedAt: String?
    public var oneThing: Bool
    public var estMinutes: Int
    public var source: String?
    public var externalRef: String?
    public var updatedAt: Date
    public var isDeleted: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        context: TaskContext = .anywhere,
        effort: TaskEffort = .quick,
        season: TaskSeason = .any,
        anchorMonth: Int? = nil,
        notes: String = "",
        previousNotes: [TaskNote] = [],
        steps: [TaskStep] = [],
        status: TaskStatus = .active,
        snoozedUntil: String? = nil,
        cooldownUntil: String? = nil,
        lastSurfacedAt: String? = nil,
        oneThing: Bool = false,
        estMinutes: Int? = nil,
        source: String? = nil,
        externalRef: String? = nil,
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.context = context
        self.effort = effort
        self.season = season
        self.anchorMonth = anchorMonth
        self.notes = notes
        self.previousNotes = previousNotes
        self.steps = steps
        self.status = status
        self.snoozedUntil = snoozedUntil
        self.cooldownUntil = cooldownUntil
        self.lastSurfacedAt = lastSurfacedAt
        self.oneThing = oneThing
        self.estMinutes = estMinutes ?? effort.defaultMinutes
        self.source = source
        self.externalRef = externalRef
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    /// Separate pools: Computer tasks or externally pushed items (GitHub, Gmail, MCP) belong to Computer / Work.
    /// Outside, Errands, and Anywhere tasks without an external source belong to the Life pool.
    public var pool: TaskPool {
        if context == .computer || (source != nil && !(source?.isEmpty ?? true)) {
            return .computerWork
        }
        return .life
    }
}

public struct WeeklyDrawIds: Codable, Sendable, Equatable {
    public var quickId: String?
    public var mediumId: String?
    public var weekKey: String?

    public init(quickId: String? = nil, mediumId: String? = nil, weekKey: String? = nil) {
        self.quickId = quickId
        self.mediumId = mediumId
        self.weekKey = weekKey
    }
}

public enum TasksDateHelper {
    public static func addDays(to isoDate: String, days: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let base = formatter.date(from: isoDate),
              let target = formatter.calendar.date(byAdding: .day, value: days, to: base) else {
            return isoDate
        }
        return formatter.string(from: target)
    }

    public static func isoWeekKey(for isoDate: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        let comps = formatter.calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(comps.yearForWeekOfYear ?? 0)-W\(comps.weekOfYear ?? 0)"
    }

    public static let seedBaselineDate = Date(timeIntervalSince1970: 1_700_000_000)

    public static func noteTimestampString(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: now)
    }

    public static func currentDateParts(now: Date = Date()) -> (todayISO: String, month: Int, season: TaskSeason) {
        let cal = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = cal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let todayISO = formatter.string(from: now)
        let month = cal.component(.month, from: now)
        let season: TaskSeason
        switch month {
        case 3, 4, 5: season = .spring
        case 6, 7, 8: season = .summer
        case 9, 10, 11: season = .fall
        default: season = .winter
        }
        return (todayISO, month, season)
    }
}

public struct TasksState: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var currentMonth: Int
    public var currentSeason: TaskSeason
    public var todayISO: String
    public var hardDayMode: Bool
    public var workHoursOn: Bool
    public var hideTags: Bool
    public var homeLayout: HomeLayoutMode
    public var expandedTaskId: String?
    public var zenIndex: Int
    public var weeklyDraw: WeeklyDrawIds
    public var pullContextFilter: String
    public var pullEffortFilter: String
    public var pullResults: [String]
    public var tasks: [TaskItem]
    public var activityLog: [String]

    public init(
        schemaVersion: Int = 1,
        currentMonth: Int? = nil,
        currentSeason: TaskSeason? = nil,
        todayISO: String? = nil,
        hardDayMode: Bool = false,
        workHoursOn: Bool = true,
        hideTags: Bool = false,
        homeLayout: HomeLayoutMode = .list,
        expandedTaskId: String? = nil,
        zenIndex: Int = 0,
        weeklyDraw: WeeklyDrawIds = WeeklyDrawIds(),
        pullContextFilter: String = "Outside",
        pullEffortFilter: String = "Quick",
        pullResults: [String] = [],
        tasks: [TaskItem] = TasksState.defaultSeedTasks(),
        activityLog: [String] = []
    ) {
        let nowParts = TasksDateHelper.currentDateParts()
        self.schemaVersion = schemaVersion
        self.currentMonth = currentMonth ?? nowParts.month
        self.currentSeason = currentSeason ?? nowParts.season
        self.todayISO = todayISO ?? nowParts.todayISO
        self.hardDayMode = hardDayMode
        self.workHoursOn = workHoursOn
        self.hideTags = hideTags
        self.homeLayout = homeLayout
        self.expandedTaskId = expandedTaskId
        self.zenIndex = zenIndex
        self.weeklyDraw = weeklyDraw
        self.pullContextFilter = pullContextFilter
        self.pullEffortFilter = pullEffortFilter
        self.pullResults = pullResults
        self.tasks = tasks
        self.activityLog = activityLog
    }

    public static func defaultSeedTasks() -> [TaskItem] {
        let seedDate = TasksDateHelper.seedBaselineDate
        return [
            TaskItem(
                id: "t-1",
                title: "Clean out garage gutters before winter rain",
                context: .outside,
                effort: .medium,
                season: .fall,
                anchorMonth: 11,
                notes: "Ladder is behind the shed. Take gloves.",
                previousNotes: [
                    TaskNote(id: "n-1", date: "Last Fall", text: "North corner near the oak tree had the most leaves; took ~15 mins once the ladder was up."),
                    TaskNote(id: "n-2", date: "2 weeks ago", text: "Bought new work gloves - left them on the workbench.")
                ],
                lastSurfacedAt: "2026-10-15",
                estMinutes: 25,
                updatedAt: seedDate
            ),
            TaskItem(
                id: "t-2",
                title: "Wipe down kitchen espresso machine wand",
                context: .anywhere,
                effort: .quick,
                season: .any,
                notes: "Takes 3 minutes with a damp microfiber cloth.",
                previousNotes: [
                    TaskNote(id: "n-3", date: "Last month", text: "Soaking the tip in warm water for 60s first makes it effortless.")
                ],
                lastSurfacedAt: "2026-10-20",
                oneThing: true,
                estMinutes: 5,
                updatedAt: seedDate
            ),
            TaskItem(
                id: "t-3",
                title: "Drop off Goodwill donation box in trunk",
                context: .errands,
                effort: .quick,
                season: .any,
                notes: "Already loaded in the car trunk.",
                previousNotes: [
                    TaskNote(id: "n-4", date: "Oct 28", text: "Side drive-thru lane is open until 6pm.")
                ],
                lastSurfacedAt: "2026-10-10",
                estMinutes: 10,
                updatedAt: seedDate
            ),
            TaskItem(
                id: "t-4",
                title: "Pressure wash front porch & patio",
                context: .outside,
                effort: .big,
                season: .spring,
                anchorMonth: 5,
                notes: "Spring-only task (hidden outside Spring).",
                lastSurfacedAt: "2026-05-01",
                estMinutes: 60,
                updatedAt: seedDate
            ),
            TaskItem(
                id: "t-5",
                title: "Check tire pressure & top off wiper fluid",
                context: .outside,
                effort: .quick,
                season: .fall,
                anchorMonth: 11,
                notes: "Portable inflator is in the garage cabinet.",
                lastSurfacedAt: "2026-10-01",
                estMinutes: 10,
                updatedAt: seedDate
            ),
            TaskItem(
                id: "t-6",
                title: "Organize Mac Downloads folder & desktop screenshots",
                context: .computer,
                effort: .quick,
                season: .any,
                notes: "Archive old PDFs, trash DMG installers.",
                previousNotes: [
                    TaskNote(id: "n-5", date: "Oct 19", text: "Sort by Size first to clear old Xcode betas and DMGs.")
                ],
                lastSurfacedAt: "2026-10-18",
                estMinutes: 5,
                updatedAt: seedDate
            ),
            TaskItem(
                id: "t-7",
                title: "Review PR #418: Fix CloudKit background sync",
                context: .computer,
                effort: .medium,
                season: .any,
                notes: "Pushed externally to Computer pool.",
                previousNotes: [
                    TaskNote(id: "n-6", date: "Yesterday", text: "Checked schema diff; just need to verify conflict resolution test.")
                ],
                lastSurfacedAt: "2026-11-01",
                estMinutes: 15,
                source: "GitHub",
                externalRef: "PR #418",
                updatedAt: seedDate
            ),
            TaskItem(
                id: "t-8",
                title: "Reply to accountant email re: Q4 estimated tax",
                context: .computer,
                effort: .quick,
                season: .any,
                notes: "Pushed externally to Computer pool.",
                lastSurfacedAt: "2026-11-02",
                estMinutes: 5,
                source: "Gmail",
                externalRef: "Starred Thread",
                updatedAt: seedDate
            ),
            TaskItem(
                id: "t-9",
                title: "Add SwiftData schema migration test for TasksCore",
                context: .computer,
                effort: .medium,
                season: .any,
                notes: "Added via Copilot CLI MCP server.",
                previousNotes: [
                    TaskNote(id: "n-7", date: "Today", text: "Use in-memory URL in TasksStore unit test.")
                ],
                lastSurfacedAt: "2026-11-04",
                estMinutes: 15,
                source: "Copilot MCP",
                externalRef: "copilot-cli",
                updatedAt: seedDate
            )
        ]
    }
}
