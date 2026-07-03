class MessagesController < ApplicationController
  def create
    card = Board.first!.cards.find_by!(number: params[:card_id])
    text = params.require(:message)[:text]
    parked_run = card.runs.where(status: "needs_input").order(:id).last

    if parked_run
      # Answer / plan feedback: goes back into the same agent session.
      kind = parked_run.phase == "plan" ? "user_message" : "answer"
      card.log!(kind, actor: "user", run: parked_run, text: text)
      ResumeRunJob.perform_later(parked_run.id, text)
    elsif card.column.review? && %w[in_review approved].include?(card.status)
      # Review is entirely human: feedback IS the conversation. A message on a
      # card under review marks it changes_requested; dragging it back to a
      # work column carries the feedback into the next run's briefing.
      card.log!("user_message", actor: "user", text: text)
      card.update!(status: "changes_requested")
      card.log!("status_change", actor: "user", text: "Changes requested — drag the card back to a work column when ready")
    else
      card.log!("user_message", actor: "user", text: text)
      AssistantReplyJob.perform_later(card) if card.column.planning?
    end
    redirect_to card_path(card)
  end
end
