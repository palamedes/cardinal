class Artifact < ApplicationRecord
  KINDS = %w[pull_request file report link].freeze

  belongs_to :run

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true
end
