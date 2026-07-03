class Column < ApplicationRecord
  ARCHETYPES = %w[inbox planning execution review terminal].freeze

  belongs_to :board
  has_many :cards, -> { order(:position) }, dependent: :restrict_with_error

  enum :archetype, ARCHETYPES.index_by(&:itself)

  # The policy blob is the column's entire behavior configuration (§1, §14.3).
  store_accessor :policy, :instructions, :model, :effort, :concurrency_limit,
                 :plan_approval, :budget_per_run_cents, :timeout_minutes,
                 :max_turns, :tools, :on_entry, :on_success, :color, :arrivals,
                 :accepts_from, :footer

  # Aggregations a footer row may compute over the column's cards (card #18).
  # A compute key not listed here renders blank, so config that outruns the
  # code degrades gracefully instead of erroring.
  FOOTER_COMPUTES = %w[sum_cost sum_tokens count_cards].freeze

  # Only ever emit a validated hex color into inline styles.
  def safe_color
    color if color.to_s.match?(/\A#\h{6}\z/)
  end

  # Which columns may move cards INTO this one (§ accept policy, card #15).
  # Stored as an array of column-id strings; blank = accept from anywhere, so
  # existing boards keep their unrestricted behavior.
  def accepts?(source_column)
    ids = Array(accepts_from).map(&:to_s).reject(&:blank?)
    ids.empty? || ids.include?(source_column.id.to_s)
  end

  # Rows rendered under the cards (card #18). Footer config is an array of
  # {"label" => "Total cost:", "compute" => "sum_cost"} hashes; each row pairs
  # static label text with an optional computed aggregate over this column's
  # cards. Returns [] when unconfigured, so existing columns render no footer.
  def footer_rows
    Array(footer).filter_map do |row|
      label = row["label"].to_s
      value = footer_value(row["compute"])
      next if label.blank? && value.blank?
      { label:, value: }
    end
  end

  # Start the next queued card when a run slot frees up. A queued card whose
  # run parked and already has its answer recorded resumes instead of
  # starting fresh.
  def kick_queue
    return if at_wip_limit?
    next_card = cards.where(status: "queued").order(:position).first
    return unless next_card

    parked = next_card.runs.where(status: "needs_input").order(:id).last
    if parked&.briefing&.key?("pending_resume")
      ResumeRunJob.perform_later(parked.id, "")
    else
      StartRunJob.perform_later(next_card.id)
    end
  end

  # "claude-sonnet-4-6" → "sonnet", for compact chips on card faces.
  def model_short
    model.to_s[/claude-([a-z]+)/, 1] || model
  end

  validates :name, presence: true
  validates :position, presence: true

  def running_count = cards.where(status: "working").count
  def queued_count  = cards.where(status: "queued").count

  def at_wip_limit?
    execution? && concurrency_limit.present? && running_count >= concurrency_limit.to_i
  end

  # Aggregate a single footer row over the runs/cards in this column (card #18).
  # Unknown keys return "" so the row shows just its static label.
  def footer_value(compute)
    case compute.to_s
    when "sum_cost"
      "$%.2f" % column_runs.sum(:cost)
    when "sum_tokens"
      ActiveSupport::NumberHelper.number_to_delimited(column_runs.sum("input_tokens + output_tokens"))
    when "count_cards"
      cards.count.to_s
    else
      ""
    end
  end

  # One-line consequence shown while dragging a card over this column (§14.1).
  def drag_hint
    case archetype
    when "inbox"     then "Parked — no agent activity"
    when "planning"  then "The board assistant will join the discussion"
    when "execution" then "An agent will be assigned and start work"
    when "review"    then "Work stops — ready for your verdict"
    when "terminal"  then "Ships it — PR merged, branch deleted"
    end
  end

  private

  # Every run belonging to a card in this column, for footer aggregation.
  def column_runs
    Run.joins(agent_session: :card).where(cards: { column_id: id })
  end
end
