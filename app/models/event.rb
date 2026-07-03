class Event < ApplicationRecord
  KINDS = %w[
    user_message agent_message assistant_message
    status_change column_move plan_proposed plan_approved
    question answer progress
    tool_call tool_result artifact_created
    run_started run_finished final_report error
  ].freeze

  # Which timeline zoom level an event first appears at (§7).
  CONVERSATION_KINDS = %w[user_message agent_message assistant_message question answer
                          plan_proposed plan_approved final_report error column_move].freeze

  belongs_to :card
  belongs_to :run, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :actor, presence: true

  scope :conversation, -> { where(kind: CONVERSATION_KINDS) }
  scope :activity, -> { where.not(kind: %w[tool_call tool_result]) }

  def text = payload["text"]
end
