# Column rule action (§17): take the card's PR out of draft — used by QA-style
# columns where the work should be formally reviewable on GitHub.
class MarkPrReadyJob < ApplicationJob
  queue_as :default

  def perform(card_id)
    card = Card.find(card_id)
    return if card.pr_url.blank?

    out, status = Open3.capture2e("gh", "pr", "ready", card.pr_url)
    if status.success? || out.downcase.include?("already")
      card.update!(pr_state: "ready")
      card.log!("status_change", text: "PR marked ready for review (out of draft)")
    else
      card.log!("error", text: "Could not mark PR ready: #{out.truncate(200)}")
    end
  end
end
