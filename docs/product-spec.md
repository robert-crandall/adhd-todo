# Product Spec: No-Guilt Task Picker

Nov 3, 2026 · @Robert Crandall

## Overview

This is a native macOS and iPhone app that surfaces one quick and one medium task each week from a pool you maintain, filtered by context, effort and season, and never turns anything into an overdue backlog. It replaces a recurring-task manager that became a source of guilt, and it adds the ADHD-oriented features of Nudge (focus timer, brain dump, task breakdown, hard-day mode and more).

**The problem.** Recurring lists refill forever, show missed items in red, and give every task the same weight. Opening the app means facing everything undone, so the app gets avoided entirely. Today the user tracks zero tasks.

**Goals**

- Complete at least one task per week, sustained over months, starting from zero.
- Never show a count of missed, overdue or skipped items on the home screen.
- Zero decisions in the weekly draw; at most one decision (context and time) in an on-demand draw.
- Add a task in under 10 seconds, including by voice.

**Success measure.** Sustained weekly use over months, completing at least one task per week without overdue guilt or streak tracking.

## Design principles

Every feature must pass one test: does it make opening the app feel safer, or does it add pressure? The rules below follow from that.

1. **Nothing is ever overdue.** A do-by date raises a task's chance of being drawn; it never creates a red or late state.
2. **Skipping is free.** Clicking `Not Now` returns the task to the pool or snoozes it with no count shown, no penalty and no scolding.
3. **No streaks, no resetting scores, no inactivity notifications.** No day dots, streak counters, or weekly scorecards.
4. **The app decides; you can veto.** The default path requires no choices. Every draw can be rerolled or deferred with `Not Now`.
5. **Two pools (Life vs. Work/Computer), hidable tags.** Life tasks (`Outside`, `Errands`, `Anywhere`) and Work/Computer tasks (`Computer` / Weekday Work, including externally pushed GitHub/Gmail/MCP items) live in separate pools so work never crowds out life. Tags power the draw under the hood and can be hidden anytime.
6. **Title-first surface (List View default + Card View toggle).** By default, the homepage shows a minimal **List View**: just the task title plus **`Done`** and **`Not Now`**. Expanding a task (or switching the homepage to **Card View**) reveals your previous notes to yourself, tags, **`Focus Timer`**, and **`Break it down`**.
7. **Returning after a gap shows one small thing,** not a catch-up list.
8. **Calm, plain language.** No exclamation-heavy cheerleading, no guilt phrasing, and gentle handling when a user writes self-critical text.

## Core concepts and data model

Tasks live in two separate pools:
- **Life Pool:** `Outside / house`, `Errands`, and `Anywhere`. Powers the default Weekly Draw.
- **Work / Computer Pool:** `Computer` (which doubles as Weekday Work, including tasks pushed externally from GitHub, Gmail, Copilot, or Claude via MCP).

**Contexts (pick one per task)**

- Outside / house: yard and home chores (Life pool).
- Errands: anything that needs leaving the property (Life pool).
- Anywhere: no particular place (Life pool).
- Computer / Work: weekday work, email/PR follow-ups, and computer tasks (Work/Computer pool).

**Effort sizes (pick one per task)**

- Quick: about 5 minutes or less.
- Medium: about 20 minutes.
- Big: an hour or more, or a weekend.

**Task fields**

| Field | Type | Notes |
| --- | --- | --- |
| Title | text | Required. Voice or typed. |
| Notes (`notes` / `noteHistory`) | text / list | Optional; links, part numbers, and **previous notes from yourself** (for example, what filter size you bought last time or where you left off). |
| Context | one of 4 | Defaults to Anywhere (`Outside`, `Errands`, `Anywhere` = Life Pool; `Computer` = Work Pool). |
| Effort | one of 3 | Defaults to Quick. |
| Estimated minutes | number | Optional; powers focus timer defaults. |
| Season window | start and end month-day | Optional; may wrap the year end (Nov 1 to Feb 28). Outside the window the task is hidden from draws. |
| Event anchor | named toggle | Optional alternative to a window, such as "first frost" or "clocks changed". Task becomes eligible when the user flips the anchor on. |
| Do-by date | date | Optional; raises draw priority as it nears. Never marks the task late. |
| Repeat cooldown | days, weeks or months | Optional; after completion, the task re-enters the pool only after this gap, preserving your previous notes for next time. |
| Snoozed until | date | Optional; hidden from draws until then. |
| One Thing flag | boolean | At most one task at a time. |
| Steps | ordered list | Created by the task breakdown feature or by hand. |
| Last shown, times shown, times completed | metadata | Used by the draw to rotate tasks fairly. |
| Status | active, done, archived | Done non-repeating tasks leave the pool; repeating ones go on cooldown. |

