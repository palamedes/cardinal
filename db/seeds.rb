# Default Cardinal board: the five-column archetype layout from cardinal.md §1,
# bound to this app's own repo — Cardinal will eventually build itself.
board = Board.find_or_create_by!(name: "Cardinal") do |b|
  b.repo_url = "git@github.com:palamedes/cardinal.git"
  b.default_branch = "main"
end

defaults = [
  { name: "Tasks",       archetype: "inbox",     policy: {} },
  { name: "Planning",    archetype: "planning",  policy: { "model" => "claude-haiku-4-5-20251001" } },
  { name: "In Progress", archetype: "execution",
    policy: { "model" => "claude-sonnet-4-6", "effort" => "high", "concurrency_limit" => 3, "plan_approval" => true,
              "budget_per_run_cents" => 200, "timeout_minutes" => 30, "max_turns" => 25,
              "on_entry" => [{ "action" => "start_agent_run" }],
              "tools" => %w[read edit run_commands git_commit_push] } },
  { name: "Review",      archetype: "review",    policy: {} },
  { name: "Done",        archetype: "terminal",  policy: { "on_entry" => [{ "action" => "merge_pr" }] } }
]

defaults.each_with_index do |attrs, index|
  board.columns.find_or_create_by!(name: attrs[:name]) do |c|
    c.position = index
    c.archetype = attrs[:archetype]
    c.policy = attrs[:policy]
  end
end

if board.cards.none?
  ideas = board.columns.find_by!(name: "Tasks")
  [
    { title: "Column settings gear modal", tags: %w[ui policy],
      description: "The gear icon on each column opens the policy editor (cardinal.md §14.3)." },
    { title: "Agent runner: provision cage container per card", tags: %w[runner agents],
      description: "ProvisionAgentJob + RunnerJob driving the Agent SDK subprocess (cardinal.md §11)." },
    { title: "Planning assistant chat", tags: %w[agents planning],
      description: "AssistantReplyJob answering user messages on cards in planning columns." }
  ].each do |attrs|
    card = board.cards.create!(column: ideas, **attrs)
    card.log!("status_change", actor: "user", text: "Card created")
  end
end

puts "Seeded board '#{board.name}' with #{board.columns.count} columns and #{board.cards.count} cards."
