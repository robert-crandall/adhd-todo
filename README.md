# Tasks — No-Guilt ADHD Task Picker (macOS & MCP)

**Tasks** is a native Swift / SwiftUI ADHD-friendly task dealer designed around executive-function ergonomics:

- **Two Separate Pools (`Life` vs. `Computer / Work`):**
  - **Life Draw (`Life Pool`):** `Outside`, `Errands`, and `Anywhere` personal tasks. Deals **2 cards per week** (1 `Quick` ~5m + 1 `Medium` ~20m).
  - **Computer / Work (`Computer Pool`):** Holds `Computer` tasks plus externally pushed **GitHub**, **Gmail**, **Copilot CLI**, and **Claude Desktop** MCP tasks (capped at `<= 3` active cards, with a 1-click **On Duty / Off Duty** toggle).
- **Calm Homepage (`List` / `Cards` / `Zen Deck`):**
  - **List View (Default):** Shows only the task title plus **`Done`** and **`Not Now`**.
  - **Expand on Click / Card View:** Reveals **Notes from Yourself** (timestamped notes from previous rolls + an inline input to leave a note for future-you), **`Focus Timer`**, **`Break it down`** (powered by **GitHub Copilot SDK** with offline fallback; set `TASKS_USE_LIVE_COPILOT_CLI=1` to invoke the live `copilot` CLI), and hidable tags.
  - **Zen Deck:** Single-card focus view (`1 of N`) when even a 2-item list feels like too much.
- **Shared Storage and Sync Library (`TasksCore`):**
  - Used by the macOS app and `tasks-mcp`, with App Group storage (`7492ZAHAJV.group.org.robertcrandall.Tasks`) and CloudKit integration (`iCloud.org.robertcrandall.Tasks`). `TasksCore` also compiles for iOS and watchOS so companion app targets can share the same persistence and draw engine.

## Build & Sign `Tasks.app` (Team `7492ZAHAJV`)

```bash
bash scripts/build-app.sh
cp -R dist/Tasks.app /Applications/Tasks.app
open /Applications/Tasks.app
```

## Run Tests

```bash
swift test
```

## Local MCP Server (`tasks-mcp`) for Copilot CLI & Claude Desktop

Add to `~/.copilot/mcp-config.json` or `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "tasks": {
      "command": "/Applications/Tasks.app/Contents/MacOS/tasks-mcp",
      "args": []
    }
  }
}
```

### Exposed MCP Tools
- `add_task`: Push a task into `Computer / Work` or `Life` pool (instantly updates `Tasks.app` via Darwin IPC).
- `list_drawn_tasks`: Read the active Life Draw and Computer / Work draw.
- `complete_task`: Mark a task Done by ID or title substring.
- `add_self_note`: Leave a timestamped "Note from Yourself" on a task.
- `brain_dump`: Parse unstructured text into tasks across Life and Computer pools.
