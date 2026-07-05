# On-demand, AI-readable "compact" of a card (card #34): the technical mirror of
# SummaryJob. Where Summary compresses a card into a couple of non-technical lines
# for a customer chat, Compact distills everything that happened — the brief,
# timeline, runs, final reports, and code commits — into a dense technical journal
# a *resuming agent* can read instead of re-exploring the repo and re-deriving
# context. That's the whole point: spend a few tokens now to save many later.
# Generation is user-triggered only; the result persists on the card and stays
# fully editable. A prior compact (possibly hand-edited) rides along as context so
# a regeneration refines rather than discards what the user kept.
class CompactJob < ApplicationJob
  queue_as :default

  FALLBACK_MODEL = "claude-haiku-4-5-20251001".freeze

  SYSTEM = <<~SYS.freeze
    You write a dense, technical engineering journal for an AI agent that will
    resume work on this card later. Your reader is a machine, not a customer:
    optimize for signal, not readability. Capture, in compact form, everything a
    resuming engineer needs so they do NOT have to re-explore the repo or re-derive
    context — what was built and how, files and components touched, key APIs and
    libraries used, decisions made and the reasons behind them, issues found,
    blockers hit, and anything left unfinished or deliberately deferred. Prefer
    terse structured notes (short headings, bullets, file paths, symbol names) over
    prose. Omit pleasantries and customer-facing framing. Write only the journal.
  SYS

  def perform(card)
    return clear_working(card) unless ClaudeCli.available?

    model = card.board.columns.find_by(archetype: "planning")&.model.presence || FALLBACK_MODEL
    compact = ClaudeCli.prompt(build_prompt(card), system: SYSTEM, model: model, max_turns: 1,
                               ledger: { kind: "compact", card: card })

    card.update!(compact: compact.to_s.strip, compact_generated_at: Time.current, compact_status: nil)
    card.broadcast_replace_to card, target: "card_compact",
                              partial: "cards/compact_panel", locals: { card: card }
  rescue StandardError
    # A failed generation must not leave the button stuck on "Generating…".
    clear_working(card)
  end

  private

  def clear_working(card)
    card.update!(compact_status: nil)
    card.broadcast_replace_to card, target: "card_compact",
                              partial: "cards/compact_panel", locals: { card: card }
  end

  def build_prompt(card)
    parts = ["Card ##{card.number}: #{card.title}"]
    parts << "Tags: #{card.tags.join(", ")}" if card.tags.any?
    parts << "\nBrief / description:\n#{card.description}" if card.description.present?

    timeline = card.events.activity.filter_map { |e| event_line(e) }
    parts << "\nWhat happened (technical timeline):\n#{timeline.join("\n")}" if timeline.any?

    reports = card.events.where(kind: "final_report").filter_map(&:text).map(&:strip).reject(&:blank?)
    parts << "\nFinal reports from runs:\n#{reports.join("\n\n---\n\n")}" if reports.any?

    runs = card.runs.order(:id).map { |r| "- Run ##{r.id}: #{r.status}#{" (#{r.phase})" if r.phase.present?}" }
    parts << "\nRuns:\n#{runs.join("\n")}" if runs.any?

    commits = commit_lines(card)
    parts << "\nCode changes (commit messages):\n#{commits.join("\n")}" if commits.any?

    if card.compact.present?
      parts << "\nThe existing technical compact is below. It may have been edited by hand, " \
               "so preserve details the user kept and fold in any new work rather than " \
               "starting from scratch:\n#{card.compact}"
    end

    parts.join("\n")
  end

  def event_line(event)
    text = event.text.to_s.strip
    return nil if text.blank?
    "- #{event.actor}: #{text.truncate(600)}"
  end

  # Commit messages for the card's branch, read from the per-card workspace
  # checkout when it still exists. The checkout isn't guaranteed to be present
  # (it's left in place after a run but may be pruned), so this is best-effort —
  # the timeline already narrates the work when commits are unavailable.
  def commit_lines(card)
    return [] if card.branch_name.blank?
    path = Agent::Workspace::Local.new(card).path
    return [] unless File.directory?(path.join(".git"))

    base = "origin/#{card.board.default_branch}"
    out, ok = Open3.capture2e("git", "-C", path.to_s, "log", "--oneline", "--no-decorate", "#{base}..HEAD")
    return [] unless ok.success?
    out.lines.map(&:strip).reject(&:blank?).map { |l| "- #{l}" }
  rescue StandardError
    []
  end
end
