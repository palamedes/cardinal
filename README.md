# Cardinal 🐦‍🔥

**A Kanban board where dragging a card to "In Progress" hires an AI to actually do the task.**

Cardinal is a Kanban board where the cards do the work. It's a little tool you fire up
inside any code repo, and it gives you a board like Trello — but the columns aren't just
labels, they're rules. The far-left column is where you dump ideas. The next one has an AI
assistant that helps you think each idea through. And when you drag a card into
"In Progress," that card *becomes* its own AI agent — it spins up in a sandbox, writes the
code on its own branch, reports its progress right on the card, and asks you questions when
it's stuck. When it's done, you drag the card to Review, look at the pull request it made,
and either send it back with notes or drag it to Done — which merges the code.

It's not an app you sign up for. It's more like having a small dev team living in your
repo, and the board is how you manage them. Dragging a card left to right literally *is*
assigning the work, supervising it, and shipping it.

## Status

Early but real: the full card lifecycle works end to end. Cards become agents in
execution columns (plan approval → work → questions back to you → draft PR), you review
and request changes (revision runs on the same branch), and dragging to Done squash-merges
the PR. Column rules, one-shot AI maintenance agents, a policy editor behind every
column's gear icon, run heartbeats + sweeping, and `cardinal up` for spinning a board up
inside any repo. PRs #2 and #3 of this very repo were written by Cardinal cards. The
design document — architecture, decisions, roadmap — lives in [cardinal.md](cardinal.md).

## Stack

Rails 8.1 · Ruby 3.4 · SQLite (the whole instance lives in `.cardinal/`) · Hotwire.
No database server, no Redis, no sign-in.

## Running it

```sh
bundle install
bin/rails db:prepare db:seed
bin/rails server
```

Then open http://localhost:3000 (or set `PORT`).

*Drag it to Done.*
