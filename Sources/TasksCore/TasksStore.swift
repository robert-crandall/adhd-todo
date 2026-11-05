import Combine
import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

@MainActor
public final class TasksStore: ObservableObject {
    public nonisolated static let appGroupIdentifier = "7492ZAHAJV.group.org.robertcrandall.Tasks"
    public nonisolated static let darwinNotificationName = "org.robertcrandall.Tasks.stateChanged"

    @Published public private(set) var state: TasksState
    @Published public var syncStatus: String = "App Group + iCloud ready"
    @Published public var activeTimerTaskId: String?
    @Published public var timerRemainingSeconds: Int = 0
    @Published public var timerRunning: Bool = false

    public let storageURL: URL
    private let cloudKit: CloudKitSyncManager
    private var suppressDarwinPost = false
    private var focusTimerCancellable: AnyCancellable?

    public init(storageURL: URL? = nil, enableCloudKit: Bool? = nil) {
        let resolvedURL = storageURL ?? Self.defaultStorageURL()
        self.storageURL = resolvedURL
        self.cloudKit = CloudKitSyncManager(
            enableCloudKit: enableCloudKit ?? CloudKitSyncManager.hasCloudKitEntitlementInCurrentProcess()
        )

        if let loaded = Self.loadState(from: resolvedURL) {
            self.state = Self.reconcileDraws(loaded)
        } else {
            let initial = Self.reconcileDraws(TasksState())
            self.state = initial
            Self.saveState(initial, to: resolvedURL)
        }

        registerDarwinObserver()

        Task {
            let status = await cloudKit.statusSummary()
            self.syncStatus = status
            if let remoteTasks = await cloudKit.pullRemoteTasks(), !remoteTasks.isEmpty {
                mergeRemoteTasks(remoteTasks)
            }
        }
    }

