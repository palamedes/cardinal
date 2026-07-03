class MessagesController < ApplicationController
  def create
    card = Card.find(params[:card_id])
    text = params.require(:message)[:text]
    parked_run = card.runs.where(status: "needs_input").order(:id).last

    if parked_run
      # Answer / plan feedback: goes back into the same agent session.
      kind = parked_run.phase == "plan" ? "user_message" : "answer"
      card.log!(kind, actor: "user", run: parked_run, text: text)
      ResumeRunJob.perform_later(parked_run.id, text)
    else
      card.log!("user_message", actor: "user", text: text)
      AssistantReplyJob.perform_later(card) if card.column.planning?
    end
    redirect_to card_path(card)
  end
end