**Pool eligibility.** A task is eligible when it is active, not snoozed, inside its season window or anchor (if it has one), and past its repeat cooldown (if it has one).

## The draw

The app runs two draws from the same pool: a weekly push draw that always surfaces one quick and one medium task, and an on-demand pull draw filtered by what you say you are up for.

**Weekly push draw (default, no input needed)**

1. Build the eligible set (see Core concepts).
2. Deadline override: any task whose do-by date falls within its lead time is forced in first. Lead times: Quick 7 days, Medium 14 days, Big 30 days. If several qualify for one slot, the earliest do-by wins.
3. Fill the quick slot, then the medium slot, by weighted random draw from the remaining eligible tasks of that size. Weight = 1 + (days since the task was last shown / 7), so rarely shown tasks are more likely and nothing repeats back to back.
4. Show the two tasks together, plus the One Thing flag if set. Never show more than three items.
5. A seasonal third slot (Big or Outside tasks in season) is supported by the model but off in the first release.

**On-demand pull draw**

1. Choose a context (Outside, Computer, Errands, Anywhere) and the time you have (5 minutes, 20 minutes, an hour or more, any).
2. Same eligibility and deadline rules, filtered to match.
3. Return up to three options, with a reroll button that replaces the set without any penalty.

**Snooze and skip**

- Snooze offers tomorrow, next week, next season, or a chosen date. The task leaves draws until then.
- Skip returns the task to the pool immediately with its "last shown" updated.
- After a task has been shown and passed over twice, offer a one-time action sheet: Just 5 minutes, Break it down, Next week, or Let it go (archive). No badge, no count.

**Edge cases**

| Situation | Behavior |
| --- | --- |
| Fewer eligible tasks than slots | Show what exists; fill an empty slot with another size only if it still fits the pool. |
| Pool is empty | Show a short invitation to add something, with voice and brain dump buttons. |
| Nothing matches the chosen context and time | Say so plainly and offer to widen the filter. |
| Do-by date has passed | The task stays eligible at top priority, with no red state. If it is more than 14 days past, ask once: still want this, move the date, or let it go. |
| Return after weeks away | Show the normal weekly draw, never a catch-up view. |

## Incoming work: External push via MCP & CLI (Copilot, Claude, GitHub, Gmail)

Instead of turning this app into an email or GitHub client that polls APIs and manages OAuth tokens, external items are **pushed in from outside** through the bundled macOS MCP server, CLI, or Apple Shortcuts, and clear themselves when resolved.

**How external items enter the pool**

- **MCP server & CLI (primary path):** A local stdio/HTTP MCP server (`steady-mcp`) and CLI (`steady`) bundled with the macOS app expose `add_task`, `resolve_task`, `brain_dump`, `get_weekly_draw`, `complete_task`, and `snooze_task`.
- **Copilot & Claude:** During any coding or triage session, Copilot or Claude can push a follow-up task directly (`add_task`) or close it when done (`resolve_task` by `externalId`).
- **GitHub & Gmail (pushed externally, not polled in-app):** External scripts, `gh` CLI hooks, Apple Shortcuts, or a lightweight external automation push actionable GitHub PRs/issues or starred Gmail threads into `steady-mcp` / `steady add --source github --external-id owner/repo#123`. When the PR merges or thread is archived, the external hook calls `resolve_task` so it disappears quietly without overdue debt.

**How incoming items behave**

| Rule | Behavior |
| --- | --- |
| Context and effort | Context is Computer. Effort is guessed by item type (review request: Medium; reply to an email or mention: Quick; failing checks: Medium) and editable; per-type defaults can be changed. |
| Source fields | Source (`GitHub`, `Gmail`, `Copilot MCP`, or `Claude MCP`), an external ID, a deep link, sender or repository, and arrival time. Tapping opens the pull request, issue, email thread, or session context directly. |
| De-duplication | One task per pull request, issue or email thread. Later activity updates the existing task instead of creating another. |
| Auto-resolve | When the pull request is merged or closed, your review is submitted, the issue is closed, or the thread is replied to, archived or loses its label, the task completes quietly as "resolved elsewhere". |
| Optional urgency | A per-source rule can set a do-by date relative to arrival (for example, review requests: 3 days). It raises priority only, like any do-by date. |
| Volume cap | At most a set number of new incoming items per day (proposed: 5) enter individually. Any extras roll into one Quick task, "Triage N new notifications". |
| Work hours | Incoming items surface only during chosen work hours, and an Off duty switch hides the stream entirely without losing anything. |

