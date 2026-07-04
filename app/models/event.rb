class Event < ApplicationRecord
  KINDS = %w[
    user_message agent_message assistant_message
    status_change config_change column_move move_rejected plan_proposed plan_approved
    question answer progress
    tool_call tool_result artifact_created
    run_started run_finished final_report error
  ].freeze

  # Which timeline zoom level an event first appears at (§7).
  CONVERSATION_KINDS = %w[user_message agent_message assistant_message question answer
                          plan_proposed plan_approved final_report error
                          column_move move_rejected].freeze

  belongs_to :card
  belongs_to :run, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :actor, presence: true

  scope :conversation, -> { where(kind: CONVERSATION_KINDS) }
  scope :activity, -> { where.not(kind: %w[tool_call tool_result]) }

  # Live-append new events into any open card modal. User-authored events are
  # skipped — they arrive via the form's own redirect re-render.
  after_create_commit -> {
    broadcast_append_to card, target: "card_events", partial: "events/event", locals: { event: self }
  }, unless: -> { actor == "user" }

  # These kinds mean the AI has delivered what the typing indicator promised.
  RESOLVES_THINKING = %w[assistant_message final_report question plan_proposed error].freeze

  # Kinds that change what a card FACE shows (progress lines, thinking chip,
  # replied chip) — the board must morph on these, not just the open modal.
  REFRESHES_BOARD = (%w[progress run_started run_finished] + RESOLVES_THINKING).freeze

  after_create_commit -> { card.broadcast_refresh_to card.board },
                      if: -> { REFRESHES_BOARD.include?(kind) }

  after_create_commit -> { broadcast_remove_to card, target: "typing-indicator" },
                      if: -> { RESOLVES_THINKING.include?(kind) }

  def text = payload["text"]
end
