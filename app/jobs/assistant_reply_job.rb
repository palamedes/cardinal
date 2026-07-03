# The shared planning assistant (cardinal.md §5): one reply per user message
# on cards sitting in a planning column, via the claude CLI (§ClaudeCli).
# The card's event timeline IS the conversation, embedded as a transcript.
class AssistantReplyJob < ApplicationJob
  queue_as :default

  FALLBACK_MODEL = "claude-haiku-4-5-20251001".freeze

  KICKOFF_TURN = <<~MSG.freeze
    This card just entered the Planning column. Open the discussion: greet me in one short
    sentence, then ask the 2-3 most important clarifying questions that would make THIS
    card execution-ready. Be specific to the card's actual content — never generic. If the
    card is already crystal clear, say so and propose a "Ready for execution" brief instead.
  MSG

  # kickoff: true generates the opening message when a card enters planning.
  def perform(card, kickoff: false)
    unless ClaudeCli.available?
      card.log!("assistant_message", actor: "assistant",
                text: "I'm here to help shape this card. What's the goal, and how will we know it's done? (Install the claude CLI for a smarter assistant.)")
      return
    end

    prompt = kickoff ? KICKOFF_TURN : transcript_prompt(card)
    reply = ClaudeCli.prompt(prompt, system: system_prompt(card),
                             model: card.column.model.presence || FALLBACK_MODEL)
    card.log!("assistant_message", actor: "assistant", text: reply) if reply.present?
  rescue ClaudeCli::Error => e
    card.log!("error", text: "Planning assistant error: #{e.message}")
  end

  private

  def system_prompt(card)
    <<~PROMPT
      You are the planning assistant on Cardinal, a Kanban board where cards become AI \
      worker agents once they enter an execution column. You are helping the user shape \
      card ##{card.number}: "#{card.title}".

      #{"Card description:\n#{card.description}\n" if card.description.present?}
      #{"Column instructions: #{card.column.instructions}\n" if card.column.instructions.present?}
      Your job is to refine this card until it is ready for an execution agent: clarify \
      the goal, surface hidden requirements, bound the scope, and drive toward crisp \
      acceptance criteria. Be concise and concrete — a few sentences or a short list per \
      reply. When the card feels well-defined, offer a short "Ready for execution" brief \
      summarizing goal, scope, and acceptance criteria.
    PROMPT
  end

  def transcript_prompt(card)
    turns = card.events.where(kind: %w[user_message assistant_message]).last(30).map do |event|
      "#{event.kind == "user_message" ? "User" : "You"}: #{event.text}"
    end
    <<~PROMPT
      Conversation so far:

      #{turns.join("\n\n")}

      Reply to the user's latest message as the planning assistant. Output only your reply.
    PROMPT
  end
end
