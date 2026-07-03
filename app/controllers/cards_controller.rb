class CardsController < ApplicationController
  before_action :set_card, only: [:show, :update, :move, :approve, :request_changes, :destroy]

  def new
  end

  def create
    board = Board.first!
    column = board.columns.inbox.order(:position).first || board.columns.first
    card = board.cards.create!(column:, **card_params)
    card.log!("status_change", actor: "user", text: "Card created")
    redirect_to root_path
  end

  # Rarely needed, deliberately buried in the card modal. A working card must
  # be cancelled first — no killing live agents by deleting their card.
  def destroy
    if @card.working?
      redirect_to card_path(@card)
      return
    end
    workspace_path = Agent::Workspace::Local.new(@card).path
    @card.destroy!
    FileUtils.rm_rf(workspace_path)
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
    @card.update!(card_params)
    @card.log!("status_change", actor: "user", text: "Card details updated")
    redirect_to card_path(@card)
  end

  # Review verdicts (§3, §14.2). Approve is reversible — the merge happens as
  # Done's entry rule when the human drags the card there.
  def approve
    if @card.in_review?
      @card.update!(status: "approved")
      @card.log!("status_change", actor: "user", text: "Work approved — drag to Done to ship")
    end
    redirect_to card_path(@card)
  end

  def request_changes
    feedback = params.require(:card)[:feedback]
    if %w[in_review approved].include?(@card.status) && feedback.present?
      @card.update!(status: "changes_requested")
      @card.log!("user_message", actor: "user", text: "Changes requested:\n#{feedback}")
      @card.log!("status_change", actor: "user", text: "Drag the card back to an execution column for a revision run")
    end
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

  def card_params
    attrs = params.require(:card).permit(:title, :description, :tags)
    attrs[:tags] = attrs[:tags].to_s.split(",").map(&:strip).reject(&:blank?) if attrs.key?(:tags)
    attrs.to_h.symbolize_keys
  end
end