**How they surface**

Life tasks (`Outside`, `Errands`, `Anywhere`) and Work/Computer tasks (`Computer`) are separate pools. GitHub, Gmail, and MCP work tasks land directly in the **Computer / Work pool** (`context: Computer`). You can view your **Life Draw** or your **Work / Computer Draw** cleanly from the sidebar or pool switcher without stacking both on the same screen.

## Key screens and flows

The home screen defaults to a minimal **List View** (task title + `Done` / `Not Now`); expanding a row or switching to **Card View** shows previous notes from yourself, tags, `Focus Timer`, and `Break it down`.

| Screen | Purpose | Key elements |
| --- | --- | --- |
| Home (Life Draw) | This week's quick and medium life task, plus One Thing | **List View** (default: title + `Done` / `Not Now`, click to expand) or **Card View** (at-a-glance notes, steps, `Focus Timer`, `Break it down`); `Hide Tags` toggle |
| Work / Computer Draw | Active draw from the Computer / Work pool (including GitHub/Gmail/MCP pushes) | Same **List View** / **Card View** toggle; `Done` and `Not Now` on the surface; `Off Duty` switch |
| Pull (`I Have Time`) | On-demand draw | Context chips, time chips, up to 3 results, reroll |
| Pool | Browse and edit Life or Work/Computer pools | Pool switcher (Life vs. Work/Computer), filters by context/effort/season, seasonal event anchors |
| Add task | Fast capture | Title field, voice button, optional chips for context and effort, optional season and do-by |
| Brain dump | Turn messy text or speech into tasks | Free-text or voice box; proposed tasks shown for review with context and effort pre-filled |
| Task detail / Expanded view | View previous notes & start tools | Previous notes from yourself (plus add note), `Focus Timer`, `Break it down` (Copilot SDK), steps checklist |
| Settings | Notifications and preferences | Draw day and time, default view (`List` vs `Card`), `Hide Tags` default, quiet hours, anchors, sound, appearance |

**Flow: the weekly draw**

1. A notification arrives on the chosen day and time.
2. Tapping it opens Home with the two tasks.
3. The user taps Done, Snooze, Reroll or Start timer. Closing the app without acting changes nothing.

**Flow: "I'm outside with 30 minutes"**

1. Open Pull, tap Outside and 20 minutes.
2. See up to three matching tasks, reroll if none appeal.
3. Start one; the timer and steps appear.

**Flow: capture while thinking of something**

1. Widget or action button opens Add task with the microphone ready.
2. Say the task; it is saved with defaults.
3. Optionally refine context and effort later from the Pool.

**Flow: a hard day**

1. The user taps Hard Day, or accepts the app's suggestion.
2. The app shows one task, with a 2-minute timer, and nothing else.

## Features

The first release centers on the pool and the draw; the Nudge-inspired ADHD features come in on top. Phases are defined in the roadmap.

