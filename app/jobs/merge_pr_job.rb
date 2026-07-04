# Done's entry rule (§12.4 decision): dragging to the terminal column is the
# irreversible act — mark the PR ready, squash-merge it, delete the branch.
class MergePrJob < ApplicationJob
  queue_as :default

  def perform(card_id)
    card = Card.find(card_id)
    return if card.pr_url.blank? || card.pr_state == "merged"
    return unless checks_green?(card)

    # Best-effort undraft — a QA column may already have done it, and gh
    # errors on an already-ready PR; the merge step is the real gate.
    Open3.capture2e("gh", "pr", "ready", card.pr_url)
    run_step(card, ["gh", "pr", "merge", card.pr_url, "--squash", "--delete-branch"]) or return

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

  def run_step(card, cmd)
    out, status = Open3.capture2e(*cmd)
    return true if status.success?
    card.log!("error", text: "Merge step failed (#{cmd[0..2].join(" ")}): #{out.truncate(200)}")
    false
  end
end
