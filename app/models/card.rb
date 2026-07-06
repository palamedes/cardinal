class Card < ApplicationRecord
  include ModelLabeling

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
    "terminal"  => %w[done blocked archived] # blocked: merge gate refused (CI red/pending)
  }.freeze

  belongs_to :board
  belongs_to :column
  belongs_to :parent, class_name: "Card", optional: true
  has_many :children, class_name: "Card", foreign_key: :parent_id,
                      dependent: :nullify, inverse_of: :parent
  has_many :events, -> { order(:created_at, :id) }, dependent: :destroy
  has_many :agent_sessions, dependent: :destroy
  has_many :ai_calls, dependent: :delete_all
  has_many :runs, through: :agent_sessions

  # Card-face status glyphs. Keyed on status, except `ready_for_approval?`
  # (a derived plan-park state, not a status) which pre-empts the ❓ below.
  STATUS_GLYPHS = {
    "working" => "⚡", "needs_input" => "❓", "failed" => "✖",
    "work_complete" => "✅", "done" => "✓", "queued" => "⏳",
    "discussing" => "💬", "in_review" => "👁", "approved" => "👍",
    "changes_requested" => "🔁"
  }.freeze

  enum :status, STATUSES.index_by(&:itself)

  validates :title, presence: true
  validate :status_legal_for_column

  before_validation :assign_number_and_position, on: :create
  # Optional git fields left blank on the new-card form arrive as "" — store
  # them as nil so "no PR/branch" is one state, not two ("" renders footers).
  normalizes :branch_name, :pr_url, with: ->(v) { v.strip.presence }

  after_commit -> { broadcast_refresh_to board }

  scope :attention, -> { where(status: %w[needs_input blocked failed work_complete]) }
  # The board shows active cards; archived ones live in /board/archive.
  scope :active,   -> { where.not(status: "archived") }
  scope :archived, -> { where(status: "archived") }

  # Where an unarchived card lands: back in its column, in that column's most
  # inert legal status — nothing fires, no agent starts.
  ARCHIVE_RESTORE = { "inbox" => "draft", "planning" => "discussing",
                      "execution" => "work_complete", "review" => "in_review",
                      "terminal" => "done" }.freeze

  def needs_attention? = %w[needs_input blocked failed work_complete].include?(status)

  # A customer-friendly summary is being (re)generated in the background (§card #35).
  def summary_working? = summary_status == "working"

  # A technical "compact" journal is being (re)generated in the background (§card
  # #34) — the AI-readable context a resuming agent reads to skip re-exploration.
  def compact_working? = compact_status == "working"

  def running? = %w[queued working needs_input].include?(status)

  # The agent has proposed a plan and is parked waiting on the user's approve
  # click — distinct from a genuine question. Same underlying `needs_input`
  # status; the plan-phase park is the signal (mirrors the work panel, §detail).
  # The status guard means the run query only fires for already-parked cards.
  def ready_for_approval?
    needs_input? && runs.needs_input.order(:id).last&.phase == "plan"
  end

  # Card-face glyph: a bell when a plan is awaiting approval, else the plain
  # per-status mapping.
  def status_glyph
    ready_for_approval? ? "🔔" : STATUS_GLYPHS[status]
  end

  # Latest one-line progress event, shown live on the card face (§6).
  def latest_progress
    events.where(kind: "progress").last&.payload&.[]("text")
  end

  # Per-card model/effort override (card #33). Nil fields mean "use the column
  # default", so existing cards are unaffected. Read fresh at every segment
  # spawn (start, restart, resume) by the runner and the planning assistant, so
  # a change takes effect on the next segment — never on an already-running one.
  # Permission override (nil = board default): "bypass" forces full autonomy
  # for this card, "ask" forces the restricted file-tools mode.
  PERMISSION_MODES = ["bypass", "ask"].freeze

  def effective_permission_bypass?
    case permission_mode
    when "bypass" then true
    when "ask"    then false
    else board.permission_bypass?
    end
  end

  def effective_model  = model.presence || column.model
  def effective_effort = effort.presence || column.effort

  # Does this card override either half of the column's "how much brain" pair?
  # Drives the de-magic marker on the card face: the board must never hide that
  # a card will spend on a model other than its column's default.
  def config_overridden? = model.present? || effort.present?

  # "Opus - High*" — the effective model label for card faces and footers, with
  # a trailing * when overridden so the override is visible without opening the
  # card. Nil when no model resolves (AI off / unset), matching Column#model_label.
  def effective_model_label
    label = model_label_of(effective_model, effective_effort)
    return if label.blank?
    config_overridden? ? "#{label}*" : label
  end

  # Running tally across every run on the card — the closed-card cost footer
  # (card #20). Sums stopped/restarted segments so the total reflects real spend.
  # Honest money: worker runs PLUS every one-shot call made on this card's
  # behalf (planning assistant, ai_task, summary/compact) — see AiCall.
  def total_cost = runs.sum(:cost) + ai_calls.sum(:cost)
  def total_output_tokens = runs.sum(:output_tokens) + ai_calls.sum(:output_tokens)

  def assistant_cost = ai_calls.where(kind: "assistant").sum(:cost)

  # Is the planning assistant expected to post next? True right after entering
  # a planning column (kickoff inspection pending) or after a user message.
  def awaiting_assistant?
    return false unless column.planning? && column.ai?
    last = events.where(kind: %w[user_message assistant_message error column_move]).order(:id).last
    return false if last&.payload&.[]("note") # a note-only message expects no reply
    last.present? && %w[user_message column_move].include?(last.kind)
  end

  # Planning chip state (card #25): the assistant ends discussion by posting
  # a "Ready for execution" brief — the SAME marker Agent::Runner promotes
  # into worker briefings. When that's the assistant's latest word, the card
  # face flips from "replied" to "ready".
  def planning_ready?
    discussing? &&
      events.where(kind: "assistant_message").order(:id).last&.text.to_s.match?(/ready for execution/i)
  end

  # Some AI is expected to write to this card imminently.
  def thinking?
    awaiting_assistant? || working?
  end

  # URLs speak card numbers, matching every other surface (header #N,
  # branches, PR titles) — not database ids, which drift after deletions.
  def to_param = number.to_s

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
