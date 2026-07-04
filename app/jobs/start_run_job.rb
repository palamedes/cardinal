class StartRunJob < ApplicationJob
  queue_as :default

  def perform(card_id)
    card = Card.find(card_id)
    column = card.column
    return unless column.execution? && column.ai?
    return if column.at_wip_limit? # stays queued; kicked when a slot frees

    # Atomic claim (§ races): two kicks can enqueue this job twice for the
    # same card; exactly one claimer flips queued→working, the rest no-op.
    return unless Card.where(id: card.id, status: "queued")
                      .update_all(status: "working", updated_at: Time.current) == 1
    card.reload.touch # update_all skips callbacks — nudge the board broadcast

    # Re-check AFTER claiming: claims are atomic, so an over-subscribed slot
    # shows up as strictly more running than allowed and the loser un-claims
    # back into the queue (the next kick retries it).
    if column.at_wip_limit_exceeded?
      card.update!(status: "queued")
      return
    end

    session = card.agent_sessions.create!(status: "provisioning", model: column.model)
    run = session.runs.create!(status: "queued", briefing: { "card" => card.title, "column" => column.name })
    Agent::Runner.start(run)
  end
end
