class CardsController < ApplicationController
  before_action :set_card, only: [:show, :update, :move]

  def create
    board = Board.first!
    column = board.columns.inbox.order(:position).first || board.columns.first
    card = board.cards.create!(column:, title: params.require(:card)[:title])
    card.log!("status_change", actor: "user", text: "Card created")
    redirect_to root_path
  end

  def show
    @zoom = params[:zoom].presence_in(%w[conversation activity debug]) || "conversation"
    @events = case @zoom
              when "conversation" then @card.events.conversation
              when "activity" then @card.events.activity
              else @card.events
              end
  end

  def update
    attrs = params.require(:card).permit(:title, :description, :tags)
    attrs[:tags] = attrs[:tags].to_s.split(",").map(&:strip).reject(&:blank?) if attrs.key?(:tags)
    @card.update!(attrs)
    @card.log!("status_change", actor: "user", text: "Card details updated")
    redirect_to card_path(@card)
  end

  def move
    column = @card.board.columns.find(params[:column_id])
    result = CardTransition.new(@card, to_column: column, position: params[:position]&.to_i).call
    if result.success?
      head :ok
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  private

  def set_card
    @card = Card.find(params[:id])
  end
end
