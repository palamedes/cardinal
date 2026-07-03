class StartRunJob < ApplicationJob
  queue_as :default

  def perform(card_id)
    card = Card.find(card_id)
    return unless card.queued? && card.column.execution?
    return if card.column.at_wip_limit? # stays queued; kicked when a slot frees

    session = card.agent_sessions.create!(status: "provisioning", model: card.column.model)
    run = session.runs.create!(status: "queued", briefing: { "card" => card.title, "column" => card.column.name })
    Agent::Runner.new(run).call
  end
end
