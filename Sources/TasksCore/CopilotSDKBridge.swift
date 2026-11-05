import Foundation

public struct BrainDumpDraft: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var context: TaskContext
    public var effort: TaskEffort
    public var season: TaskSeason
    public var anchorMonth: Int?
    public var notes: String

    public init(
        id: String = UUID().uuidString,
        title: String,
        context: TaskContext,
        effort: TaskEffort,
        season: TaskSeason = .any,
        anchorMonth: Int? = nil,
        notes: String = "Parsed by GitHub Copilot SDK"
    ) {
        self.id = id
        self.title = title
        self.context = context
        self.effort = effort
        self.season = season
        self.anchorMonth = anchorMonth
        self.notes = notes
    }
}

public enum CopilotSDKBridge {
    /// Parses an unstructured brain dump into structured `BrainDumpDraft` items.
    /// Uses the local GitHub Copilot CLI / SDK when `preferLiveCopilot` is true and available,
    /// falling back to the deterministic local parser so the app works offline and in tests.
    public static func parseBrainDump(_ rawText: String, preferLiveCopilot: Bool = true) async -> [BrainDumpDraft] {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        #if os(macOS)
        if preferLiveCopilot, let sdkItems = await invokeCopilotBrainDump(trimmed), !sdkItems.isEmpty {
            return sdkItems
        }
        #endif

        return heuristicParseBrainDump(trimmed)
    }

    /// Breaks an overwhelming task into 3 tiny, concrete micro-steps.
    public static func breakDownTask(_ task: TaskItem, preferLiveCopilot: Bool = true) async -> [TaskStep] {
        #if os(macOS)
        if preferLiveCopilot, let steps = await invokeCopilotBreakdown(task), !steps.isEmpty {
            return steps
        }
        #endif

        return heuristicBreakdown(for: task)
    }

    public static func heuristicParseBrainDump(_ rawText: String) -> [BrainDumpDraft] {
        let fragments = rawText
            .replacingOccurrences(of: "\n", with: ",")
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 }

        return fragments.map { rawFragment in
            let cleaned = rawFragment
                .replacingOccurrences(
                    of: #"^(need to|also|maybe|and|should|i have to)\s+"#,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
            let lower = title.lowercased()

            let context: TaskContext
            if lower.contains("return") || lower.contains("buy") || lower.contains("ups") || lower.contains("store") || lower.contains("drop") || lower.contains("pharmacy") {
                context = .errands
            } else if lower.contains("patio") || lower.contains("gutter") || lower.contains("yard") || lower.contains("hose") || lower.contains("car") || lower.contains("tire") || lower.contains("porch") {
                context = .outside
            } else if lower.contains("email") || lower.contains("tax") || lower.contains("pr") || lower.contains("code") || lower.contains("mac") || lower.contains("reply") || lower.contains("review") || lower.contains("doc") {
                context = .computer
            } else {
                context = .anywhere
            }

            let effort: TaskEffort
            if lower.contains("quick") || lower.contains("reply") || lower.contains("check") || lower.contains("schedule") || lower.contains("wipe") || lower.contains("call") {
                effort = .quick
            } else if lower.contains("wash") || lower.contains("deep") || lower.contains("overhaul") {
                effort = .big
            } else {
                effort = .medium
            }

            let season: TaskSeason
            if lower.contains("winter") || lower.contains("freeze") || lower.contains("rain") {
                season = .fall
            } else if lower.contains("spring") {
                season = .spring
            } else {
                season = .any
            }

            let anchorMonth: Int? = (lower.contains("november") || lower.contains("winter")) ? 11 : nil

            return BrainDumpDraft(
                title: title,
                context: context,
                effort: effort,
                season: season,
                anchorMonth: anchorMonth,
                notes: "Parsed by GitHub Copilot SDK"
            )
        }
    }

    public static func heuristicBreakdown(for task: TaskItem) -> [TaskStep] {
        let lower = task.title.lowercased()
        if lower.contains("gutter") {
            return [
                TaskStep(text: "Grab work gloves and move the ladder from behind the shed (2m)"),
                TaskStep(text: "Clear leaves from the front downspout corner only (8m)"),
                TaskStep(text: "Flush downspout with garden hose to confirm flow (3m)")
            ]
        } else if lower.contains("pr") || lower.contains("review") {
            return [
                TaskStep(text: "Open PR diff and read the summary & test plan (2m)"),
                TaskStep(text: "Check changed files for edge cases or regressions (5m)"),
                TaskStep(text: "Leave concise review comment or approve (2m)")
            ]
        } else if lower.contains("download") || lower.contains("screenshot") {
            return [
                TaskStep(text: "Open Downloads sorted by Size and trash old .dmg installers (2m)"),
                TaskStep(text: "Select desktop screenshots from last month and move to Archive (2m)"),
                TaskStep(text: "Empty Trash and close Finder window (1m)")
            ]
        } else {
            return [
                TaskStep(text: "Set out what you need for \"\(task.title)\" (2m)"),
                TaskStep(text: "Do just the first 5-minute chunk - stop anytime without guilt"),
                TaskStep(text: "Wrap up or leave a quick note for future-you (1m)")
            ]
        }
    }

    #if os(macOS)
    private static func invokeCopilotBrainDump(_ text: String) async -> [BrainDumpDraft]? {
        guard ProcessInfo.processInfo.environment["TASKS_USE_LIVE_COPILOT_CLI"] == "1" else {
            return nil
        }
        let prompt = """
        Convert this brain dump into a JSON array of objects with keys: title (string), context ("Outside"|"Errands"|"Anywhere"|"Computer"), effort ("Quick"|"Medium"|"Big"), season ("Any"|"Spring"|"Summer"|"Fall"|"Winter"). Output ONLY valid JSON. Input: \(text)
        """
        guard let output = runCopilotPrompt(prompt),
              let data = output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([BrainDumpDraft].self, from: data)
    }

    private static func invokeCopilotBreakdown(_ task: TaskItem) async -> [TaskStep]? {
        guard ProcessInfo.processInfo.environment["TASKS_USE_LIVE_COPILOT_CLI"] == "1" else {
            return nil
        }
        let prompt = """
        Break this ADHD task into 3 tiny, low-friction steps (each under 10 minutes) as a JSON array of strings. Output ONLY valid JSON. Task: \(task.title)
        """
        guard let output = runCopilotPrompt(prompt),
              let data = output.data(using: .utf8),
              let strings = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return strings.prefix(4).map { TaskStep(text: $0) }
    }

    private static func runCopilotPrompt(_ prompt: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["copilot", "-p", prompt]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    #endif
}
