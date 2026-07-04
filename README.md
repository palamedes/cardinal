# Cardinal AI 🐦‍🔥

**A Kanban board where dragging a card to "In Progress" hires an AI to actually do the task.**

Cardinal AI puts a board on any of your projects. You write down what needs doing, chat
with an assistant to sharpen the idea, and then drag the card forward — at which point an
AI agent picks it up, does the work on its own branch, asks you questions when it's stuck,
and hands you a pull request to review. Approve it, drag the card to Done, and the work is
merged. You never leave the board.

## What you need

- **Ruby 3.2 or newer** (`ruby -v` to check)
- **The Claude CLI**, signed in — this is the AI: `npm install -g @anthropic-ai/claude-code`, then `claude` once to log in
- **git**, and for pull requests the **GitHub CLI** (`gh auth login`)

## Install

```sh
gem install cardinal-ai
```

## Use it

Go to any project that lives in git, and start Cardinal:

```sh
cd your-project
cardinal
```

The first time, a browser window asks **which Claude account this board should work as** —
pick one, and it's remembered for this project only. Then open **http://localhost:4000**.

That's the whole setup. Now:

1. **Add a card** for something you want done, in plain English.
2. **Drag it to Planning** — an assistant reads your card *and your code*, then asks the
   questions that make the task clear. Chat until it feels right.
3. **Drag it to In Progress** — an agent studies the repo and proposes a plan. One click
   to approve. Then it works: you can watch its progress live on the card, and it will
   stop and ask you if it hits a real decision.
4. **Review** — read the final report and the pull request. Say what's wrong in the
   card's conversation to send it back, or approve.
5. **QA** — the pull request goes live for formal review on GitHub.
6. **Drag to Done** — the pull request merges. Shipped. (If the project has CI and it's
   red or still running, Cardinal refuses to merge and tells you why on the card.)

Every column has a ⚙ gear where you can change the rules — which AI model works there,
how many cards can run at once, spending limits, and what happens when a card arrives
(written in plain English; Cardinal figures out the rest).

### The deep dive

The **🔍 Deep dive** button in the topbar sends a read-only agent (it can look, never
touch) through your repo once and saves what it learns as a **repo brief** — what the
project is, where things live, how to build and test it, the traps to avoid. Every worker
agent gets the brief with its assignment, so agents skip re-exploring your codebase on
every single card. It costs one AI call.

Once a brief exists the button shows **🔍 Repo brief** — click it to read exactly what
agents are being told, and to regenerate it. The button drifts from grey toward red as
commits land that the brief hasn't seen; Cardinal won't silently re-run a dive that's
already current.

## Good to know

- Everything Cardinal knows about a project lives in a `.cardinal/` folder inside it,
  invisible to git. Delete the folder and Cardinal was never there.
- Each project's board can use a **different Claude account** (`cardinal login` to switch,
  `cardinal logout` to unlink).
- Agents can only push to their own card branches — merging is always your drag.
- AI usage bills the Claude account you linked, the same as using Claude Code.
- The board is only reachable from **your own machine** (localhost). To browse it from
  another device on your network — a phone or tablet — start with `CARDINAL_HOST=0.0.0.0
  cardinal`, and know that anyone on that network can then drive your board.
- In a worker column's ⚙ gear you can turn off **Shell access**: the agent can then only
  read and edit files — it can't run commands — and Cardinal commits its work for it.

## For developers

The architecture and design history live in [cardinal.md](cardinal.md). The engine is a
Rails 8 app — clone, `bundle install`, `bin/rails test`. MIT licensed.
