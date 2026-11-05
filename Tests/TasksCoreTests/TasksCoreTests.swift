import Foundation
import Testing
@testable import TasksCore

@Suite("TasksCore Behavior Tests")
struct TasksCoreTests {
    @Test("Life Draw strictly excludes Computer and externally pushed tasks")
    func lifeDrawExcludesComputerPool() {
        let tasks = TasksState.defaultSeedTasks()
        let draw = DrawEngine.computeLifeDraw(
            tasks: tasks,
            month: 11,
            season: .fall,
            todayISO: "2026-11-04"
        )

        #expect(draw.quick != nil)
        #expect(draw.medium != nil)
        #expect(draw.quick?.pool == .life)
        #expect(draw.medium?.pool == .life)
        #expect(draw.quick?.context != .computer)
        #expect(draw.medium?.context != .computer)
        #expect(draw.quick?.source == nil)
        #expect(draw.medium?.source == nil)
    }

    @Test("Computer / Work Draw caps at 3 when On Duty and hides all when Off Duty")
    func computerDrawRespectsWorkDutyAndCap() {
        let tasks = TasksState.defaultSeedTasks()

        let onDuty = DrawEngine.computeComputerDraw(
            tasks: tasks,
            workHoursOn: true,
            month: 11,
            season: .fall,
            todayISO: "2026-11-04",
            maxCards: 3
        )
        #expect(onDuty.visible.count == 3)
        #expect(onDuty.visible.allSatisfy { $0.pool == .computerWork })
        #expect(onDuty.suppressedCount == 1)

        let offDuty = DrawEngine.computeComputerDraw(
            tasks: tasks,
            workHoursOn: false,
            month: 11,
            season: .fall,
            todayISO: "2026-11-04",
            maxCards: 3
        )
        #expect(offDuty.visible.isEmpty)
        #expect(offDuty.suppressedCount == 4)
    }

    @Test("Seasonal filter hides Spring tasks in Fall and surfaces them in Spring")
    func seasonalEligibility() {
        let springTask = TasksState.defaultSeedTasks().first { $0.id == "t-4" }!
        #expect(!DrawEngine.isEligible(springTask, month: 11, season: .fall, todayISO: "2026-11-04"))
        #expect(DrawEngine.isEligible(springTask, month: 5, season: .spring, todayISO: "2026-05-04"))
    }

    @Test("TasksStore persists Notes from Yourself and Not Now slot refills across reload")
    @MainActor
    func storePersistenceAndNotNowRefill() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tasks-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = TasksStore(storageURL: tempURL, enableCloudKit: false)
        let firstQuickId = store.state.weeklyDraw.quickId
        #expect(firstQuickId != nil)

        store.addSelfNote(taskId: firstQuickId!, text: "Need to buy citric acid packets first", dateLabel: "Nov 4")
        store.notNowTask(firstQuickId!)

        // Slot refills with another eligible Life task while keeping the skipped task in the pool
        let refilledQuickId = store.state.weeklyDraw.quickId
        #expect(refilledQuickId != firstQuickId)

        let reloaded = TasksStore(storageURL: tempURL, enableCloudKit: false)
        let originalTask = reloaded.state.tasks.first { $0.id == firstQuickId }
        #expect(originalTask?.status == .active)
        #expect(originalTask?.previousNotes.first?.text == "Need to buy citric acid packets first")
    }

    @Test("MCPServerHandler pushes external tasks into Computer pool and completes tasks")
    @MainActor
    func mcpServerEndToEnd() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tasks-mcp-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = TasksStore(storageURL: tempURL, enableCloudKit: false)
        let handler = MCPServerHandler(storageURL: tempURL)

        let addReq = """
        {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"add_task","arguments":{"title":"Investigate flaky test in PR #902","context":"Computer","effort":"Quick","notes":"Check CI logs","source":"Copilot MCP"}}}
        """
        let addResp = try #require(handler.handleLine(addReq))
        #expect(addResp.contains("Investigate flaky test in PR #902"))
        #expect(addResp.contains("Computer / Work"))

        store.reloadFromDiskIfChanged()
        let added = store.state.tasks.first { $0.title == "Investigate flaky test in PR #902" }
        #expect(added != nil)
        #expect(added?.pool == .computerWork)
        #expect(added?.previousNotes.first?.text == "Check CI logs")

        let doneReq = """
        {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"complete_task","arguments":{"query":"PR #902"}}}
        """
        let doneResp = try #require(handler.handleLine(doneReq))
        #expect(doneResp.contains("Completed 'Investigate flaky test in PR #902'"))

        store.reloadFromDiskIfChanged()
        let updated = store.state.tasks.first { $0.id == added?.id }
        #expect(updated?.status == .done)
    }
}
