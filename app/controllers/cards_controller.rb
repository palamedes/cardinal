class CardsController < ApplicationController
  before_action :set_card, only: [:show, :update, :move, :approve, :summarize, :compact, :destroy]

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
    @zoom = params[:zoom].presence_in(%w[conversation activity debug summary compact]) || "conversation"
    @events = case @zoom
              when "conversation" then @card.events.conversation
              when "activity" then @card.events.activity
              when "summary", "compact" then Event.none # these tabs show a card panel, not events
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
    # branch_name and pr_url lock once set (by the user or the agent) — never
    # let a later edit clobber a value that work may already depend on.
    attrs.delete(:branch_name) if @card.branch_name.present?
    attrs.delete(:pr_url) if @card.pr_url.present?
    @card.update!(attrs)
    log_changelog!
    log_config_change!

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

    respond_to do |format|
      # Flash the verdict in place, then let the dismiss controller minimize the
      # modal. Patch the board face too — Turbo suppresses this tab's own refresh
      # broadcast, so without this the card keeps its stale status once we close.
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(helpers.dom_id(@card), partial: "cards/card", locals: { card: @card }),
          turbo_stream.replace("review-callout", partial: "cards/dismiss_flash",
                                                  locals: { message: "Approved — closing…" })
        ]
      end
      format.html { redirect_to card_path(@card) }
    end
  end

  # Generate a customer-friendly summary on demand (card #35). Non-blocking,
  # mirroring the board's deep dive: flip the card into its "working" state,
  # morph the Summary panel so the button reflects it, and let SummaryJob do the
  # one-shot synthesis in the background. Skipped when one is already running.
  def summarize
    unless @card.summary_working?
      @card.update!(summary_status: "working")
      SummaryJob.perform_later(@card)
    end
    render turbo_stream: turbo_stream.replace("card_summary",
             partial: "cards/summary_panel", locals: { card: @card })
  end

  # Generate a technical "compact" journal on demand (card #34). The AI-readable
  # mirror of #summarize: flip the card into its "working" state, morph the Compact
  # panel so the button reflects it, and let CompactJob do the one-shot synthesis
  # in the background. Skipped when one is already running.
  def compact
    unless @card.compact_working?
      @card.update!(compact_status: "working")
      CompactJob.perform_later(@card)
    end
    render turbo_stream: turbo_stream.replace("card_compact",
             partial: "cards/compact_panel", locals: { card: @card })
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
    @card = Board.first!.cards.find_by!(number: params[:id])
  end

  def card_params
    attrs = params.require(:card).permit(:title, :description, :tags, :branch_name, :pr_url, :summary, :compact, :model, :effort)
    attrs[:tags] = attrs[:tags].to_s.split(",").map(&:strip).reject(&:blank?) if attrs.key?(:tags)
    # Blank model/effort from the "Use column default" option mean "no override" —
    # store nil so effective_* falls back to the column (card #33).
    attrs[:model] = attrs[:model].presence if attrs.key?(:model)
    attrs[:effort] = attrs[:effort].presence if attrs.key?(:effort)
    attrs.to_h.symbolize_keys
  end

  # Changelog in the activity timeline (the mechanism already exists). A burst
  # of autosaves coalesces into one entry instead of one per pause-in-typing.
  def log_changelog!
    changed = @card.previous_changes.keys & %w[title description tags branch_name pr_url summary compact]
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

  # A model/effort override is not a routine detail edit — it changes what the
  # card will spend on. Log each change explicitly with its old→new value (the
  # "config_change" kind, card #33) instead of coalescing it into the changelog
  # above, so the timeline records exactly what the money will run on and when.
  def log_config_change!
    (@card.previous_changes.keys & %w[model effort]).each do |field|
      old, new = @card.previous_changes[field].map { |v| v.presence || "column default" }
      @card.log!("config_change", actor: "user", field: field, old: old, new: new,
                 text: "#{field.capitalize} changed: #{old} → #{new}")
    end
  end
end
