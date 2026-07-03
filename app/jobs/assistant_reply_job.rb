# The shared planning assistant (cardinal.md §5): one reply per user message on
# cards sitting in a planning column. Stateless between calls — the card's event
# timeline IS the conversation.
class AssistantReplyJob < ApplicationJob
  queue_as :default

  FALLBACK_MODEL = "claude-haiku-4-5-20251001".freeze

  def perform(card)
    unless ENV["ANTHROPIC_API_KEY"].present?
      card.log!("assistant_message", actor: "assistant",
                text: "I can't reach the Claude API — set ANTHROPIC_API_KEY in Cardinal's environment and message me again.")
      return
    end

    card.log!("assistant_message", actor: "assistant", text: request_reply(card))
  rescue Anthropic::Errors::APIError => e
    card.log!("error", text: "Planning assistant error: #{e.message}")
  end

  private

  def request_reply(card)
    client = Anthropic::Client.new
    response = client.messages.create(
      model: card.column.model.presence || FALLBACK_MODEL,
      max_tokens: 1024,
      system_: system_prompt(card),
      messages: conversation(card)
    )
    response.content.filter_map { |block| block.text if block.type == :text }.join("\n")
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
    PROMPT
  end

  # The API requires alternating roles; merge consecutive same-role messages
  # (e.g. two user messages sent before a reply landed).
  def conversation(card)
    turns = card.events.where(kind: %w[user_message assistant_message]).map do |event|
      { role: event.kind == "user_message" ? "user" : "assistant", content: event.text.to_s }
    end
    turns.chunk_while { |a, b| a[:role] == b[:role] }.map do |chunk|
      { role: chunk.first[:role], content: chunk.map { |t| t[:content] }.join("\n\n") }
    end
  end
end
