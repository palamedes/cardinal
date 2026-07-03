class Column < ApplicationRecord
  ARCHETYPES = %w[inbox planning execution review terminal].freeze

  belongs_to :board
  has_many :cards, -> { order(:position) }, dependent: :restrict_with_error

  enum :archetype, ARCHETYPES.index_by(&:itself)

  # The policy blob is the column's entire behavior configuration (§1, §14.3).
  store_accessor :policy, :instructions, :model, :concurrency_limit,
                 :plan_approval, :budget_per_run_cents, :timeout_minutes,
                 :tools, :on_entry, :on_success

  validates :name, presence: true
  validates :position, presence: true

  def running_count = cards.where(status: "working").count
  def queued_count  = cards.where(status: "queued").count

  def at_wip_limit?
    execution? && concurrency_limit.present? && running_count >= concurrency_limit.to_i
  end

  # One-line consequence shown while dragging a card over this column (§14.1).
  def drag_hint
    case archetype
    when "inbox"     then "Parked — no agent activity"
    when "planning"  then "The board assistant will join the discussion"
    when "execution" then "An agent will be assigned and start work"
    when "review"    then "Work stops — ready for your verdict"
    when "terminal"  then "Card will be finalized"
    end
  end
end
