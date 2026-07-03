class CardsController < ApplicationController
  before_action :set_card, only: [:show, :update, :move, :approve, :destroy]

  def new
    @board = Board.first!
    @parent = @board.cards.find_by(id: params[:parent_id])
  end

  def create
    board = Board.first!
    column = board.columns.inbox.order(:position).first || board.columns.first
    parent = board.cards.find_by(id: params.dig(:card, :parent_id))
    card = board.cards.create!(column:, parent:, **card_params)
    card.log!("status_change", actor: "user", text: parent ? "Card created as a child of ##{parent.number} #{parent.title}" : "Card created")
    parent&.log!("status_change", actor: "user", text: "Child card added: #{card.title}")
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

    # A frame navigation (opening the modal from the board) only needs the modal
    # frame. A direct visit — bookmark, reload, or history restore of /cards/:id —
    # must render the whole board with the modal already open behind it.
    unless turbo_frame_request?
      @board = @card.board
      render "boards/show"
    end
  end

  def update
    attrs = card_params
    attrs.delete(:title) if params[:autosave] && attrs[:title].blank? # mid-edit blank, not a delete
    @card.update!(attrs)
    log_changelog!

    respond_to do |format|
      # Explicitly patch the board face in this tab too — Turbo suppresses a
      # tab's own refresh broadcasts, so the morph won't cover the originator.
      # Autosave must NOT replace the modal (it would steal focus mid-typing).
      format.turbo_stream do
        streams = [turbo_stream.replace(helpers.dom_id(@card), partial: "cards/card", locals: { card: @card })]
        unless params[:autosave]
          @zoom = "conversation"
          @events = @card.events.conversation
          streams << turbo_stream.replace("modal", template: "cards/show", formats: [:html])
        end
        render turbo_stream: streams
      end
      format.html { redirect_to card_path(@card) }
    end
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

  def move
    from_column = @card.column
    to_column = @card.board.columns.find(params[:column_id])
    result = CardTransition.new(@card, to_column: to_column, position: params[:position]&.to_i).call
    if result.success?
      # Fresh markup for the affected columns: Turbo suppresses this tab's own
      # refresh broadcasts, so without this the dragged card keeps its stale
      # face (no queued ghosting, no ticker bump) until a job-thread broadcast.
      render turbo_stream: [from_column, to_column].uniq.map { |col|
        turbo_stream.replace(helpers.dom_id(col), partial: "columns/column", locals: { column: col.reload })
      }
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

  # Changelog in the activity timeline (the mechanism already exists). A burst
  # of autosaves coalesces into one entry instead of one per pause-in-typing.
  def log_changelog!
    changed = @card.previous_changes.keys & %w[title description tags]
    return if changed.empty?

    last = @card.events.order(:id).last
    if last&.kind == "status_change" && last.payload["changelog"] && last.created_at > 10.minutes.ago
      fields = (Array(last.payload["fields"]) | changed)
      last.update!(payload: last.payload.merge("fields" => fields, "text" => "Details edited: #{fields.join(", ")}"))
    else
      @card.log!("status_change", actor: "user", changelog: true, fields: changed,
                 text: "Details edited: #{changed.join(", ")}")
    end
  end
end
