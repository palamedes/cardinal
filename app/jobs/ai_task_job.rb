# A maintenance agent (cardinal.md §17): one bounded Claude call fired by a
# column rule. The prompt template may reference the card via %{title},
# %{description}, %{conversation}. Output lands on the timeline as an
# assistant_message. Distinct from the worker agent — no workspace, no tools.
class AiTaskJob < ApplicationJob
  queue_as :default

  def perform(card_id, prompt_template, model = nil)
    card = Card.find(card_id)
    return if prompt_template.blank? || ENV["ANTHROPIC_API_KEY"].blank?

    prompt = format(prompt_template,
                    title: card.title,
                    description: card.description.to_s,
                    conversation: card.events.conversation.filter_map(&:text).last(30).join("\n\n"))

    response = Anthropic::Client.new.messages.create(
      model: model.presence || AssistantReplyJob::FALLBACK_MODEL,
      max_tokens: 1024,
      system_: "You are a maintenance agent on a Cardinal board performing one bounded task on card ##{card.number}. Be concise; your output is posted directly to the card's timeline.",
      messages: [{ role: "user", content: prompt }]
    )
    text = response.content.filter_map { |b| b.text if b.type == :text }.join("\n")
    card.log!("assistant_message", actor: "assistant", text: text) if text.present?
  rescue Anthropic::Errors::APIError => e
    card.log!("error", text: "Maintenance agent error: #{e.message}")
  end
end
