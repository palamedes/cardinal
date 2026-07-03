# The shared planning assistant (cardinal.md §5): a CONTINUING claude session
# per card (assistant_session_id) — context and repo exploration carry across
# replies instead of being re-paid per message. Falls back to a fresh session
# (with the transcript embedded) if the stored session can't be resumed.
class AssistantReplyJob < ApplicationJob
  queue_as :default

  FALLBACK_MODEL = "claude-haiku-4-5-20251001".freeze
  MAX_TURNS = 20

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

    reply, session_id = converse(card, kickoff:)
    card.update!(assistant_session_id: session_id) if session_id.present?
    card.log!("assistant_message", actor: "assistant", text: reply) if reply.present?
  rescue ClaudeCli::Error => e
    card.log!("error", text: "The planning assistant #{e.message}.", detail: e.detail)
  end

  private

  def converse(card, kickoff:)
    repo = card.board.local_path.presence
    common = { model: card.column.model.presence || FALLBACK_MODEL,
               tools: repo ? "Read,Glob,Grep" : nil,
               cwd: repo, max_turns: MAX_TURNS, with_session: true }

    if !kickoff && card.assistant_session_id.present?
      begin
        # Continuing conversation: just the new message — the session already
        # holds the system prompt, the history, and everything it explored.
        return ClaudeCli.prompt(latest_user_message(card), resume: card.assistant_session_id, **common)
      rescue ClaudeCli::Error
        card.update!(assistant_session_id: nil) # stale/expired — start fresh below
      end
    end

    ClaudeCli.prompt(kickoff ? KICKOFF_TURN : transcript_prompt(card),
                     system: system_prompt(card), **common)
  end

  def latest_user_message(card)
    card.events.where(kind: "user_message").order(:id).last&.text.to_s
  end

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

      #{"You have READ-ONLY access to the board's repository (Read/Glob/Grep; you are in \
      its root). Ground your questions and advice in the actual code whenever relevant — \
      check what exists before asking about it. Never promise to look at something later: \
      you cannot act between replies, so look NOW, within this turn, then answer." if card.board.local_path.present?}
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
