# Cardinal — Feature Alignment Document

**One-liner:** A Kanban board where columns change what a card *is*. Cards start as passive
ideas, become active AI workers when dragged into an execution column, and become reviewable
artifacts when the work is done. The board is not a task tracker — it is a control surface
for a team of AI agents.

**Status:** Draft for alignment. Nothing here is committed; the point is to agree on the
model before writing code.

---

## 1. Core insight: columns are policies, not labels

In a normal Kanban board a column is a label. In Cardinal a column is a **policy object**
that answers three questions:

1. **Who services cards here?** (nobody / a shared planning assistant / a dedicated per-card agent)
2. **What happens on entry?** (nothing / open a discussion / spawn an agent and start a run)
3. **What is allowed here?** (chat only / read-only research / real actions with tool access)

This is the single most important modeling decision. It means:

- Board behavior is **data, not code**. Users can eventually add a second execution column
  ("Research" with read-only tools, "Build" with write tools) without new application logic.
- Moving a card is a **transition event** with well-defined semantics: leave-policy of the old
  column runs (e.g., pause/detach the agent), enter-policy of the new column runs (e.g., spawn
  agent, start run).
- The UI can render affordances directly from the policy ("dragging here will start an agent
  with these permissions") instead of hardcoding column names.

Suggested column archetypes (a column has exactly one):

| Archetype   | Serviced by            | On card entry                          |
|-------------|------------------------|----------------------------------------|
| `inbox`     | nobody                 | nothing — parking lot                  |
| `planning`  | shared board assistant | assistant joins the card's conversation |
| `execution` | dedicated card agent   | spawn agent, start a Run               |
| `review`    | human                  | agent stops; card presents outputs for verdict |
| `terminal`  | nobody                 | archive/lock the conversation          |

The default board ships as: **Ideas (inbox) → Planning (planning) → In Progress (execution)
→ Review (review) → Done (terminal)**.

**Every column gets a gear icon** that opens a settings modal — this is the entire admin
surface for the policy object: column name, archetype, instructions (a system-prompt
addendum given to any agent servicing cards in this column), model choice, WIP/concurrency
limit, tool permissions, plan-approval toggle, budgets, and entry/exit automations. Adding
a column is just creating a new policy; there is nothing special about the five defaults.
(See §14 for the modal layout.)

---

## 2. Domain model

```
Board  (repo_url, default_branch — a board is bound to one git repo; see §13)
 ├── Columns (ordered; each has an archetype + policy: agent config, tool
 │            permissions, WIP limit, auto-transition rules — edited via gear modal)
 └── Cards
      ├── belongs_to :column  (position within column for ordering)
      ├── branch_name, pr_url, pr_state  (each card is its own branch + PR; see §13)
      ├── tags, description  (freeform metadata; more fields later)
      ├── Conversation (exactly one, permanent — survives all column moves)
      │     └── Events (append-only timeline; see §7)
      ├── AgentSessions (0..n; one per visit to an execution column)
      │     ├── workspace: a cage-style throwaway Docker container (repo mounted,
      │     │              card branch checked out; see §13)
      │     └── Runs (1..n per session; one per "go do work" invocation)
      │           ├── Events (written into the card's single timeline, tagged with run_id)
      │           └── Artifacts (files, diffs, links, documents — the outputs)
      └── status (cached state machine value, denormalized for board rendering)
```

Key relationships and rules:

- **Card : Conversation is 1:1 and permanent.** The conversation is the card's memory. The
  planning assistant writes into it, the execution agent reads it as briefing context and
  writes into it, the human writes into it at every stage. Nothing is ever in a side channel.
- **AgentSession** is the identity of "this card's dedicated AI." It owns the agent's
  working state (working directory / sandbox handle, model config, accumulated context
  pointer). A card dragged back into execution after revisions gets a *new* Run under the
  same session if the session is resumable, or a new session if not.
- **Run** is one bounded attempt: started → (streaming events) → finished with a result
  (`succeeded | failed | cancelled | needs_input`). Runs are the unit of retry, cost
  accounting, and audit. Never mutate a run's events; append.
- **Artifact** is a first-class output record (file, patch, URL, rendered document) attached
  to a run. Review columns render artifacts, not raw chat logs.
- **Event** is the single append-only log entry type (see §7). Everything the user sees in a
  card — human messages, agent messages, status changes, tool calls, questions, column moves —
  is an event. One table, one ordering, one rendering pipeline.

---

## 3. Card lifecycle

The card has one state machine; column archetype constrains which states are legal.

```
 draft ──► discussing ──► queued ──► working ──┬──► needs_input ──► working
   ▲            ▲                      │        │
   │            │                      │        ├──► blocked (external dependency)
   │            │                      │        │
   │            └──── revising ◄───┐   │        └──► failed ──► (retry ⇒ queued)
   │                               │   ▼
   └── (any) ◄── archived      changes_requested ◄── in_review ◄── work_complete
                                                        │
                                                        └──► approved ──► done
```

Rules of thumb:

- **Column move is the trigger; state machine is the truth.** Dragging a card into
  In Progress sets `queued`; the runner picks it up and sets `working`. Dragging out of an
  execution column mid-run prompts: *cancel the run* or *let it finish in place* (card
  refuses to move until the user picks — no silent kills).
- **The agent finishes, the human moves the card — by default.** When a run succeeds the
  card goes to `work_complete` and visually signals "ready for review," but auto-advancing
  to the Review column is a per-column policy toggle (off in MVP). Physical card motion the
  user didn't cause is disorienting; do it only when explicitly enabled.
- **`needs_input` is a first-class state, not a failure.** Agents will constantly need
  clarification. The run parks, the card shows a prominent "waiting on you" badge, the
  question is the newest event. Answering resumes the same run.
- **Rejection is a loop, not a dead end.** In Review, "request changes" adds a human event
  describing what's wrong and sets `changes_requested`; dragging back to In Progress starts
  a new run whose briefing includes the rejection feedback.

---

## 4. What happens when a card enters an execution column

Ordered, and each step is observable in the card's timeline:

1. **Snapshot the briefing.** Compile card title + description + the planning conversation
   + any prior run summaries + rejection feedback into a structured brief. Store it on the
   Run (immutable). This is what the agent actually receives — the user can inspect it.
2. **Pre-flight gate.** If the column policy requires it (default: yes), the card enters
   `queued` and shows a **plan-of-attack confirmation**: the agent's first action is to post
   a short "here is what I intend to do" event and wait for a 👍. One click to approve, or
   reply to redirect. (Toggleable per column for trusted/low-stakes work.)
3. **Provision the session.** Create/resume the AgentSession: sandbox or working directory,
   tool permissions from column policy, budget caps.
4. **Start the Run.** Enqueue a job; the runner drives the agent loop. Every agent message,
   tool call, and status change streams into the card as events in real time.
5. **Terminate deliberately.** The run ends in exactly one of: `succeeded` (agent posted a
   **final report event** + artifacts), `needs_input`, `failed` (error + last-known state),
   or `cancelled`. There is no "the agent just stopped talking" state — the runner enforces
   a final event.

---

## 5. Shared column agent vs. dedicated card agent

Two genuinely different constructs — don't unify them into one "agent" abstraction:

|                        | Planning assistant (column-level)         | Worker agent (card-level)              |
|------------------------|-------------------------------------------|----------------------------------------|
| Cardinality            | One per board                              | One per card (AgentSession)             |
| Lifetime               | Always available, stateless between cards  | Created on column entry, bounded by runs |
| Context                | The one card's conversation it's invoked in | Full briefing + working state + tools   |
| Tools                  | None (chat only) — maybe read-only board ops | Real tools per column policy           |
| Invocation             | Reactive: responds when the user writes    | Proactive: works autonomously until done |
| Cost profile           | Cheap, fast model                          | Expensive, capable model                |

Implementation consequence: the planning assistant is a plain synchronous-ish chat completion
against the card's conversation (a small job per message). The worker agent is a long-running
agentic loop with tool use, checkpointing, and streaming. Different code paths, same Event
timeline.

The planning assistant's most valuable output is a **crisp brief**: it should actively drive
toward "acceptance criteria are clear, scope is bounded" and can offer a *"Ready for
execution"* summary event that becomes the top of the briefing when the card moves.

---

## 6. UI: making state legible at a glance

The board must answer "who needs me?" in one glance. Card states map to a fixed visual
vocabulary (color + icon + animation), consistent everywhere:

| State               | Treatment                                                        |
|---------------------|------------------------------------------------------------------|
| `draft`             | Plain, muted                                                     |
| `discussing`        | Chat glyph; subtle highlight when assistant has replied unread    |
| `queued`            | Clock glyph, dimmed pulse                                        |
| `working`           | **Animated indicator (breathing border / spinner) + live one-line status** ("running tests…") sourced from the latest progress event |
| `needs_input`       | **Loud.** Amber, question-mark badge, card floats to top of column, board-level attention counter increments |
| `blocked`           | Red-amber, "blocked: <reason>" chip                              |
| `failed`            | Red, error chip, one-click "view failure / retry"                |
| `work_complete`     | Green check, "ready for review" chip                             |
| `in_review`         | Eye glyph                                                        |
| `changes_requested` | Amber-red loop glyph                                             |
| `done` / `archived` | Muted, checkmark                                                 |

Board-level chrome:

- **Attention inbox** (header): a single ordered list of every card that is waiting on the
  human (`needs_input`, `failed`, `work_complete`). This is the primary navigation surface
  once >3 agents run concurrently — the board becomes the map, the inbox becomes the queue.
- **Activity ticker** per execution column: "3 running · 1 waiting on you · 2 queued".
- Cards in `working` state show their **latest progress line directly on the card face** —
  the user should never have to open a card to know roughly what it's doing.

Card detail view is a two-pane layout: **timeline** (the conversation/log, §7) and a
**work panel** (current run status, plan, artifacts, controls: pause / cancel / retry /
approve plan / answer question).

---

## 7. The card timeline: one log, typed events, aggressive collapsing

Single append-only stream of typed events. One table, polymorphic-ish `kind` + JSON payload:

```
Event(card_id, run_id?, kind, actor, payload, created_at)

kinds:
  user_message        agent_message        assistant_message   (planning)
  status_change       column_move          plan_proposed       plan_approved
  question            answer               progress            (one-liners)
  tool_call           tool_result          artifact_created
  run_started         run_finished         final_report        error
```

Rendering rules (this is what keeps the card readable):

- **Three zoom levels.** *Conversation view* (default): messages, questions, plans, final
  reports, artifacts — the stuff a human should read. *Activity view*: + progress lines and
  tool-call summaries, collapsed into expandable groups ("ran 14 commands ▸"). *Debug view*:
  everything raw, including full tool payloads.
- **Runs are visually bracketed** — a run header/footer frames its events, so a card with
  three attempts reads as three chapters, each ending in a final report or failure.
- **The final report is a first-class artifact**, not the last chat message: what was done,
  what changed, what to check, open questions. Review UX is built on final reports +
  artifacts; the timeline is the supporting evidence.
- Human messages are never collapsed. Agent chatter is always collapsible.

---

## 8. Keeping N concurrent agents from becoming chaos

Chaos control is mostly *throughput control* + *attention control*:

1. **WIP limits are load-bearing.** Execution columns get a hard concurrent-run limit
   (default 3). Cards beyond it queue in-column (`queued`, visibly ordered). This is both a
   UX guardrail and the natural backpressure for the job system.
2. **One global run queue, per-board concurrency.** The runner respects board + column
   limits. Priority = column position (top of column runs first) so the user reorders the
   queue by dragging — no separate priority UI.
3. **Attention inbox** (§6) serializes human interrupts. Agents park in `needs_input`
   indefinitely without burning tokens.
4. **Budgets:** per-run token/cost cap and wall-clock timeout (column policy). Hitting a cap
   → `needs_input` with "I've used my budget, here's where I am — continue?" Never silent
   death, never runaway spend.
5. **Isolation by default.** Each AgentSession gets its own sandbox/workspace. Two agents
   never share mutable state in MVP. Cross-card dependencies ("blocked by card X") are a
   later feature — model as an explicit edge, not shared state.
6. **Notifications are batched and quiet** except `needs_input` and `failed`, which are
   immediate.

---

## 9. Permissions, controls, and safety rails

Layered, all enforced server-side in the runner (never trust the agent's self-restraint):

1. **Column tool policy** — the permission boundary the user reasons about. Each execution
   column declares allowed tool classes: read-only research / file & workspace writes /
   network / external side-effects (email, deploy, purchases). MVP ships read+write
   workspace tools, nothing externally irreversible.
2. **Plan approval gate** (§4) — default on. The user sees intent before action.
3. **Action-level approval for flagged tools.** Any tool marked `requires_approval` in the
   column policy pauses the run into `needs_input` with a concrete "may I run X?" event.
   Approvals can be remembered per-card ("allow `git push` for this card").
4. **Budgets and timeouts** (§8) as hard caps.
5. **Kill switches at every level:** pause/cancel a run, a card, a column ("pause all"), or
   the board. Cancel is graceful (agent gets a moment to checkpoint + post a wrap-up event)
   with a hard-kill fallback.
6. **Full audit trail for free:** the event log *is* the audit log — every tool call and
   result is an event tied to a run and an actor.
7. **Sandboxing:** every agent workspace is a **cage-style throwaway Docker container** —
   the repo checked out inside, the card's branch active, host isolated, destroyed after
   the session. The only thing that leaves the container is what gets pushed to the card's
   branch. Secrets injected per-column policy, never stored in conversation context.

---

## 10. MVP scope

**In:**

- One board bound to one git repo, defaulting to five columns (Ideas / Planning /
  In Progress / Review / Done). Columns are addable/editable via the gear-icon settings
  modal (§14) — the policy model is user-facing from day one.
- Cards: create, edit, tag, drag between columns, manual ordering. Each card gets its own
  branch and PR (§13).
- Planning assistant: chat in the card in the Planning column; produces a "ready for
  execution" brief.
- Execution: dedicated agent per card in a cage-style container, real runs with streaming
  events, plan-approval gate, `needs_input` round-trips, final report + artifacts. **MVP
  domain is coding against the board's git repo** (decided — see §15): work is committed
  to the card's branch and surfaced as a PR.
- Card timeline with conversation/activity zoom levels.
- States + full visual vocabulary; attention inbox in the header.
- Concurrency limit (global, e.g. 3), per-run token budget + timeout, cancel/retry.
- Single user, no auth beyond a login, no billing.

**Explicitly out (post-MVP):**

- Custom boards/columns UI, multiple boards, multi-user/roles, cross-card dependencies,
  agent-to-agent communication, auto-advancing cards, scheduled/recurring cards, external
  side-effect tools (email/deploy), mobile.

**MVP demo script (the bar for "done"):** create a card → refine it with the planning
assistant → drag to In Progress → approve the agent's plan → watch live progress on the
card face → answer one clarifying question → get a final report with a diff artifact →
drag to Review → request a change → drag back → second run fixes it → approve → Done.

---

## 11. Technical architecture (Rails + JS)

### Shape

```
Browser (Hotwire: Turbo Streams + Stimulus; board DnD via SortableJS)
   │  websocket (ActionCable / SolidCable)
Rails app ── Postgres (system of record: boards, columns, cards, events, runs…)
   │
Job backend (SolidQueue or Sidekiq) ── RunnerJob per Run
   │
Agent runtime: Claude Agent SDK subprocess per run (or raw Anthropic API loop)
   └── sandboxed workspace per AgentSession (Docker container or scoped dir)
```

### Frontend: Hotwire first

The UI is fundamentally "server state streamed to the client": cards changing status,
events appending to timelines. Turbo Streams over ActionCable does exactly this with almost
no client state management — `broadcast_append_to card` for events, `broadcast_replace_to
board` for card face updates. Stimulus + SortableJS covers drag-and-drop (POST the move,
server validates the transition, broadcasts the result). Reach for React only if the board
interaction gets genuinely app-like later; don't start there.

### Backend pieces

- **Models:** `Board, Column, Card, Event, AgentSession, Run, Artifact` per §2. Card state
  machine via a small hand-rolled `state` enum + transition methods (AASM optional). Column
  policy as a JSON column on `columns` (schema-validated), archetypes as an enum.
- **Transitions:** a `CardTransition` service object is the only code path that moves cards
  between columns — validates legality, runs leave/enter policies, emits `column_move` and
  `status_change` events, enqueues runs. Controllers and (later) automations all call it.
- **Runner:** `Run` row is the source of truth; `RunnerJob` (one per run) drives the agent,
  translating agent output into Events as it streams. Heartbeat column on `runs` +
  a sweeper job to catch dead runners → mark run `failed` honestly. Concurrency limits
  enforced at dequeue time (count running runs per board/column before starting).
- **Agent runtime (decided):** the Claude **Agent SDK** run as a supervised subprocess
  *inside the card's cage container*; it gives tool-use loops, streaming, and permission
  hooks out of the box. The Rails runner only *supervises* — provision container, spawn,
  stream-parse output into Events, enforce budgets, kill, tear down. The container boundary
  doubles as the sandbox: Rails talks to it over the Docker API / exec stream, and the
  agent's only exit path for work is `git push` to the card branch.
- **Approvals/interrupts:** run parks by setting `needs_input` and *exiting the job*
  (persist a resume token / session id); answering enqueues a resume job. Don't hold a job
  thread open waiting on a human.
- **Planning assistant:** a plain `AssistantReplyJob` per user message in planning columns —
  one Messages API call with the card conversation, append the reply event. No session, no
  tools. Cheap model.
- **Streaming UX:** Events written to Postgres → Turbo Stream broadcasts on the card and
  board channels. For token-by-token agent text, buffer and flush progress events every
  ~1–2s rather than streaming raw tokens through the DB; per-token streaming is post-MVP
  polish, not architecture.

### Why this holds up

Postgres as the single system of record (events included) keeps MVP ops trivial — no Redis
required if SolidQueue/SolidCable are used. The event table will grow; it's append-only and
easily partitioned/archived later. The runner/SDK boundary means the "AI part" is swappable
without touching the product model.

---

## 12. Open questions to align on

(Resolved questions move to the decision log, §15.)

All current open questions concern the portable-instance direction (§16):

1. **Adopt §16 at all?** It reshapes deployment (engine + per-repo instances) but barely
   touches the domain model. Recommendation: yes, and soon — it's cheap now, expensive later.
2. **SQLite vs Postgres.** If Cardinal spins up per-repo like cage, a per-instance SQLite
   file (gitignored inside `.cardinal/`) removes the Postgres service dependency entirely;
   Rails 8's Solid* stack is SQLite-first. Recommendation: switch now, before more schema
   accumulates.
3. **Commit policy for `.cardinal/` files.** Every drag = a file change; auto-committing
   would spam history. Recommendation: Cardinal writes the files but never commits them —
   they ride along in the user's normal commits; optional auto-commit-on-card-completion
   later.
4. **What lives in the card file vs. only in the DB?** Recommendation: identity, column,
   status, tags, branch/PR, description, and final reports in the file (durable, greppable,
   reviewable); the full event stream / tool logs stay DB-only as operational telemetry.

---

## 13. Git & workspace model: card = branch = PR

Cardinal is tightly coupled to a git repo. A board is bound to exactly one repo
(`repo_url`, `default_branch`) — "multiple boards" later maps naturally to
one-board-per-repo, Asana-style.

**Per-card git lifecycle:**

1. Card is created → nothing happens in git. Branches are cheap but noise isn't; the
   branch is created on first entry into an execution column.
2. First entry into execution → runner provisions a **cage-style throwaway container**:
   clone (or cached fetch of) the repo, create `cardinal/<card-number>-<slug>` from the
   board's default branch, check it out. The container is the agent's entire world.
3. During the run the agent commits early and often to the card branch. Pushes go to the
   remote card branch; a **draft PR** is opened on first push (pending open question §12.3).
   The PR description is maintained by the runner: card title, link back to the card,
   latest final report.
4. `work_complete` → final push, PR marked ready for review. The PR diff *is* the primary
   artifact; the final report event links to it.
5. Revisions (`changes_requested` → re-entry into execution) → new run, **same branch**,
   new commits. The PR accumulates the whole story, just like a human's PR would.
6. Approval → merge (recommended: as the Done column's entry policy — see §12.4), branch
   deleted, card `done`. Rejection/abandonment → card archived, PR closed, branch deleted.
7. Session teardown → container destroyed. Anything not pushed is gone, by design: **the
   branch is the only durable output channel**, which makes the audit story trivial.

**Why cage-style containers are the right sandbox:**

- Isolation is the default, not a policy to enforce — the agent physically cannot touch
  the host, other cards' workspaces, or the repo outside its branch.
- Teardown is `docker rm`, so failed/abandoned runs leave zero residue.
- The container image bakes in the toolchain (git, language runtimes, Agent SDK), so
  provisioning is seconds, not a setup script per run.
- A per-card session log inside the workspace (cage's `.cage` pattern) doubles as an
  agent-facing scratch memory across runs *within* a session.

**Conflict posture (MVP):** cards are assumed independent. If a card branch falls behind
the default branch, the agent rebases at run start; a rebase conflict is a `needs_input`
event, not something the agent resolves silently. Cross-card coordination is post-MVP.

---

## 14. UI / UX specification

Design principle: **the board answers "who needs me?", the card answers "what happened?",
the gear answers "what are the rules here?"** Everything below serves one of those three.

### 14.1 Board view

```
┌ Cardinal ▸ sidekick-app ──────────────────────────────── ⚠ 2 need you ▾ ─ + Card ┐
│                                                                                   │
│  Ideas        │ Planning     │ In Progress        ⚙ │ Review          ⚙ │ Done  ⚙ │
│               │              │ 2 running · 1 queued  │ 1 ready           │         │
│ ┌───────────┐ │ ┌──────────┐ │ ┌───────────────────┐ │ ┌───────────────┐ │ ┌─────┐ │
│ │ Dark mode │ │ │ CSV      │ │ │ #14 Add rate      │ │ │ #11 Fix login │ │ │ #8 ✓│ │
│ │           │ │ │ export ● │ │ │ limiting        ⚡ │ │ │ redirect    ✅│ │ └─────┘ │
│ └───────────┘ │ │ 2 unread │ │ │ ▸ running tests…  │ │ │ PR #52 ready  │ │ ┌─────┐ │
│ ┌───────────┐ │ └──────────┘ │ │ 🌿#61 ⏱14m 💰$0.87│ │ └───────────────┘ │ │ #5 ✓│ │
│ │ Onboard   │ │              │ └───────────────────┘ │                   │ └─────┘ │
│ │ emails    │ │              │ ┌───────────────────┐ │                   │         │
│ └───────────┘ │              │ │ #17 Webhook       │ │                   │         │
│               │              │ │ retries         ❓│ │                   │         │
│               │              │ │ waiting on you 8m │ │                   │         │
│               │              │ └───────────────────┘ │                   │         │
│               │              │ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐ │                   │         │
│               │              │   #19 queued (1st)    │                   │         │
│               │              │ └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘ │                   │         │
└───────────────────────────────────────────────────────────────────────────────────┘
```

- **Card faces are status instruments.** An executing card shows: state glyph (⚡ working,
  ❓ needs input, ✅ ready for review, ✖ failed), the live one-line progress event, branch/PR
  chip, elapsed time and spend. Idle cards are just title + tags.
- **Queued cards render ghosted** with their queue position; dragging within the column
  reorders the queue.
- **Column headers carry the activity ticker** and the gear. Execution/review archetypes
  get subtle background tinting so "where behavior changes" is visible board-wide.
- **Attention dropdown** (header, `⚠ n need you`): ordered list of cards in `needs_input` /
  `failed` / `work_complete`; click jumps to the card with the relevant event focused.
  This is the primary work queue once several agents run at once.
- Drag affordances: while dragging, each column highlights with a one-line consequence —
  *"In Progress: an agent will be assigned and start work"*, *"Done: PR will be merged"*.
  The policy model makes these strings derivable, and it teaches the product's core idea
  at exactly the right moment.

### 14.2 Card detail (opens as a wide modal / side panel)

```
┌ #14 Add rate limiting ──────────────────────────────── ⚡ working · Run 2 ── ✕ ─┐
│ tags: backend, security     🌿 cardinal/14-rate-limiting → PR #61 (draft)        │
├────────────────────────────────────────────┬─────────────────────────────────────┤
│ TIMELINE   [Conversation|Activity|Debug]   │ WORK PANEL                          │
│                                            │                                     │
│ ── Run 1 ───────────────── failed ──       │ Status: working (14m) · $0.87       │
│  ▸ 23 events (collapsed)                   │ Plan:  ✓ approved 14m ago           │
│ ── Run 2 ───────────────── running ──      │  1. ✓ add Rack::Attack              │
│  🤖 Plan: I'll add Rack::Attack with…      │  2. ✓ configure per-endpoint limits │
│  👤 approved · redirect: skip /health      │  3. ▶ write request specs           │
│  🤖 progress: configured throttles         │  4. · update README                 │
│  ▸ ran 9 commands (collapsed)              │                                     │
│  🤖 progress: running request specs…       │ Artifacts:                          │
│ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁      │  · PR #61 — 6 files, +214 −12       │
│ [ Message the agent…              ⏎ ]      │  · rate_limits.md (report)          │
│                                            │                                     │
│                                            │ [⏸ Pause] [✖ Cancel run] [↻ Retry]  │
└────────────────────────────────────────────┴─────────────────────────────────────┘
```

- Timeline zoom tabs per §7; typing in the message box mid-run delivers an interrupt/
  steer event to the agent at its next checkpoint.
- The work panel is stage-aware: in Planning it shows the emerging brief; while working it
  shows live plan progress; in Review it becomes the **review panel** — final report on
  top, file-level diff summary, `[Approve] [Request changes]` buttons, deep link to the PR.
- "Request changes" focuses the message box with the feedback becoming both a timeline
  event and the seed of the next run's briefing.

### 14.3 Column settings modal (the gear)

```
┌ Column settings — “In Progress” ──────────────────────────────┐
│ Name        [In Progress        ]   Archetype  [execution ▾]  │
│                                                               │
│ Instructions (given to every agent working in this column)    │
│ [ Follow the repo style guide. Write tests for all changes. ] │
│                                                               │
│ Model            [claude-sonnet ▾]     Concurrency limit [3]  │
│ Plan approval    [● required]          Budget/run  [$2.00]    │
│ Timeout/run      [30 min]                                     │
│                                                               │
│ Tool permissions                                              │
│   [✓] read & search workspace     [✓] edit files              │
│   [✓] run commands / tests        [✓] git commit & push       │
│   [ ] network access              [ ] flagged tools (ask)     │
│                                                               │
│ Automations                                                   │
│   On entry:  [start agent run ▾]                              │
│   On success:[stay + mark ready ▾]   (or: move to → Review)   │
│                                                               │
│                                        [Cancel]  [Save]       │
└───────────────────────────────────────────────────────────────┘
```

Fields shown/hidden by archetype: a `planning` column shows model + instructions only; a
`terminal` column shows just automations (e.g., *On entry: merge PR, delete branch*);
`inbox` shows nothing but the name. The modal **is** the policy editor — there is no other
admin surface.

### 14.4 The canonical workflow, end to end

1. **Capture** — `+ Card` → "Add rate limiting to the API" lands in Ideas. Passive.
2. **Shape** — drag to Planning. The board assistant engages in the card: asks which
   endpoints, agrees limits, writes acceptance criteria, posts a *Ready for execution*
   brief event.
3. **Launch** — drag to In Progress. Consequence hint shown during the drag. Card goes
   `queued` → container provisioned, branch `cardinal/14-rate-limiting` created → agent
   posts its plan → user taps 👍 (or redirects).
4. **Work** — card face shows live progress. Agent commits/pushes; draft PR opens. A
   question ("skip /health from throttling?") parks the card in `needs_input`, the
   attention counter increments, the user answers from the attention dropdown, the run
   resumes.
5. **Deliver** — run succeeds: final report + PR marked ready; card shows ✅ ready for
   review.
6. **Review** — drag to Review. Work panel shows report + diff summary; user checks the
   PR, requests one change; card → `changes_requested`; drag back to In Progress → Run 2
   on the same branch fixes it.
7. **Ship** — drag to Done. Terminal policy merges the PR and deletes the branch. Card
   archives with its full timeline as the permanent record.

---

## 15. Decision log

- **2026-07-03** — Columns-as-policies confirmed as the core model; per-column gear modal
  is the entire policy admin surface. Card-as-agent confirmed: execution-column entry
  policy provisions a dedicated agent bound to the card. Single append-only Event timeline
  per card confirmed. Concurrency/WIP limits live in column policy, not global config.
  **MVP work domain = coding against a git repo.** Board binds to one repo; **each card
  is its own branch and PR** (`cardinal/<n>-<slug>`). Agent workspaces are **cage-style
  throwaway Docker containers** (repo cloned inside, branch checked out, destroyed on
  teardown; pushed commits are the only durable output). Agent runtime = Claude Agent SDK
  as a supervised subprocess inside the container. Architecture confirmed: Rails +
  Hotwire + Postgres (SolidQueue/SolidCable). Cards get tags/descriptions now, richer
  metadata later; multi-board (one repo per board) is post-MVP. Next step agreed: nail
  down UI/UX and workflow before scaffolding (§14 drafted).
- **2026-07-03 (later)** — Five review/git seam questions resolved per recommendation:
  (1) plan-approval gate defaults ON for columns with write tools, per-column toggleable;
  (2) human-drags-only is a product principle for MVP — no auto-advance;
  (3) draft PR opens on first push, flipped to ready on `work_complete`;
  (4) "approve" is a reversible verdict — **the merge is Done's entry policy**;
  (5) review surface = in-card final report + file-level diff summary, deep link to the
  GitHub PR for line-level review. Scaffolding started: Rails 8 + Ruby 3.4 (Fullstaq) +
  Postgres 15 inside the cage container, repo at github.com/palamedes/cardinal.

---

## 16. Portable instances: Cardinal as a tool you point at any repo (proposed)

**The idea (raised 2026-07-03):** Cardinal lives in its own repo as the *engine*, but you
instantiate it inside any repo — like cage. The board's durable state lives in that repo
as `.cardinal/` files, so every repo can carry its own Cardinal board, versioned with the
code it describes.

### Shape

```
any-repo/
 ├── .cardinal/
 │    ├── board.yml          # committed: columns, archetypes, policies
 │    ├── cards/
 │    │    ├── 14-add-rate-limiting.md   # committed: one file per card
 │    │    └── 17-webhook-retries.md
 │    └── cardinal.db        # gitignored: SQLite runtime (events, runs, sessions)
 └── src/...
```

- `cardinal up` (CLI, cage-style) in any repo → boots the engine in a container against
  that repo, reads `.cardinal/`, serves the board on a local port.
- **Card file** = frontmatter (number, column, status, tags, branch, pr_url) + markdown
  body (description, planning brief, final reports). Greppable, hand-editable, reviewable
  in PRs, survives any database.
- **Sync rule — one direction at a time:** at boot, files are the source of truth (DB
  rebuilt/reconciled from them); at runtime, the DB is authoritative and Cardinal flushes
  card/board changes back to the files as ordinary working-tree edits. Cardinal never
  commits them itself (§12.3 recommendation) — they ride along in normal commits.
- The **event stream, tool logs, and run telemetry stay in the DB only.** They are
  operational exhaust, not repo content; final reports are the durable distillate that
  lands in the card file.

### What this changes — and what it doesn't

- **Unchanged:** the entire domain model (§2), lifecycle (§3), runner design (§11),
  column-as-policy (§1). `Board.repo_url` simply becomes "the repo I'm sitting in."
- **Changed:** deployment (hosted app → per-repo instances), datastore (Postgres →
  per-instance SQLite, proposed), and "multiple boards" gets a natural answer: one board
  per repo, no multi-board UI needed at all.
- **Gained:** board state is versioned, portable, diffable; a repo is "cardinal-enabled"
  by committing `.cardinal/`; teammates get the board by cloning.
- **Tension to manage:** two representations of a card (file + DB row) means sync
  discipline matters; the one-direction-at-a-time rule above is the guard.