    public nonisolated static func defaultStorageURL() -> URL {
        if let envPath = ProcessInfo.processInfo.environment["TASKS_STORAGE_PATH"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath)
        }
        let fm = FileManager.default
        #if os(iOS) || os(watchOS)
        if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.org.robertcrandall.Tasks") {
            try? fm.createDirectory(at: groupURL, withIntermediateDirectories: true)
            return groupURL.appendingPathComponent("tasks-state.json")
        }
        #endif
        let groupDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(appGroupIdentifier)", isDirectory: true)
        try? fm.createDirectory(at: groupDir, withIntermediateDirectories: true)
        return groupDir.appendingPathComponent("tasks-state.json")
    }

    public nonisolated static func loadState(from url: URL) -> TasksState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.tasksDecoder.decode(TasksState.self, from: data)
    }

    @discardableResult
    public nonisolated static func saveState(_ state: TasksState, to url: URL) -> Bool {
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder.tasksEncoder.encode(state)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Coordinates cross-process read-modify-write on the shared state file using an exclusive flock lockfile.
    public nonisolated static func mutateStateOnDisk<T>(
        at url: URL,
        _ mutation: (inout TasksState) throws -> T
    ) throws -> T {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lockURL = url.appendingPathExtension("lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        if fd >= 0 {
            _ = flock(fd, LOCK_EX)
        }
        defer {
            if fd >= 0 {
                _ = flock(fd, LOCK_UN)
                close(fd)
            }
        }

        var current = loadState(from: url) ?? TasksState()
        let result = try mutation(&current)
        let data = try JSONEncoder.tasksEncoder.encode(current)
        try data.write(to: url, options: .atomic)
        postDarwinNotification()
        return result
    }

    public nonisolated static func postDarwinNotification() {
        #if os(macOS) || os(iOS) || os(watchOS)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(darwinNotificationName as CFString),
            nil,
            nil,
            true
        )
        #endif
    }

    deinit {
        #if os(macOS) || os(iOS) || os(watchOS)
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
        #endif
    }

    private func registerDarwinObserver() {
        #if os(macOS) || os(iOS) || os(watchOS)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let store = Unmanaged<TasksStore>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    store.reloadFromDiskIfChanged()
                }
            },
            Self.darwinNotificationName as CFString,
            nil,
            .deliverImmediately
        )
        #endif
    }

    public func reloadFromDiskIfChanged() {
        guard !suppressDarwinPost,
              let diskState = Self.loadState(from: storageURL) else { return }
        let reconciled = Self.reconcileDraws(diskState)
        if reconciled != state {
            state = reconciled
            let tasksSnapshot = reconciled.tasks
            Task {
                await cloudKit.pushTasks(tasksSnapshot)
                self.syncStatus = await cloudKit.statusSummary()
            }
        }
    }

    private static func reconcileDraws(_ input: TasksState) -> TasksState {
        var next = input
        let life = DrawEngine.computeLifeDraw(
            tasks: next.tasks,
            existingDraw: next.weeklyDraw,
            month: next.currentMonth,
            season: next.currentSeason,
            todayISO: next.todayISO
        )
        next.weeklyDraw = life.ids
        let pulls = DrawEngine.computePullCandidates(
            tasks: next.tasks,
            lifeDraw: next.weeklyDraw,
            contextFilter: next.pullContextFilter,
            effortFilter: next.pullEffortFilter,
            workHoursOn: next.workHoursOn,
            month: next.currentMonth,
            season: next.currentSeason,
            todayISO: next.todayISO
        )
        next.pullResults = pulls.map(\.id)
        return next
    }

    private func commit(_ mutation: (inout TasksState) -> Void, logMessage: String? = nil) {
        var next = state
        mutation(&next)
        if let logMessage {
            let stamp = Self.shortTimeString()
            next.activityLog.insert("\(stamp)  \(logMessage)", at: 0)
            if next.activityLog.count > 40 {
                next.activityLog = Array(next.activityLog.prefix(40))
            }
        }
        next = Self.reconcileDraws(next)
        state = next
        suppressDarwinPost = true
        Self.saveState(next, to: storageURL)
        Self.postDarwinNotification()
        suppressDarwinPost = false

        let tasksSnapshot = next.tasks
        Task {
            await cloudKit.pushTasks(tasksSnapshot)
            self.syncStatus = await cloudKit.statusSummary()
        }
    }

    private func mergeRemoteTasks(_ remoteTasks: [TaskItem]) {
        commit({ st in
            var byId = Dictionary(uniqueKeysWithValues: st.tasks.map { ($0.id, $0) })
            for remote in remoteTasks {
                if let local = byId[remote.id] {
                    if remote.updatedAt > local.updatedAt {
                        byId[remote.id] = remote
                    }
                } else {
                    byId[remote.id] = remote
                }
            }
            st.tasks = Array(byId.values).sorted { $0.id < $1.id }
        }, logMessage: nil)
    }

    private static func shortTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    // MARK: - Derived Views

    public var lifeDrawTasks: (quick: TaskItem?, medium: TaskItem?) {
        let res = DrawEngine.computeLifeDraw(
            tasks: state.tasks,
            existingDraw: state.weeklyDraw,
            month: state.currentMonth,
            season: state.currentSeason,
            todayISO: state.todayISO
        )
        return (res.quick, res.medium)
    }

    public var computerDraw: ComputerDrawResult {
        DrawEngine.computeComputerDraw(
            tasks: state.tasks,
            workHoursOn: state.workHoursOn,
            month: state.currentMonth,
            season: state.currentSeason,
            todayISO: state.todayISO
        )
    }

    public var pullCandidates: [TaskItem] {
        state.pullResults.compactMap { id in
            state.tasks.first { $0.id == id && $0.status == .active && !$0.isDeleted }
        }
    }

    public var oneThingTask: TaskItem? {
        if let pinned = state.tasks.first(where: {
            $0.status == .active && !$0.isDeleted && $0.oneThing && (state.workHoursOn || $0.pool == .life)
        }) {
            return pinned
        }
        return lifeDrawTasks.quick ?? computerDraw.visible.first
    }

    public var zenDeckTasks: [(slotLabel: String, task: TaskItem)] {
        var deck: [(String, TaskItem)] = []
        let life = lifeDrawTasks
        if let q = life.quick {
            deck.append(("Life Draw · Quick (~5m)", q))
        }
        if let m = life.medium {
            deck.append(("Life Draw · Medium (~20m)", m))
        }
        for workTask in computerDraw.visible {
            deck.append(("Computer / Work Pool", workTask))
        }
        return deck
    }

    // MARK: - User Actions

    public func setHomeLayout(_ mode: HomeLayoutMode) {
        commit({ $0.homeLayout = mode }, logMessage: "[Layout] Switched view to \(mode.rawValue)")
    }

    public func toggleHideTags() {
        commit({ $0.hideTags.toggle() }, logMessage: "[Surface] Tags \(state.hideTags ? "shown" : "hidden")")
    }

    public func toggleHardDayMode() {
        commit({ $0.hardDayMode.toggle() }, logMessage: "[Hard Day] Hard Day mode \(!state.hardDayMode ? "enabled" : "disabled")")
    }

    public func toggleWorkDuty() {
        commit({ $0.workHoursOn.toggle() }, logMessage: "[Work Pool] Computer / Work pool \(!state.workHoursOn ? "On Duty" : "Off Duty")")
    }

    public func toggleExpandedTask(_ taskId: String) {
        commit({ st in
            st.expandedTaskId = (st.expandedTaskId == taskId) ? nil : taskId
        })
    }

    public func stepZenDeck(_ delta: Int) {
        let count = max(1, zenDeckTasks.count)
        commit({ st in
            st.zenIndex = (st.zenIndex + delta + count) % count
        })
    }

    public func setSeasonAndMonth(season: TaskSeason, month: Int) {
        commit({ st in
            st.currentSeason = season
            st.currentMonth = month
            st.weeklyDraw = WeeklyDrawIds()
        }, logMessage: "[Calendar] Season \(season.rawValue), Month \(month)")
    }

    public func updatePullFilter(context: String? = nil, effort: String? = nil) {
        commit({ st in
            if let context { st.pullContextFilter = context }
            if let effort { st.pullEffortFilter = effort }
        }, logMessage: "[Pull] Filter Context=\(context ?? state.pullContextFilter), Effort=\(effort ?? state.pullEffortFilter)")
    }

    public func completeTask(_ taskId: String) {
        guard let title = state.tasks.first(where: { $0.id == taskId })?.title else { return }
        if activeTimerTaskId == taskId {
            stopTimer()
        }
        commit({ st in
            guard let idx = st.tasks.firstIndex(where: { $0.id == taskId }) else { return }
            st.tasks[idx].status = .done
            st.tasks[idx].oneThing = false
            st.tasks[idx].updatedAt = Date()
            if st.weeklyDraw.quickId == taskId { st.weeklyDraw.quickId = nil }
            if st.weeklyDraw.mediumId == taskId { st.weeklyDraw.mediumId = nil }
            if st.expandedTaskId == taskId { st.expandedTaskId = nil }
        }, logMessage: "[Done] Completed \"\(title)\"")
    }

    public func notNowTask(_ taskId: String) {
        guard let title = state.tasks.first(where: { $0.id == taskId })?.title else { return }
        commit({ st in
            guard let idx = st.tasks.firstIndex(where: { $0.id == taskId }) else { return }
            st.tasks[idx].cooldownUntil = TasksDateHelper.addDays(to: st.todayISO, days: 4)
            st.tasks[idx].lastSurfacedAt = st.todayISO
            st.tasks[idx].updatedAt = Date()
            if st.weeklyDraw.quickId == taskId { st.weeklyDraw.quickId = nil }
            if st.weeklyDraw.mediumId == taskId { st.weeklyDraw.mediumId = nil }
            if st.expandedTaskId == taskId { st.expandedTaskId = nil }
        }, logMessage: "[Not Now] Returned \"\(title)\" to pool with cooldown")
    }

    public func rerollLifeDraw() {
        commit({ st in
            let nextCooldown = TasksDateHelper.addDays(to: st.todayISO, days: 4)
            for id in [st.weeklyDraw.quickId, st.weeklyDraw.mediumId].compactMap({ $0 }) {
                if let idx = st.tasks.firstIndex(where: { $0.id == id }) {
                    st.tasks[idx].cooldownUntil = nextCooldown
                    st.tasks[idx].lastSurfacedAt = st.todayISO
                    st.tasks[idx].updatedAt = Date()
                }
            }
            st.weeklyDraw = WeeklyDrawIds()
        }, logMessage: "[Reroll] Re-dealt Life Draw without guilt")
    }

    public func snoozeTask(_ taskId: String, untilISO: String? = nil) {
        guard let title = state.tasks.first(where: { $0.id == taskId })?.title else { return }
        commit({ st in
            guard let idx = st.tasks.firstIndex(where: { $0.id == taskId }) else { return }
            let resolvedUntil = untilISO ?? TasksDateHelper.addDays(to: st.todayISO, days: 7)
            st.tasks[idx].snoozedUntil = resolvedUntil
            st.tasks[idx].updatedAt = Date()
            if st.weeklyDraw.quickId == taskId { st.weeklyDraw.quickId = nil }
            if st.weeklyDraw.mediumId == taskId { st.weeklyDraw.mediumId = nil }
        }, logMessage: "[Snooze] Hid \"\(title)\" for 1 week")
    }

    public func addSelfNote(taskId: String, text: String, dateLabel: String = "Just now") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let title = state.tasks.first(where: { $0.id == taskId })?.title else { return }
        commit({ st in
            guard let idx = st.tasks.firstIndex(where: { $0.id == taskId }) else { return }
            st.tasks[idx].previousNotes.insert(TaskNote(date: dateLabel, text: trimmed), at: 0)
            st.tasks[idx].updatedAt = Date()
        }, logMessage: "[Self Note] Saved note on \"\(title)\"")
    }

    public func toggleStep(taskId: String, stepId: String) {
        commit({ st in
            guard let tIdx = st.tasks.firstIndex(where: { $0.id == taskId }),
                  let sIdx = st.tasks[tIdx].steps.firstIndex(where: { $0.id == stepId }) else { return }
            st.tasks[tIdx].steps[sIdx].done.toggle()
            st.tasks[tIdx].updatedAt = Date()
        })
    }

    public func pinAsOneThing(_ taskId: String) {
        guard let title = state.tasks.first(where: { $0.id == taskId })?.title else { return }
        commit({ st in
            for i in st.tasks.indices {
                st.tasks[i].oneThing = (st.tasks[i].id == taskId)
            }
            if let idx = st.tasks.firstIndex(where: { $0.id == taskId }), st.tasks[idx].pool == .life {
                st.weeklyDraw.quickId = taskId
            }
        }, logMessage: "[One Thing] Pinned \"\(title)\"")
    }

    @discardableResult
    public func addTask(
        title: String,
        context: TaskContext = .anywhere,
        effort: TaskEffort = .quick,
        season: TaskSeason = .any,
        anchorMonth: Int? = nil,
        notes: String = "",
        source: String? = nil,
        externalRef: String? = nil
    ) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let newTask = TaskItem(
            id: "t-\(Int(Date().timeIntervalSince1970 * 1000))-\(Int.random(in: 100...999))",
            title: trimmed,
            context: context,
            effort: effort,
            season: season,
            anchorMonth: anchorMonth,
            notes: notes,
            previousNotes: notes.isEmpty ? [] : [TaskNote(date: "Added", text: notes)],
            source: source,
            externalRef: externalRef
        )
        commit({ st in
            st.tasks.insert(newTask, at: 0)
        }, logMessage: "[Capture] Added \"\(trimmed)\" to \(newTask.pool.rawValue)")
        return newTask
    }

    public func breakDownTaskWithCopilot(_ taskId: String) async {
        guard let task = state.tasks.first(where: { $0.id == taskId }) else { return }
        let steps = await CopilotSDKBridge.breakDownTask(task)
        commit({ st in
            guard let idx = st.tasks.firstIndex(where: { $0.id == taskId }) else { return }
            st.tasks[idx].steps = steps
            st.tasks[idx].updatedAt = Date()
            st.expandedTaskId = taskId
        }, logMessage: "[Copilot SDK] Broke \"\(task.title)\" into \(steps.count) micro-steps")
    }

    public func importBrainDumpDrafts(_ drafts: [BrainDumpDraft]) {
        guard !drafts.isEmpty else { return }
        commit({ st in
            for draft in drafts {
                let item = TaskItem(
                    id: "t-bd-\(UUID().uuidString.prefix(8))",
                    title: draft.title,
                    context: draft.context,
                    effort: draft.effort,
                    season: draft.season,
                    anchorMonth: draft.anchorMonth,
                    notes: draft.notes
                )
                st.tasks.insert(item, at: 0)
            }
        }, logMessage: "[Copilot SDK] Imported \(drafts.count) brain dump tasks into pools")
    }

    // MARK: - Gentle Focus Timer

    public func startTimer(for taskId: String, minutes: Int? = nil) {
        guard let task = state.tasks.first(where: { $0.id == taskId }) else { return }
        let mins = minutes ?? task.estMinutes
        activeTimerTaskId = taskId
        timerRemainingSeconds = max(60, mins * 60)
        timerRunning = true
        if focusTimerCancellable == nil {
            focusTimerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.tickTimer()
                }
        }
    }

    public func tickTimer() {
        guard timerRunning, activeTimerTaskId != nil else { return }
        if timerRemainingSeconds > 0 {
            timerRemainingSeconds -= 1
        }
        if timerRemainingSeconds == 0 {
            stopTimer()
        }
    }

    public func toggleTimerPause() {
        guard activeTimerTaskId != nil else { return }
        timerRunning.toggle()
    }

    public func stopTimer() {
        activeTimerTaskId = nil
        timerRemainingSeconds = 0
        timerRunning = false
        focusTimerCancellable?.cancel()
        focusTimerCancellable = nil
    }
}
