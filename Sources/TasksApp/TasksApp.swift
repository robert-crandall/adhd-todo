import Combine
import SwiftUI
import TasksCore

@main
struct TasksMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TasksStore()
    @State private var selectedSection: SidebarSection = .lifeDraw
    @State private var showingQuickCapture = false

    var body: some Scene {
        WindowGroup("Tasks") {
            MainTasksWindow(
                store: store,
                selectedSection: $selectedSection,
                showingQuickCapture: $showingQuickCapture
            )
            .frame(minWidth: 920, minHeight: 620)
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    store.refreshFromCloud()
                }
            }
        }
        .commands {
            CommandMenu("Tasks") {
                Button("Quick Capture…") {
                    showingQuickCapture = true
                }
                .keyboardShortcut("n", modifiers: [.command])

                Divider()

                Button("Reroll Life Draw") {
                    store.rerollLifeDraw()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(store.state.hideTags ? "Show Tags" : "Hide Tags (Clean Surface)") {
                    store.toggleHideTags()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button(store.state.hardDayMode ? "Exit Hard Day Mode" : "Pick One Thing for Me (Hard Day)") {
                    store.toggleHardDayMode()
                    if store.state.hardDayMode {
                        selectedSection = .lifeDraw
                    }
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarPopoverView(store: store, showingQuickCapture: $showingQuickCapture)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.activeTimerTaskId != nil ? "timer" : "flame.fill")
                if store.activeTimerTaskId != nil {
                    Text(formatSeconds(store.timerRemainingSeconds))
                        .monospacedDigit()
                } else {
                    Text("Tasks")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

public func formatSeconds(_ total: Int) -> String {
    let mins = max(0, total) / 60
    let secs = max(0, total) % 60
    return String(format: "%02d:%02d", mins, secs)
}
