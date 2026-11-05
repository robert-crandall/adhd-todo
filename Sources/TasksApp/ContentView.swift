import SwiftUI
import TasksCore

struct MainTasksWindow: View {
    @ObservedObject var store: TasksStore
    @Binding var selectedSection: SidebarSection
    @Binding var showingQuickCapture: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(
                store: store,
                selectedSection: $selectedSection,
                showingQuickCapture: $showingQuickCapture
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 270)
        } detail: {
            VStack(spacing: 0) {
                TopHeaderBar(
                    store: store,
                    selectedSection: $selectedSection,
                    showingQuickCapture: $showingQuickCapture
                )

                if let activeId = store.activeTimerTaskId,
                   let task = store.state.tasks.first(where: { $0.id == activeId }) {
                    ActiveTimerBannerView(store: store, task: task)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedSection {
                        case .lifeDraw:
                            LifeDrawDetailView(store: store)
                        case .computerWork:
                            ComputerWorkDetailView(store: store)
                        case .pull:
                            PullTimeDetailView(store: store)
                        case .brainDump:
                            BrainDumpDetailView(store: store, selectedSection: $selectedSection)
                        case .mcp:
                            MCPSimulatorDetailView(store: store, selectedSection: $selectedSection)
                        case .pools:
                            FullPoolsDetailView(store: store)
                        }
                    }
                    .padding(24)
                }
            }
            .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        }
        .sheet(isPresented: $showingQuickCapture) {
            QuickCaptureSheet(store: store, isPresented: $showingQuickCapture)
        }
    }
}

struct SidebarView: View {
    @ObservedObject var store: TasksStore
    @Binding var selectedSection: SidebarSection
    @Binding var showingQuickCapture: Bool

