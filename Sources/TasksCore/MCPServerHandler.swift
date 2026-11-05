import Foundation

/// Stateless JSON-RPC 2.0 Model Context Protocol (MCP) handler operating on the shared `TasksStore` file.
/// Used by the `tasks-mcp` stdio server (for GitHub Copilot CLI and Claude Desktop) and unit tests.
public struct MCPServerHandler: Sendable {
    public let storageURL: URL

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? TasksStore.defaultStorageURL()
    }

    public func handleLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else {
            return nil
        }
        let rawObj: Any
        do {
            rawObj = try JSONSerialization.jsonObject(with: data)
        } catch {
            return encodeResponse(id: NSNull(), error: ["code": -32700, "message": "Parse error"])
        }
        guard let json = rawObj as? [String: Any] else {
            return encodeResponse(id: NSNull(), error: ["code": -32600, "message": "Invalid Request"])
        }

        let method = json["method"] as? String ?? ""
        let id = json["id"]
        let params = json["params"] as? [String: Any] ?? [:]

        // Notifications (no id) do not return a JSON-RPC response
        if id == nil {
            return nil
        }

        let result: [String: Any]
        switch method {
        case "initialize":
            result = [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": ["listChanged": false]
                ],
                "serverInfo": [
                    "name": "tasks-mcp",
                    "version": "1.0.0"
                ]
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": Self.toolDefinitions]
        case "tools/call":
            result = handleToolCall(params: params)
        default:
            return encodeResponse(id: id, error: ["code": -32601, "message": "Method not found: \(method)"])
        }

        return encodeResponse(id: id, result: result)
    }

    public static var toolDefinitions: [[String: Any]] {
        [
            [
                "name": "add_task",
                "description": "Push a task into Tasks. Externally pushed work/code/email items default to the Computer / Work pool; personal items use Outside, Errands, or Anywhere (Life pool).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Actionable task title"],
                        "context": [
                            "type": "string",
                            "enum": ["Computer", "Outside", "Errands", "Anywhere"],
                            "description": "Defaults to Computer for agent-pushed tasks"
                        ],
                        "effort": [
                            "type": "string",
                            "enum": ["Quick", "Medium", "Big"],
                            "description": "Quick (~5m), Medium (~20m), or Big (45m+)"
                        ],
                        "notes": ["type": "string", "description": "Optional note from yourself or context link"],
                        "source": ["type": "string", "description": "Source badge (e.g. Copilot MCP, Claude MCP, GitHub, Gmail)"],
                        "externalRef": ["type": "string", "description": "Optional PR/issue/thread reference"]
                    ],
                    "required": ["title"]
                ]
            ],
            [
                "name": "list_drawn_tasks",
                "description": "List the active Life Draw (2 weekly slots) and Computer / Work Pool draw.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ]
            ],
            [
                "name": "complete_task",
                "description": "Mark a task done by task ID or case-insensitive title substring.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Task ID or title substring to mark Done"]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "add_self_note",
                "description": "Leave a timestamped 'Note from Yourself' on an existing task for future-you.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Task ID or title substring"],
                        "note": ["type": "string", "description": "Note text to save on the task"]
                    ],
                    "required": ["query", "note"]
                ]
            ],
            [
                "name": "brain_dump",
                "description": "Parse an unstructured brain dump string into structured tasks across Life and Computer pools.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "Raw brain dump text separated by commas or newlines"]
                    ],
                    "required": ["text"]
                ]
            ]
        ]
    }

    private func handleToolCall(params: [String: Any]) -> [String: Any] {
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]

        switch name {
        case "add_task":
            let title = (args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                return textResult("Error: 'title' is required.", isError: true)
            }
            let contextRaw = args["context"] as? String ?? "Computer"
            let context = TaskContext(rawValue: contextRaw) ?? .computer
            let effortRaw = args["effort"] as? String ?? "Quick"
            let effort = TaskEffort(rawValue: effortRaw) ?? .quick
            let notes = args["notes"] as? String ?? ""
            let source = args["source"] as? String ?? (context == .computer ? "Copilot MCP" : nil)
            let externalRef = args["externalRef"] as? String

            do {
                let stamp = TasksDateHelper.noteTimestampString()
                let item = try TasksStore.mutateStateOnDisk(at: storageURL) { state in
                    let nowParts = TasksDateHelper.currentDateParts()
                    if state.todayISO != nowParts.todayISO {
                        state.todayISO = nowParts.todayISO
                        state.currentMonth = nowParts.month
                        state.currentSeason = nowParts.season
                    }
                    let created = TaskItem(
                        id: "t-mcp-\(Int(Date().timeIntervalSince1970 * 1000))-\(Int.random(in: 100...999))",
                        title: title,
                        context: context,
                        effort: effort,
                        notes: notes,
                        previousNotes: notes.isEmpty ? [] : [TaskNote(date: stamp, text: notes)],
                        lastSurfacedAt: state.todayISO,
                        source: source,
                        externalRef: externalRef
                    )
                    state.tasks.insert(created, at: 0)
                    return created
                }
                return textResult("Added '\(item.title)' (\(item.effort.rawValue)) to \(item.pool.rawValue) [id: \(item.id)]")
            } catch {
                return textResult("Failed to persist task: \(error.localizedDescription)", isError: true)
            }

        case "list_drawn_tasks":
            let state = (try? TasksStore.mutateStateOnDisk(at: storageURL) { st in
                st = TasksStore.reconcileDraws(st)
                return st
            }) ?? TasksStore.reconcileDraws(TasksStore.loadState(from: storageURL) ?? TasksState())
            let life = DrawEngine.computeLifeDraw(
                tasks: state.tasks,
                existingDraw: state.weeklyDraw,
                month: state.currentMonth,
                season: state.currentSeason,
                todayISO: state.todayISO
            )
            let work = DrawEngine.computeComputerDraw(
                tasks: state.tasks,
                workHoursOn: state.workHoursOn,
                month: state.currentMonth,
                season: state.currentSeason,
                todayISO: state.todayISO
            )
            var lines: [String] = ["=== Life Draw (Personal) ==="]
            if let q = life.quick {
                lines.append("- [Quick] \(q.title) (\(q.context.rawValue), id: \(q.id))")
            }
            if let m = life.medium {
                lines.append("- [Medium] \(m.title) (\(m.context.rawValue), id: \(m.id))")
            }
            lines.append("")
            lines.append("=== Computer / Weekday Work Pool (\(state.workHoursOn ? "On Duty" : "Off Duty")) ===")
            for t in work.visible {
                lines.append("- [\(t.effort.rawValue)] \(t.title) [id: \(t.id)]")
            }
            return textResult(lines.joined(separator: "\n"))

        case "complete_task":
            let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else {
                return textResult("No active task matching '' found.", isError: true)
            }
            do {
                let completed: (title: String, id: String)? = try TasksStore.mutateStateOnDisk(at: storageURL) { state in
                    let exactIdx = state.tasks.firstIndex { $0.id.lowercased() == query }
                    let idx: Int?
                    if let exactIdx {
                        idx = (state.tasks[exactIdx].status == .active && !state.tasks[exactIdx].isDeleted) ? exactIdx : nil
                    } else {
                        idx = state.tasks.firstIndex {
                            $0.status == .active && !$0.isDeleted && $0.title.lowercased().contains(query)
                        }
                    }
                    guard let resolvedIdx = idx else { return nil }
                    let title = state.tasks[resolvedIdx].title
                    let id = state.tasks[resolvedIdx].id
                    state.tasks[resolvedIdx].status = .done
                    state.tasks[resolvedIdx].updatedAt = Date()
                    if state.weeklyDraw.quickId == id { state.weeklyDraw.quickId = nil }
                    if state.weeklyDraw.mediumId == id { state.weeklyDraw.mediumId = nil }
                    return (title, id)
                }
                guard let completed else {
                    return textResult("No active task matching '\(query)' found.", isError: true)
                }
                return textResult("Completed '\(completed.title)' [id: \(completed.id)]")
            } catch {
                return textResult("Failed to complete task: \(error.localizedDescription)", isError: true)
            }

        case "add_self_note":
            let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let note = (args["note"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty, !note.isEmpty else {
                return textResult("Task matching '\(query)' not found.", isError: true)
            }
            do {
                let stamp = TasksDateHelper.noteTimestampString()
                let matchedTitle: String? = try TasksStore.mutateStateOnDisk(at: storageURL) { state in
                    let exactIdx = state.tasks.firstIndex { $0.id.lowercased() == query }
                    let idx: Int?
                    if let exactIdx {
                        idx = !state.tasks[exactIdx].isDeleted ? exactIdx : nil
                    } else {
                        idx = state.tasks.firstIndex {
                            !$0.isDeleted && $0.title.lowercased().contains(query)
                        }
                    }
                    guard let resolvedIdx = idx else { return nil }
                    state.tasks[resolvedIdx].previousNotes.insert(TaskNote(date: stamp, text: note), at: 0)
                    state.tasks[resolvedIdx].updatedAt = Date()
                    return state.tasks[resolvedIdx].title
                }
                guard let matchedTitle else {
                    return textResult("Task matching '\(query)' not found.", isError: true)
                }
                return textResult("Added self-note to '\(matchedTitle)'")
            } catch {
                return textResult("Failed to save note: \(error.localizedDescription)", isError: true)
            }

        case "brain_dump":
            let text = args["text"] as? String ?? ""
            let drafts = CopilotSDKBridge.heuristicParseBrainDump(text)
            do {
                try TasksStore.mutateStateOnDisk(at: storageURL) { state in
                    for d in drafts {
                        state.tasks.insert(
                            TaskItem(
                                id: "t-mcp-bd-\(UUID().uuidString.prefix(8))",
                                title: d.title,
                                context: d.context,
                                effort: d.effort,
                                season: d.season,
                                anchorMonth: d.anchorMonth,
                                notes: d.notes,
                                lastSurfacedAt: state.todayISO,
                                source: d.context == .computer ? "Copilot MCP" : nil
                            ),
                            at: 0
                        )
                    }
                }
                return textResult("Parsed and added \(drafts.count) tasks from brain dump.")
            } catch {
                return textResult("Failed to persist brain dump: \(error.localizedDescription)", isError: true)
            }

        default:
            return textResult("Unknown tool: \(name)", isError: true)
        }
    }

    private func textResult(_ text: String, isError: Bool = false) -> [String: Any] {
        [
            "content": [
                ["type": "text", "text": text]
            ],
            "isError": isError
        ]
    }

    private func encodeResponse(id: Any?, result: [String: Any]? = nil, error: [String: Any]? = nil) -> String? {
        var payload: [String: Any] = ["jsonrpc": "2.0"]
        if let id { payload["id"] = id }
        if let result { payload["result"] = result }
        if let error { payload["error"] = error }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes]),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }
}
