class MessagesController < ApplicationController
  def create
    card = Card.find(params[:card_id])
    card.log!("user_message", actor: "user", text: params.require(:message)[:text])
    AssistantReplyJob.perform_later(card) if card.column.planning?
    redirect_to card_path(card)
  end
end
