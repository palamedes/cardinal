class Run < ApplicationRecord
  STATUSES = %w[queued running needs_input succeeded failed cancelled].freeze

  belongs_to :agent_session
  has_one :card, through: :agent_session
  has_many :artifacts, dependent: :destroy
  has_many :events, dependent: :nullify

  enum :status, STATUSES.index_by(&:itself)

  def finished? = %w[succeeded failed cancelled].include?(status)
end
