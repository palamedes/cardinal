class Run < ApplicationRecord
  STATUSES = %w[queued running needs_input succeeded failed cancelled].freeze

  belongs_to :agent_session
  has_one :card, through: :agent_session
  has_many :artifacts, dependent: :destroy
  has_many :permission_requests, dependent: :destroy
  has_many :events, dependent: :nullify

  enum :status, STATUSES.index_by(&:itself)

  # A budget/timeout outcome, whether the segment parked (needs_input) or was
  # recorded as a failure. The parked message ("…turn budget mid-work…") lives
  # on the last question event; the failure message (failure_reason) lives on
  # result_summary. Either signals "try again with a fresh budget," not a bug.
  EXHAUSTION = /turn budget|max-turns budget|timed out|timeout/i

  def finished? = %w[succeeded failed cancelled].include?(status)

  def exhausted?
    text = needs_input? ? events.where(kind: "question").order(:id).last&.text : result_summary
    text.to_s.match?(EXHAUSTION)
  end

  # A run the user can relaunch from the work panel: an execution-column run
  # that parked or failed on its budget/timeout. Restart resumes the surviving
  # session (fresh budget) or starts a clean run when no session remains.
  def restartable? = card.column.execution? && (needs_input? || failed?) && exhausted?
end
