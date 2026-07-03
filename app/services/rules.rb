# Column rules (cardinal.md §17): a column's on_entry policy is a list of rule
# actions fired when a card lands in it. Archetypes only supply defaults —
# any column can carry any rules, including one-shot AI maintenance tasks.
module Rules
  DEFAULTS = {
    "planning"  => [{ "action" => "assistant_greeting" }],
    "execution" => [{ "action" => "start_agent_run" }],
    "terminal"  => [{ "action" => "merge_pr" }]
  }.freeze

  # Shown in the gear modal so the archetype's built-in behavior is visible,
  # not implied (the on-entry box being blank doesn't mean nothing happens).
  DEFAULT_DESCRIPTIONS = {
    "inbox"     => "Nothing — cards park here untouched.",
    "planning"  => "The planning assistant inspects the card and opens the conversation: it reads the title and description, then asks its sharpest clarifying questions to improve the card before execution. Tune its focus with the Instructions field above.",
    "execution" => "A dedicated worker agent is assigned to the card and a run starts (plan-first if plan approval is on).",
    "review"    => "Nothing automatic — the card waits for your verdict.",
    "terminal"  => "The card's PR is marked ready, squash-merged, and its branch deleted."
  }.freeze

  def self.fire_entry(card, column)
    each_rule(column.policy["on_entry"], column.archetype) do |rule|
      apply(rule, card, column)
    end
  end

  def self.each_rule(configured, archetype, &block)
    rules = configured.presence || DEFAULTS[archetype] || []
    rules = [rules] if rules.is_a?(Hash) || rules.is_a?(String)
    rules.map { |r| r.is_a?(String) ? { "action" => r } : r }.each(&block)
  end

  def self.apply(rule, card, column)
    case rule["action"]
    when "assistant_greeting"
      # Contextual opener: the assistant reads the card and asks targeted
      # questions (AssistantReplyJob falls back to a canned line without a key).
      AssistantReplyJob.perform_later(card, kickoff: true)
    when "start_agent_run"
      card.update!(branch_name: card.branch_name.presence || card.default_branch_name)
      card.log!("status_change", text: "Queued for execution on #{card.branch_name}")
      StartRunJob.perform_later(card.id)
    when "ai_task"
      # One-shot maintenance agent: a bounded Messages API call whose prompt
      # comes from the rule config. No workspace, no session, no tools.
      AiTaskJob.perform_later(card.id, rule["prompt"].to_s, rule["model"])
    when "merge_pr"
      if card.pr_url.present?
        card.log!("status_change", text: "Shipping: merging #{card.pr_url}")
        MergePrJob.perform_later(card.id)
      else
        card.log!("status_change", text: "Card finalized (no PR to merge)")
      end
    when "set_status"
      card.update!(status: rule["status"]) if Card::STATUSES.include?(rule["status"])
    else
      card.log!("error", text: "Unknown column rule: #{rule["action"].inspect}")
    end
  end
end
