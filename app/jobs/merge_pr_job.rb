# Done's entry rule (§12.4 decision): dragging to the terminal column is the
# irreversible act — mark the PR ready, squash-merge it, delete the branch.
class MergePrJob < ApplicationJob
  queue_as :default

  def perform(card_id)
    card = Card.find(card_id)
    return if card.pr_url.blank? || card.pr_state == "merged"
    return unless checks_green?(card)
    return unless mergeable?(card)

    # Best-effort undraft — a QA column may already have done it, and gh
    # errors on an already-ready PR; the merge step is the real gate.
    Open3.capture2e("gh", "pr", "ready", card.pr_url)
    unless run_step(card, ["gh", "pr", "merge", card.pr_url, "--squash", "--delete-branch"])
      # The floor (card #55): a card whose merge failed must never sit in
      # Done claiming done — block it so the attention dropdown surfaces it.
      card.update!(status: "blocked")
      return
    end

    card.update!(pr_state: "merged")
    card.log!("status_change", text: "PR squash-merged and branch deleted — shipped 🎉")
  end

  private

  # The merge gate: never ship over failing CI. A repo with no checks
  # configured passes (nothing to gate on); failing or still-running checks
  # park the card as blocked with the reason — drag it out and back into Done
  # to retry once CI is green.
  def checks_green?(card)
    out, status = Open3.capture2e("gh", "pr", "checks", card.pr_url)
    return true if status.success?
    return true if out.match?(/no checks reported/i)

    reason =
      if status.exitstatus == 8
        "CI checks are still running — not merged. Drag out of Done and back once they finish."
      else
        failing = out.lines.map(&:strip).grep(/fail/i).first(3).join("; ").presence || out.strip.truncate(160)
        "CI checks failing — not merged. #{failing}"
      end
    card.log!("error", text: reason)
    card.update!(status: "blocked")
    false
  end

  # A sibling card's merge can conflict this one after its CI ran (card #55) —
  # mergeability is a separate axis from checks. Ask before attempting so the
  # conflict parks with a clean reason instead of a raw gh error. UNKNOWN
  # (GitHub still computing) and gh hiccups fall through to the merge attempt,
  # which remains the authority.
  def mergeable?(card)
    out, status = Open3.capture2e("gh", "pr", "view", card.pr_url, "--json", "mergeable")
    return true unless status.success?
    return true unless JSON.parse(out)["mergeable"] == "CONFLICTING"

    card.log!("error", text: "Merge conflict with #{card.board.default_branch} — not merged. " \
                             "Another card's merge likely landed first. Drag this card back to " \
                             "In Progress for a conflict-resolution run, then bring it back here.")
    card.update!(status: "blocked")
    false
  rescue JSON::ParserError
    true
  end

  def run_step(card, cmd)
    out, status = Open3.capture2e(*cmd)
    return true if status.success?
    card.log!("error", text: "Merge step failed (#{cmd[0..2].join(" ")}): #{out.truncate(200)}")
    false
  end
end
