# Reliability layer (cardinal.md §11): no run may stay "running" without a
# live process behind it. The server boots a sweeper thread (see
# config/initializers/run_sweeper.rb) that fails silent runs and unsticks
# their cards, then re-kicks execution queues.
module RunSweeper
  HEARTBEAT_GRACE = 3.minutes

  def self.sweep
    fail_dead_runs
    repair_stuck_cards
    kick_queues
  end

  def self.fail_dead_runs
    Run.where(status: %w[queued running]).find_each do |run|
      next if alive?(run)
      next if recently_active?(run)

      run.update!(status: "failed", finished_at: Time.current,
                  result_summary: "Runner died without finishing (swept)")
      card = run.card
      if card.working? || card.queued?
        card.update!(status: "failed")
        card.log!("error", run: run, text: "Run ##{run.id} lost its runner process and was marked failed. Retry by dragging the card out and back into the column.")
      end
    end
  end

  # Cards left "working" with no live or recorded run — e.g. a crash between
  # state writes.
  def self.repair_stuck_cards
    Card.where(status: "working").find_each do |card|
      next unless card.column.ai? # non-AI columns: "working" means a human is
      # Same grace as fail_dead_runs: a freshly started run has no pid until
      # AFTER workspace provisioning (clone/fetch) — recency is its proof of
      # life, or every just-dragged card risks a bogus "stuck" verdict.
      next if card.runs.where(status: %w[queued running needs_input])
                  .any? { |r| r.needs_input? || alive?(r) || recently_active?(r) }
      card.update!(status: "failed")
      card.log!("error", text: "Card was stuck working with no live run; marked failed.")
    end
  end

  def self.kick_queues
    Column.where(archetype: "execution").find_each(&:kick_queue)
  end

  # Between state writes (provisioning, spawn) a live run has no pid yet —
  # a recent heartbeat or recent birth counts as alive.
  def self.recently_active?(run)
    (run.heartbeat_at || run.created_at) > HEARTBEAT_GRACE.ago
  end

  def self.alive?(run)
    pid = run.agent_session&.config&.dig("pid")
    return false if pid.blank?
    Process.kill(0, Integer(pid))
    true
  rescue Errno::ESRCH, Errno::EPERM, ArgumentError
    false
  end
end