**Core (this app's own)**

| Feature | What it does | Phase |
| --- | --- | --- |
| Task pool | One list of tasks with context, effort, notes | 1 |
| Weekly push draw | One quick and one medium task, chosen for you | 1 |
| On-demand pull draw | Filter by context and time, up to three results, reroll | 1 |
| Snooze and skip | Free, no count, returns to the pool | 1 |
| Season windows | Tasks appear only in their window | 1 |
| Event anchors | Seasonal tasks triggered by an event you flip on | 2 |
| Do-by dates | Raise draw priority, never mark late | 1 |
| Repeat cooldowns | Task returns a set time after completion | 1 |
| Seasonal third slot | A weekly in-season Big or Outside suggestion | 2 |
| Todoist import | CSV import of existing tasks, with auto-guessed context and effort for review | 2 |
| Local MCP server (Copilot & Claude) | Bundled macOS MCP server (`add_task`, `brain_dump`, `get_weekly_draw`, `complete_task`) so Copilot and Claude can capture and manage tasks directly into the SwiftData/CloudKit pool | 1 |

**Task-start and focus features (inspired by Nudge)**

| Feature | What it does | Phase |
| --- | --- | --- |
| One Thing flag | One task marked as today's single priority | 1 |
| Hard Day mode | One task at a time, 2-minute timer, lowest barrier | 1 |
| Skipped-task action sheet | Just 5 minutes, break it down, next week, or let it go | 1 |
| Focus timer | Chosen durations, countdown, 5-minute and 1-minute warnings with haptics (shown inside expanded task / Card View) | 1 |
| Home List & Card views | Default **List View** shows only task titles + `Done` / `Not Now`; expanding a row or toggling **Card View** shows previous notes from yourself, `Focus Timer`, `Break it down`, and optional tags | 1 |
| Hideable tags (Clean Surface) | One-tap toggle to hide context, effort, season, and source chips in Card View and Pool | 1 |
| Home screen & desktop widgets | Shows this week's draw with Done and Not Now buttons on iOS Home Screen and macOS Notification Center / Desktop, plus a macOS menu bar extra | 1 |
| Per-task reminders | Optional reminder and a 10-minute pre-task heads-up | 2 |
| Quick note during focus | Capture a stray thought or leave a note for your future self without leaving the timer | 1 |
| Ambient sound | White and brown noise, plus rain and lo-fi; stops with the timer | 2 |
| Live Activity | Timer on the lock screen | 2 |

**AI-assisted features (powered by GitHub Copilot SDK; macOS first, iPhone later)**

All AI features run through the **GitHub Copilot SDK** on macOS first (reusing your existing authenticated Copilot setup with zero extra API keys or per-token billing friction). Any structured outputs (extracted tasks from Brain Dump, 3-5 step breakdowns, context/effort tags) sync immediately to iPhone over SwiftData + CloudKit; direct iPhone invocation can follow later.

| Feature | What it does | Phase |
| --- | --- | --- |
| Brain dump (Copilot SDK) | Paste or speak messy thoughts on Mac (or via MCP); Copilot SDK proposes structured tasks with context and effort filled in, to review | 2 |
| Task breakdown (Copilot SDK) | Uses Copilot SDK to turn a vague task into 3 to 5 concrete steps of 5 to 15 minutes each | 2 |
| AI suggestion (Copilot SDK) | Suggests one task for right now, from the pool only | 2 |
| Up-next suggestion (Copilot SDK) | After finishing a session, offers one follow-up | 2 |
| Gentle language handling | Detects self-critical or crisis language in free text; suggests Hard Day mode, and shows region-appropriate crisis resources (such as 988 in the US) when needed | 2 |

**Community (optional later phase)**

| Feature | What it does | Phase |
| --- | --- | --- |
| Body doubling rooms | Quiet shared rooms showing who is working, no video or audio; needs accounts, a backend and moderation | 3 |

**Appearance:** dark mode and light mode from day one; Dynamic Type; VoiceOver labels on all controls.

## Notifications

The app sends only notifications the user has asked for, and never one about something missed. All are local notifications, so they work offline and need no account.

| Notification | Default | Notes |
| --- | --- | --- |
| Weekly draw | On, Saturday morning | Day and time configurable; tapping opens Home |
| Morning reminder | Off | Optional; opens the One Thing picker |
| Extra daily reminders | Off | Up to two, at chosen times |
| Per-task reminder | Off | Set on a specific task and day |
| 10-minute pre-task heads-up | Off | For tasks with a scheduled time in Day view |
| Habit reminders | On per habit | Time chosen per habit; survive reinstall via sync |
| Focus timer warnings | On | 5-minute and 1-minute banners with haptics |

**Never sent:** overdue or missed-task alerts, inactivity nudges, streak warnings, or badge counts of any kind. Quiet hours are respected for everything except the focus timer the user started.

## Seasonal tasks and deadlines

Seasonal tasks are ordinary tasks with a window, so there are no separate seasonal lists to maintain. Outside the window a task is invisible; inside it, the task competes in draws like any other.

- **Windows** are month-day ranges and may wrap the new year. Example: clean gutters, Oct 1 to Nov 30.
- **Event anchors** cover tasks tied to something that happens, not a date. The user defines a named anchor such as "first frost" or "clocks changed" and flips it on when it happens, and flips it off when the season ends. A task can have a window, an anchor, both (anchor must be on and inside the window), or neither.
- **Do-by dates** make a task more likely to be drawn as the date nears, using the lead times in the draw rules (7, 14 and 30 days by effort). The date only increases priority; it never creates a late state.
- **Passed dates** are handled kindly: the task stays eligible and is asked about once after 14 days.
- **Starter packs** (phase 3, optional) offer editable sets of fall, winter, spring and summer home tasks to seed the pool.

In the first release, seasonal tasks flow through the same weekly quick and medium slots by effort size. The seasonal third slot is added in phase 2.

## macOS & iOS technical notes

A local-first universal SwiftUI app (macOS 14+ and iOS 17+) with iCloud sync covers phase 1 with no server of your own; the incoming work feature in phase 2 adds a small service. These are starting recommendations to confirm during the build.

| Area | Recommendation |
| --- | --- |
| UI | Universal SwiftUI (`NavigationSplitView` + `MenuBarExtra` on macOS; `TabView` + sheets on iPhone) |
| Storage and sync | SwiftData with CloudKit sync, so tasks, draws, and focus state follow the user between Mac and iPhone without accounts |
| Draw logic | A pure Swift module with no UI dependencies, unit tested with seeded randomness |
| Notifications | Local notifications through UserNotifications; reschedule on settings change and on app launch |
| Widgets & Menu Bar | WidgetKit with interactive buttons through App Intents (Done, Snooze) for iOS Home Screen and macOS Desktop; `MenuBarExtra` on macOS showing active timer or One Thing |
| Quick capture | Global hotkey (`⌘⇧Space`) quick-entry panel on macOS; local **MCP server** for adding tasks directly from GitHub Copilot and Claude; App Intents for Siri, Shortcuts and the iPhone Action button; dictation through system speech APIs |
| Focus timer | Timer plus Live Activity on iPhone and floating/menu-bar timer on macOS; haptics on iPhone; audio session for ambient sounds |
| AI features (Copilot SDK) | Powered by the **GitHub Copilot SDK** on macOS first (Brain Dump, Task Breakdown, right-now suggestions, gentle language handling); generated steps and tasks sync to iPhone via CloudKit, with direct iPhone AI support added later |
| Privacy | Task content stays on device and in the user's iCloud; no analytics on task text; AI calls disclose what is sent |
| Body doubling (phase 3) | Needs a backend, accounts, presence handling and moderation; treat as a separate project |

**Testing.** Unit-test the draw (eligibility, deadline override, rotation, edge cases) heavily; it is the heart of the app. Add a debug screen that shows why each task was or was not eligible.

## Non-goals

- Team or shared tasks, assignments, or household collaboration.
- Calendar integration, and any attempt to be a full email or GitHub client; incoming work is captured as tasks that link out.
- Projects, nested hierarchies or Gantt-style planning beyond a task's own steps.
- Streaks, points, badges, leaderboards or any score that resets.
- Time tracking or billing.
- Android or web versions.
- Budgeting or finance features; a budget check is just another recurring task in the pool.

## Roadmap

Build in three phases, each ending with a real-use gate so the app earns its next feature by being used.

**Phase 1: Core pool, draw, and MCP capture.** Task pool with context and effort, add by typing, voice, or the local macOS **MCP server** (from Copilot and Claude), weekly push draw, pull draw, snooze and skip, season windows, do-by dates, repeat cooldowns, One Thing, Hard Day mode, skipped-task action sheet, focus timer, widget, local notifications, dark mode.

- *Gate:* you use it yourself for four weeks in a row and complete at least one task each week.

**Phase 2: ADHD support layer (Copilot SDK on macOS first).** Brain dump, task breakdown, AI suggestions and up-next, and gentle language handling via the **GitHub Copilot SDK** on macOS (syncing results to iPhone via CloudKit, with iPhone-native triggers later), plus habits, Hours view and Day view, per-task reminders, quick note, ambient sound, Live Activity, week in review, event anchors, seasonal third slot, Todoist import, incoming work from GitHub and Gmail (GitHub first).

- *Gate:* the AI features are used at least weekly, and the language-handling behavior has been reviewed against a set of test phrases.

**Phase 3: Community and polish.** Body doubling rooms (backend, accounts, moderation), starter packs of seasonal tasks, any App Store launch work such as onboarding, screenshots, privacy labels and pricing.

- *Gate:* decide whether to ship publicly or keep it personal.

## Open questions

- [ ] Name for the app.
- [ ] Personal tool or App Store product? This decides pricing, onboarding and body doubling.
- [ ] If shipped, what is free versus paid (Nudge keeps its core free and limits AI use)?
- [ ] When bringing Copilot SDK AI features to iPhone later, route through a personal thin proxy or keep AI generation on macOS + CloudKit sync?
- [ ] Default weekly draw day and time (proposed: Saturday morning).
- [ ] Should the weekly draw ever add a third, in-season task before phase 2?
- [ ] Should a passed do-by date ever prompt more than once?
- [ ] Which contexts are missing from the four proposed (for example Garage, Phone calls)?
- [ ] Does the Hard Day suggestion trigger only from language in free text, or also from skipped draws?
- [ ] Is body doubling worth building, or is a shared-presence feature enough?
