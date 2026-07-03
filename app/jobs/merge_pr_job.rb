# Done's entry rule (§12.4 decision): dragging to the terminal column is the
# irreversible act — mark the PR ready, squash-merge it, delete the branch.
class MergePrJob < ApplicationJob
  queue_as :default

  def perform(card_id)
    card = Card.find(card_id)
    return if card.pr_url.blank? || card.pr_state == "merged"

    # Best-effort undraft — a QA column may already have done it, and gh
    # errors on an already-ready PR; the merge step is the real gate.
    Open3.capture2e("gh", "pr", "ready", card.pr_url)
    run_step(card, ["gh", "pr", "merge", card.pr_url, "--squash", "--delete-branch"]) or return

    card.update!(pr_state: "merged")
    card.log!("status_change", text: "PR squash-merged and branch deleted — shipped 🎉")
  end

  private

  def run_step(card, cmd)
    out, status = Open3.capture2e(*cmd)
    return true if status.success?
    card.log!("error", text: "Merge step failed (#{cmd[0..2].join(" ")}): #{out.truncate(200)}")
    false
  end
end