    var body: some View {
        let computerCount = store.computerDraw.visible.count
        let mcpCount = store.state.tasks.filter { $0.status == .active && !$0.isDeleted && ($0.source?.contains("MCP") ?? false) }.count
        let totalActive = store.state.tasks.filter { $0.status == .active && !$0.isDeleted }.count

        List(selection: $selectedSection) {
            Section("Separate Draws") {
                NavigationLink(value: SidebarSection.lifeDraw) {
                    HStack {
                        Label("Life Draw", systemImage: "house.fill")
                        Spacer()
                        Text("2")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                }

                NavigationLink(value: SidebarSection.computerWork) {
                    HStack {
                        Label("Computer / Work", systemImage: "desktopcomputer")
                        Spacer()
                        Text(store.state.workHoursOn ? "\(computerCount)" : "Off")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                }

                NavigationLink(value: SidebarSection.pull) {
                    HStack {
                        Label("I Have Time (Pull)", systemImage: "dice.fill")
                        Spacer()
                        Text("≤3")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                }
            }

            Section("Capture, AI & Pools") {
                NavigationLink(value: SidebarSection.brainDump) {
                    Label("Copilot SDK Dump", systemImage: "brain.head.profile")
                }

                NavigationLink(value: SidebarSection.mcp) {
                    HStack {
                        Label("External MCP Push", systemImage: "terminal.fill")
                        Spacer()
                        Text("\(mcpCount)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2), in: Capsule())
                    }
                }

                NavigationLink(value: SidebarSection.pools) {
                    HStack {
                        Label("Life & Work Pools", systemImage: "square.stack.3d.up.fill")
                        Spacer()
                        Text("\(totalActive)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "icloud.fill")
                        .foregroundStyle(.teal)
                        .font(.caption)
                    Text(store.syncStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("Calm Default: List View shows task titles only. Click any task for your previous notes, Focus Timer & Break it down.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }
}

struct TopHeaderBar: View {
    @ObservedObject var store: TasksStore
    @Binding var selectedSection: SidebarSection
    @Binding var showingQuickCapture: Bool

    var body: some View {
        HStack(spacing: 12) {
            Picker("Layout", selection: Binding(
                get: { store.state.homeLayout },
                set: { store.setHomeLayout($0) }
            )) {
                ForEach(HomeLayoutMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            Button {
                store.toggleHideTags()
            } label: {
                Label(
                    store.state.hideTags ? "Show Tags" : "Hide Tags",
                    systemImage: store.state.hideTags ? "eye" : "eye.slash"
                )
            }
            .buttonStyle(.bordered)

            Button {
                store.toggleHardDayMode()
                if !store.state.hardDayMode {
                    selectedSection = .lifeDraw
                }
            } label: {
                Label(
                    store.state.hardDayMode ? "Exit Hard Day" : "Pick One Thing",
                    systemImage: "flame.fill"
                )
            }
            .buttonStyle(.bordered)
            .tint(store.state.hardDayMode ? .orange : nil)

            Spacer()

            WeekProgressDotsView()

            Button {
                showingQuickCapture = true
            } label: {
                Label("Quick Add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
    }
}

struct WeekProgressDotsView: View {
    private let days = ["M", "T", "W", "T", "F", "S", "S"]
    var body: some View {
        HStack(spacing: 5) {
            Text("Wed · 4d left")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(0..<7, id: \.self) { idx in
                Circle()
                    .fill(idx < 2 ? Color.green : (idx == 2 ? Color.orange : Color.white.opacity(0.18)))
                    .frame(width: 7, height: 7)
                    .help(days[idx])
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.05), in: Capsule())
    }
}

struct ActiveTimerBannerView: View {
    @ObservedObject var store: TasksStore
    let task: TaskItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "timer")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("GENTLE FOCUS BLOCK · STOP ANYTIME WITHOUT GUILT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            Text(formatSeconds(store.timerRemainingSeconds))
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(.orange)

            Button(store.timerRunning ? "Pause" : "Resume") {
                store.toggleTimerPause()
            }
            .buttonStyle(.bordered)

            Button("Done") {
                store.completeTask(task.id)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button("Stop") {
                store.stopTimer()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }
}

// MARK: - 1. Life Draw View

struct LifeDrawDetailView: View {
    @ObservedObject var store: TasksStore

    var body: some View {
        if store.state.hardDayMode {
            HardDaySingleCardView(store: store)
        } else if store.state.homeLayout == .zen {
            ZenDeckView(store: store)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This Week's Draw · Life Pool")
                            .font(.title2.weight(.bold))
                        Text(store.state.homeLayout == .list
                             ? "Calm list view: just your 2 drawn life tasks. Click a task to see your previous notes, Focus Timer & Break it down."
                             : "Card view: showing previous notes from yourself, tags, Focus Timer & Break it down at a glance.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.rerollLifeDraw()
                    } label: {
                        Label("Reroll Both", systemImage: "dice")
                    }
                    .buttonStyle(.bordered)
                }

                let draw = store.lifeDrawTasks
                let items: [(String, TaskItem)] = [
                    draw.quick.map { ("Quick Weekly Slot (~5m)", $0) },
                    draw.medium.map { ("Medium Weekly Slot (~20m)", $0) }
                ].compactMap { $0 }

                if items.isEmpty {
                    EmptyPoolCardView(message: "You finished your Life Draw for the week! Pull a bonus task if you have energy, or enjoy the free time.")
                } else {
                    DrawnTasksCollectionView(store: store, items: items)
                }
            }
        }
    }
}

// MARK: - 2. Computer / Work Pool View

struct ComputerWorkDetailView: View {
    @ObservedObject var store: TasksStore

    var body: some View {
        let workDraw = store.computerDraw
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Computer / Weekday Work Pool")
                        .font(.title2.weight(.bold))
                    Text("Separate from Life Draw. Holds Computer tasks plus externally pushed GitHub, Gmail & MCP items (capped at ≤ 3 active items).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.toggleWorkDuty()
                } label: {
                    Label(
                        store.state.workHoursOn ? "On Duty (Click for Off Duty)" : "Off Duty (Hidden)",
                        systemImage: store.state.workHoursOn ? "desktopcomputer" : "moon.zzz.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(store.state.workHoursOn ? .teal : .gray)
            }

            if !store.state.workHoursOn {
                EmptyPoolCardView(
                    message: "Off Duty: \(workDraw.suppressedCount) Computer / Work tasks are quietly tucked away so you only see personal Life tasks after hours."
                )
            } else if workDraw.visible.isEmpty {
                EmptyPoolCardView(message: "No active Computer / Work tasks right now.")
            } else {
                let items = workDraw.visible.map { task in
                    let label = task.source.map { "Computer Pool · \($0)\(task.externalRef.map { " (\($0))" } ?? "")" } ?? "Computer / Weekday Work"
                    return (label, task)
                }
                DrawnTasksCollectionView(store: store, items: items)
            }
        }
    }
}

// MARK: - Shared List vs. Card Task Renderer

struct DrawnTasksCollectionView: View {
    @ObservedObject var store: TasksStore
    let items: [(slotLabel: String, task: TaskItem)]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(items, id: \.task.id) { item in
                if store.state.homeLayout == .list {
                    TaskListRowView(store: store, task: item.task, slotLabel: item.slotLabel)
                } else {
                    TaskCardDetailView(store: store, task: item.task, slotLabel: item.slotLabel)
                }
            }
        }
    }
}

struct TaskListRowView: View {
    @ObservedObject var store: TasksStore
    let task: TaskItem
    let slotLabel: String
    @State private var noteDraft: String = ""

    var isExpanded: Bool {
        store.state.expandedTaskId == task.id
    }

    var noteCount: Int {
        task.previousNotes.count + (task.notes.isEmpty ? 0 : 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    store.toggleExpandedTask(task.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)

                        Text(task.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        if !isExpanded && noteCount > 0 {
                            Label("\(noteCount) note\(noteCount == 1 ? "" : "s")", systemImage: "note.text")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.14), in: Capsule())
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Button {
                        store.completeTask(task.id)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        store.notNowTask(task.id)
                    } label: {
                        Label("Not Now", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                TaskExpandedBodyView(
                    store: store,
                    task: task,
                    slotLabel: slotLabel,
                    noteDraft: $noteDraft
                )
                .padding(16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isExpanded ? Color.orange.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

struct TaskCardDetailView: View {
    @ObservedObject var store: TasksStore
    let task: TaskItem
    let slotLabel: String
    @State private var noteDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(slotLabel.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.state.hideTags {
                    TaskTagsStrip(task: task)
                }
            }

            Text(task.title)
                .font(.title3.weight(.semibold))

            TaskExpandedBodyView(
                store: store,
                task: task,
                slotLabel: slotLabel,
                noteDraft: $noteDraft,
                includePrimaryButtons: true
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(task.oneThing ? Color.orange.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

struct TaskExpandedBodyView: View {
    @ObservedObject var store: TasksStore
    let task: TaskItem
    let slotLabel: String
    @Binding var noteDraft: String
    var includePrimaryButtons: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !includePrimaryButtons && !store.state.hideTags {
                HStack {
                    Text(slotLabel.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    TaskTagsStrip(task: task)
                }
            }

            // Notes from Yourself
            VStack(alignment: .leading, spacing: 8) {
                Label("NOTES FROM YOURSELF", systemImage: "note.text")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.9))
                }

                ForEach(task.previousNotes) { note in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(note.date):")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("“\(note.text)”")
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                }

                if task.notes.isEmpty && task.previousNotes.isEmpty {
                    Text("No notes yet — leave context for future-you if you skip or pause.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    TextField("Leave a note for next time…", text: $noteDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            saveNote()
                        }
                    Button("Save Note") {
                        saveNote()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))

            // Micro-steps from Break it down
            if !task.steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("COPILOT SDK MICRO-STEPS", systemImage: "sparkles")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.teal)
                    ForEach(task.steps) { step in
                        Button {
                            store.toggleStep(taskId: task.id, stepId: step.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(step.done ? .green : .secondary)
                                Text(step.text)
                                    .font(.callout)
                                    .strikethrough(step.done)
                                    .foregroundStyle(step.done ? .secondary : .primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            // Secondary Action Bar
            HStack(spacing: 8) {
                if includePrimaryButtons {
                    Button {
                        store.completeTask(task.id)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        store.notNowTask(task.id)
                    } label: {
                        Label("Not Now", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    store.startTimer(for: task.id, minutes: task.estMinutes)
                } label: {
                    Label("Focus Timer (\(task.estMinutes)m)", systemImage: "timer")
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await store.breakDownTaskWithCopilot(task.id)
                    }
                } label: {
                    Label("Break it down", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)

                Button {
                    store.snoozeTask(task.id)
                } label: {
                    Label("Snooze 1w", systemImage: "moon.zzz")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    store.pinAsOneThing(task.id)
                } label: {
                    Label(task.oneThing ? "Pinned One Thing" : "Pin One Thing", systemImage: "flame")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func saveNote() {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addSelfNote(taskId: task.id, text: trimmed)
        noteDraft = ""
    }
}

struct TaskTagsStrip: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 6) {
            Text("\(task.effort.rawValue) · ~\(task.estMinutes)m")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.18), in: Capsule())

            Text(task.context.rawValue)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1), in: Capsule())

            if task.season != .any {
                Text(task.season.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.18), in: Capsule())
            }

            if let src = task.source {
                Text(src)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.teal.opacity(0.22), in: Capsule())
            }
        }
    }
}

// MARK: - Hard Day Mode & Zen Deck

struct HardDaySingleCardView: View {
    @ObservedObject var store: TasksStore

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("HARD DAY MODE · EVERYTHING ELSE IS TUCKED AWAY", systemImage: "heart.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                Spacer()
                Button("Return to Full Draw") {
                    store.toggleHardDayMode()
                }
                .buttonStyle(.bordered)
            }

            if let oneThing = store.oneThingTask {
                TaskCardDetailView(
                    store: store,
                    task: oneThing,
                    slotLabel: "Your Only Thing Right Now (~5m)"
                )
            } else {
                EmptyPoolCardView(message: "Nothing urgent at all. Rest up!")
            }
        }
    }
}

struct ZenDeckView: View {
    @ObservedObject var store: TasksStore

    var body: some View {
        let deck = store.zenDeckTasks
        let safeIdx = deck.isEmpty ? 0 : min(store.state.zenIndex, deck.count - 1)

        VStack(spacing: 18) {
            HStack {
                Text("Zen Deck · One Card at a Time")
                    .font(.title3.weight(.bold))
                Spacer()
                if !deck.isEmpty {
                    Text("Card \(safeIdx + 1) of \(deck.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if deck.isEmpty {
                EmptyPoolCardView(message: "All drawn cards are done!")
            } else {
                let current = deck[safeIdx]
                TaskCardDetailView(store: store, task: current.task, slotLabel: current.slotLabel)

                HStack(spacing: 12) {
                    Button("← Previous Card") {
                        store.stepZenDeck(-1)
                    }
                    .buttonStyle(.bordered)

                    Button("Next Card in Draw →") {
                        store.stepZenDeck(1)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

// MARK: - 3. Pull Mode ("I Have Time")

struct PullTimeDetailView: View {
    @ObservedObject var store: TasksStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("I Have Time — Pull Mode (≤ 3 Cards)")
                        .font(.title2.weight(.bold))
                    Text("Pick where you are and how much energy you have. Never shows more than 3 options.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.updatePullFilter()
                } label: {
                    Label("Roll Again", systemImage: "dice")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Where:")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(["Any", "Outside", "Errands", "Anywhere", "Computer"], id: \.self) { ctx in
                        Button(ctx) {
                            store.updatePullFilter(context: ctx)
                        }
                        .buttonStyle(.bordered)
                        .tint(store.state.pullContextFilter == ctx ? .orange : nil)
                    }
                }

                Divider().frame(height: 20)

                HStack(spacing: 6) {
                    Text("Energy:")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(["Any", "Quick", "Medium", "Big"], id: \.self) { eff in
                        Button(eff) {
                            store.updatePullFilter(effort: eff)
                        }
                        .buttonStyle(.bordered)
                        .tint(store.state.pullEffortFilter == eff ? .orange : nil)
                    }
                }
            }

            let results = store.pullCandidates
            if results.isEmpty {
                EmptyPoolCardView(message: "No active tasks match Context=\(store.state.pullContextFilter) + Effort=\(store.state.pullEffortFilter). Try 'Any'.")
            } else {
                let items = results.enumerated().map { idx, t in
                    ("Pull Option #\(idx + 1) of \(results.count)", t)
                }
                DrawnTasksCollectionView(store: store, items: items)
            }
        }
    }
}

// MARK: - 4. Copilot SDK Brain Dump View

struct BrainDumpDetailView: View {
    @ObservedObject var store: TasksStore
    @Binding var selectedSection: SidebarSection
    @State private var rawInput: String = "clean patio furniture before winter, return UPS Amazon package, reply to Sarah's email about Q4 roadmap, maybe check smoke detector batteries, schedule dentist cleaning"
    @State private var drafts: [BrainDumpDraft] = []
    @State private var isParsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Brain Dump Mode (Powered by GitHub Copilot SDK)")
                    .font(.title2.weight(.bold))
                Text("Paste a messy wall of text. Copilot SDK splits it into discrete tasks and routes personal items to Life Pool and work/email items to Computer Pool.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $rawInput)
                .font(.body)
                .frame(height: 100)
                .padding(8)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                Button {
                    isParsing = true
                    Task {
                        drafts = await CopilotSDKBridge.parseBrainDump(rawInput)
                        isParsing = false
                    }
                } label: {
                    Label(isParsing ? "Parsing…" : "Parse with Copilot SDK", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                if !drafts.isEmpty {
                    Button {
                        store.importBrainDumpDrafts(drafts)
                        drafts = []
                        selectedSection = .pools
                    } label: {
                        Label("Add All \(drafts.count) Tasks to Pools", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }

            if !drafts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PARSED PREVIEW (\(drafts.count) ITEMS)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach($drafts) { $draft in
                        HStack(spacing: 12) {
                            TextField("Title", text: $draft.title)
                                .textFieldStyle(.roundedBorder)

                            Picker("Context", selection: $draft.context) {
                                ForEach(TaskContext.allCases) { c in
                                    Text(c.rawValue).tag(c)
                                }
                            }
                            .frame(width: 140)

                            Picker("Effort", selection: $draft.effort) {
                                ForEach(TaskEffort.allCases) { e in
                                    Text(e.rawValue).tag(e)
                                }
                            }
                            .frame(width: 120)
                        }
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - 5. External MCP Push & Config View

struct MCPSimulatorDetailView: View {
    @ObservedObject var store: TasksStore
    @Binding var selectedSection: SidebarSection
    @State private var customTitle: String = "Follow up on PR review comment"
    @State private var customContext: TaskContext = .computer
    @State private var customEffort: TaskEffort = .quick

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("External Push & Local MCP Server (tasks-mcp)")
                    .font(.title2.weight(.bold))
                Text("GitHub, Gmail, Copilot CLI, and Claude Desktop push tasks externally into the shared App Group + iCloud store.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("TEST LIVE EXTERNAL PUSH INTO COMPUTER POOL")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    TextField("Task title…", text: $customTitle)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Picker("Context", selection: $customContext) {
                            ForEach(TaskContext.allCases) { c in
                                Text(c.rawValue).tag(c)
                            }
                        }
                        Picker("Effort", selection: $customEffort) {
                            ForEach(TaskEffort.allCases) { e in
                                Text(e.rawValue).tag(e)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            store.addTask(
                                title: customTitle,
                                context: customContext,
                                effort: customEffort,
                                notes: "Pushed via Copilot CLI MCP",
                                source: "Copilot MCP",
                                externalRef: "copilot-cli"
                            )
                            selectedSection = (customContext == .computer) ? .computerWork : .lifeDraw
                        } label: {
                            Label("Push via Copilot MCP", systemImage: "terminal")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)

                        Button {
                            store.addTask(
                                title: customTitle,
                                context: customContext,
                                effort: customEffort,
                                notes: "Pushed via Claude Desktop MCP",
                                source: "Claude MCP",
                                externalRef: "claude-desktop"
                            )
                            selectedSection = (customContext == .computer) ? .computerWork : .lifeDraw
                        } label: {
                            Label("Push via Claude MCP", systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("MCP SERVER CONFIGURATION (~/.copilot/mcp-config.json)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    let configSnippet = """
                    {
                      "mcpServers": {
                        "tasks": {
                          "command": "/Applications/Tasks.app/Contents/MacOS/tasks-mcp",
                          "args": []
                        }
                      }
                    }
                    """
                    Text(configSnippet)
                        .font(.system(.caption, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)

                    Text("Shared Store Path: \(store.storageURL.path)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(16)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - 6. Full Pools View (Life Pool vs. Computer / Work Pool)

struct FullPoolsDetailView: View {
    @ObservedObject var store: TasksStore

    var body: some View {
        let activeTasks = store.state.tasks.filter { !$0.isDeleted && $0.status == .active }
        let lifeTasks = activeTasks.filter { $0.pool == .life }
        let workTasks = activeTasks.filter { $0.pool == .computerWork }

        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Separate Pools: Life Pool vs. Computer / Work Pool")
                        .font(.title2.weight(.bold))
                    Text("Out of sight on the homepage so you don't feel overwhelmed, but always transparent here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("Season:")
                        .font(.caption.weight(.bold))
                    ForEach([TaskSeason.fall, .spring, .summer, .winter], id: \.self) { s in
                        Button(s.rawValue) {
                            let month = (s == .spring) ? 5 : (s == .summer ? 7 : (s == .winter ? 1 : 11))
                            store.setSeasonAndMonth(season: s, month: month)
                        }
                        .buttonStyle(.bordered)
                        .tint(store.state.currentSeason == s ? .orange : nil)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("LIFE POOL · PERSONAL, OUTSIDE, ERRANDS, ANYWHERE (\(lifeTasks.count))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                ForEach(lifeTasks) { t in
                    TaskListRowView(store: store, task: t, slotLabel: "Life Pool · \(t.context.rawValue)")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("COMPUTER / WEEKDAY WORK POOL · COMPUTER, GITHUB, GMAIL, MCP (\(workTasks.count))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.teal)
                ForEach(workTasks) { t in
                    TaskListRowView(store: store, task: t, slotLabel: "Computer Pool\(t.source.map { " · \($0)" } ?? "")")
                }
            }
        }
    }
}

// MARK: - MenuBarExtra Popover & Quick Capture Sheet

struct MenuBarPopoverView: View {
    @ObservedObject var store: TasksStore
    @Binding var showingQuickCapture: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tasks · One Thing", systemImage: "flame.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                Spacer()
                Text("MCP Ready")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }

            if let oneThing = store.oneThingTask {
                Text(oneThing.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let firstNote = oneThing.previousNotes.first {
                    Text("Note (\(firstNote.date)): “\(firstNote.text)”")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button("Done") {
                        store.completeTask(oneThing.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button("Not Now") {
                        store.notNowTask(oneThing.id)
                    }
                    .buttonStyle(.bordered)

                    Button("5m Focus") {
                        store.startTimer(for: oneThing.id, minutes: 5)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("All clear for right now!")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button(store.state.workHoursOn ? "Work: On Duty" : "Work: Off Duty") {
                    store.toggleWorkDuty()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Reroll Draw") {
                    store.rerollLifeDraw()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 310)
    }
}

struct QuickCaptureSheet: View {
    @ObservedObject var store: TasksStore
    @Binding var isPresented: Bool
    @State private var title: String = ""
    @State private var context: TaskContext = .anywhere
    @State private var effort: TaskEffort = .quick
    @State private var season: TaskSeason = .any
    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Capture into Pool")
                .font(.title3.weight(.bold))
            Text("Drop it in and forget it. No due date required.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("What's on your mind?", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack {
                Picker("Context", selection: $context) {
                    ForEach(TaskContext.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                Picker("Effort", selection: $effort) {
                    ForEach(TaskEffort.allCases) { e in
                        Text(e.rawValue).tag(e)
                    }
                }
                Picker("Season", selection: $season) {
                    ForEach(TaskSeason.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
            }

            TextField("Note for future-you (optional)…", text: $notes)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save to \(context == .computer ? "Computer Pool" : "Life Pool")") {
                    store.addTask(title: title, context: context, effort: effort, season: season, notes: notes)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}

struct EmptyPoolCardView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}
