module Rules
  # Turns a plain-English description of a column's on-entry behavior into the
  # rule actions the dispatcher executes (§17). English is the source of
  # truth; the compiled JSON is stored alongside it and shown read-only.
  module Compiler
    Error = Class.new(StandardError)

    VOCABULARY = <<~DOC.freeze
      Available actions:
      - {"action": "assistant_greeting"} — the planning assistant posts an opening message
      - {"action": "start_agent_run"} — assign a dedicated worker agent to the card and start a run
      - {"action": "ai_task", "prompt": "...", "model": "optional-model-id"} — a one-shot AI maintenance
        task; the prompt may use %{title}, %{description}, %{conversation}; its output is posted to the
        card timeline
      - {"action": "mark_pr_ready"} — take the card's PR out of draft (ready for review on GitHub)
      - {"action": "merge_pr"} — mark the card's PR ready, squash-merge it, delete the branch
      - {"action": "set_status", "status": "..."} — force a card status
    DOC

    def self.compile(text)
      raise Error, "Rules compiler needs the claude CLI — use the advanced JSON editor instead." unless ClaudeCli.available?

      raw = ClaudeCli.prompt(
        text,
        ledger: { kind: "rules_compile" },
        model: AssistantReplyJob::FALLBACK_MODEL,
        system: <<~SYS
          You compile plain-English descriptions of Kanban column automation into JSON rule
          arrays for the Cardinal board engine.

          #{VOCABULARY}
          Respond with ONLY the JSON array — no prose, no code fences. If the description
          asks for something outside the vocabulary, approximate it with an ai_task whose
          prompt captures the intent.
        SYS
      ).strip
      raw = raw.sub(/\A```(?:json)?\s*/, "").sub(/```\z/, "").strip
      rules = JSON.parse(raw)
      validate!(rules)
      rules
    rescue JSON::ParserError
      raise Error, "Compiler returned invalid JSON — try rephrasing, or use the advanced editor."
    rescue ClaudeCli::Error => e
      raise Error, "Compiler call failed: #{e.message.truncate(120)}"
    end

    def self.validate!(rules)
      raise Error, "Expected a JSON array of rules" unless rules.is_a?(Array)
      known = %w[assistant_greeting start_agent_run ai_task mark_pr_ready merge_pr set_status]
      rules.each do |rule|
        raise Error, "Each rule must be an object with an \"action\"" unless rule.is_a?(Hash) && rule["action"].present?
        raise Error, "Unknown action #{rule["action"].inspect}" unless known.include?(rule["action"])
      end
    end
  end
end
