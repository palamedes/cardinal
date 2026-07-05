# One row per one-shot AI call (§ money honesty): what it was for, what it
# cost. Worker runs keep their usage on Run; everything that goes through
# ClaudeCli lands here — including board-level calls with no card (deep dive).
class AiCall < ApplicationRecord
  KINDS = %w[assistant ai_task deep_dive summary compact rules_compile].freeze

  belongs_to :card, optional: true

  validates :kind, inclusion: { in: KINDS }
end
