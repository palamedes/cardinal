# Column rules (cardinal.md §17): a column's on_entry policy is a list of rule
# actions fired when a card lands in it. Archetypes only supply defaults —
# any column can carry any rules, including one-shot AI maintenance tasks.
module Rules
  DEFAULTS = {
    "planning"  => [{ "action" => "assistant_greeting" }],
    "execution" => [{ "action" => "start_agent_run" }],
    "terminal"  => [{ "action" => "merge_pr" }]
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
      card.log!("assistant_message", actor: "assistant",
                text: "I'm here to help shape this card. What's the goal, and how will we know it's done?")
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
