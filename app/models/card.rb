class Card < ApplicationRecord
  STATUSES = %w[
    draft discussing queued working needs_input blocked failed
    work_complete in_review changes_requested approved done archived
  ].freeze

  # Which statuses a card may hold while sitting in each column archetype.
  # The column move is the trigger; this map keeps the state machine honest (§3).
  LEGAL_STATUSES = {
    "inbox"     => %w[draft archived],
    "planning"  => %w[draft discussing archived],
    "execution" => %w[queued working needs_input blocked failed work_complete archived],
    "review"    => %w[in_review changes_requested approved archived],
    "terminal"  => %w[done archived]
  }.freeze

  belongs_to :board
  belongs_to :column
  has_many :events, -> { order(:created_at, :id) }, dependent: :destroy
  has_many :agent_sessions, dependent: :destroy
  has_many :runs, through: :agent_sessions

  enum :status, STATUSES.index_by(&:itself)

  validates :title, presence: true
  validate :status_legal_for_column

  before_validation :assign_number_and_position, on: :create

  after_commit -> { broadcast_refresh_to board }

  scope :attention, -> { where(status: %w[needs_input blocked failed work_complete]) }

  def needs_attention? = %w[needs_input blocked failed work_complete].include?(status)

  def running? = %w[queued working needs_input].include?(status)

  # Latest one-line progress event, shown live on the card face (§6).
  def latest_progress
    events.where(kind: "progress").last&.payload&.[]("text")
  end

  def default_branch_name
    "cardinal/#{number}-#{title.parameterize[0, 40]}"
  end

  def log!(kind, actor: "system", run: nil, **payload)
    events.create!(kind:, actor:, run:, payload:)
  end

  private

  def assign_number_and_position
    self.number ||= (board.cards.maximum(:number) || 0) + 1
    self.position ||= (column.cards.maximum(:position) || -1) + 1
  end

  def status_legal_for_column
    return if column.blank? || status.blank?
    legal = LEGAL_STATUSES.fetch(column.archetype, STATUSES)
    errors.add(:status, "#{status} is not legal in a #{column.archetype} column") unless legal.include?(status)
  end
end
