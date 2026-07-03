class AgentSession < ApplicationRecord
  STATUSES = %w[provisioning ready torn_down].freeze

  belongs_to :card
  has_many :runs, dependent: :destroy

  enum :status, STATUSES.index_by(&:itself)
end
