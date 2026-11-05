import Foundation

public struct ComputerDrawResult: Sendable, Equatable {
    public var visible: [TaskItem]
    public var suppressedCount: Int
    public var totalEligibleCount: Int

    public init(visible: [TaskItem], suppressedCount: Int, totalEligibleCount: Int) {
        self.visible = visible
        self.suppressedCount = suppressedCount
        self.totalEligibleCount = totalEligibleCount
    }
}

public enum DrawEngine {
    /// Checks whether a task is eligible to be surfaced today.
    public static func isEligible(
        _ task: TaskItem,
        month: Int,
        season: TaskSeason,
        todayISO: String,
        respectCooldown: Bool = true
    ) -> Bool {
        guard !task.isDeleted, task.status == .active else { return false }

        if let snoozedUntil = task.snoozedUntil, snoozedUntil > todayISO {
            return false
        }
        if respectCooldown, let cooldownUntil = task.cooldownUntil, cooldownUntil > todayISO {
            return false
        }
        if task.season != .any && task.season != season {
            return false
        }
        if let anchor = task.anchorMonth, anchor != month {
            return false
        }
        return true
    }

    /// Sorts tasks by oldest-surfaced first, with anchor-month boost.
    public static func sortForDraw(_ tasks: [TaskItem], month: Int) -> [TaskItem] {
        tasks.sorted { a, b in
            let aAnchor = (a.anchorMonth == month) ? 0 : 1
            let bAnchor = (b.anchorMonth == month) ? 0 : 1
            if aAnchor != bAnchor { return aAnchor < bAnchor }
            let aDate = a.lastSurfacedAt ?? "0000-00-00"
            let bDate = b.lastSurfacedAt ?? "0000-00-00"
            if aDate != bDate { return aDate < bDate }
            return a.id < b.id
        }
    }

    /// Computes the 2-card weekly draw for the Life Pool only (Outside, Errands, Anywhere).
    /// Computer / Work tasks are strictly excluded from the Life Draw.
    public static func computeLifeDraw(
        tasks: [TaskItem],
        existingDraw: WeeklyDrawIds = WeeklyDrawIds(),
        month: Int,
        season: TaskSeason,
        todayISO: String
    ) -> (quick: TaskItem?, medium: TaskItem?, ids: WeeklyDrawIds) {
        let currentWeek = TasksDateHelper.isoWeekKey(for: todayISO)
        let activeExisting = (existingDraw.weekKey == nil || existingDraw.weekKey == currentWeek)
            ? existingDraw
            : WeeklyDrawIds(weekKey: currentWeek)

        let lifeEligible = sortForDraw(
            tasks.filter {
                $0.pool == .life && isEligible($0, month: month, season: season, todayISO: todayISO, respectCooldown: true)
            },
            month: month
        )

        let existingQuick = lifeEligible.first { $0.id == activeExisting.quickId }
        let quick = existingQuick
            ?? lifeEligible.first { $0.effort == .quick }
            ?? lifeEligible.first

        let existingMedium = lifeEligible.first { $0.id == activeExisting.mediumId && $0.id != quick?.id }
        let medium = existingMedium
            ?? lifeEligible.first { $0.id != quick?.id && ($0.effort == .medium || $0.effort == .big) }
            ?? lifeEligible.first { $0.id != quick?.id }

        let ids = WeeklyDrawIds(quickId: quick?.id, mediumId: medium?.id, weekKey: currentWeek)
        return (quick: quick, medium: medium, ids: ids)
    }

    /// Computes the Computer / Weekday Work draw (up to `maxCards`, default 3).
    /// When `workHoursOn` is false, all Computer / Work tasks are suppressed.
    public static func computeComputerDraw(
        tasks: [TaskItem],
        workHoursOn: Bool,
        month: Int,
        season: TaskSeason,
        todayISO: String,
        maxCards: Int = 3
    ) -> ComputerDrawResult {
        let allActiveComputer = tasks.filter { !$0.isDeleted && $0.status == .active && $0.pool == .computerWork }
        guard workHoursOn else {
            return ComputerDrawResult(visible: [], suppressedCount: allActiveComputer.count, totalEligibleCount: 0)
        }

        let eligible = sortForDraw(
            allActiveComputer.filter { isEligible($0, month: month, season: season, todayISO: todayISO, respectCooldown: true) },
            month: month
        )
        let visible = Array(eligible.prefix(maxCards))
        return ComputerDrawResult(
            visible: visible,
            suppressedCount: max(0, eligible.count - visible.count),
            totalEligibleCount: eligible.count
        )
    }

    /// Computes up to `limit` (default 3) pull candidates matching context and effort filters.
    public static func computePullCandidates(
        tasks: [TaskItem],
        lifeDraw: WeeklyDrawIds,
        contextFilter: String,
        effortFilter: String,
        workHoursOn: Bool,
        month: Int,
        season: TaskSeason,
        todayISO: String,
        limit: Int = 3
    ) -> [TaskItem] {
        let candidates = sortForDraw(
            tasks.filter { task in
                guard isEligible(task, month: month, season: season, todayISO: todayISO, respectCooldown: true) else {
                    return false
                }
                if task.id == lifeDraw.quickId || task.id == lifeDraw.mediumId {
                    return false
                }
                if !workHoursOn && task.pool == .computerWork {
                    return false
                }
                let matchesContext = (contextFilter == "Any")
                    || (task.context.rawValue == contextFilter)
                    || (task.context == .anywhere && contextFilter != "Computer")
                let matchesEffort = (effortFilter == "Any") || (task.effort.rawValue == effortFilter)
                return matchesContext && matchesEffort
            },
            month: month
        )
        return Array(candidates.prefix(limit))
    }

    /// Returns active tasks anchored to the given month (1...12).
    public static func computeAnchorReminders(tasks: [TaskItem], month: Int) -> [TaskItem] {
        tasks.filter { !$0.isDeleted && $0.status == .active && $0.anchorMonth == month }
    }
}
