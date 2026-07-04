class ResumeRunJob < ApplicationJob
  queue_as :default

  # Resumes honor the column's WIP limit like any other start (§8): if the
  # column is full, the answer is recorded and the card rejoins the queue;
  # Column#kick_queue fires the pending resume when a slot frees.
  def perform(run_id, message, approve: false)
    run = Run.find(run_id)
    return unless run.needs_input?
    card = run.card

    if card.column.execution? && card.column.at_wip_limit?
      pending = run.briefing["pending_resume"]
      combined = [pending&.dig("message"), message].compact_blank.join("\n\n")
      run.update!(briefing: run.briefing.merge(
        "pending_resume" => { "message" => combined, "approve" => approve || pending&.dig("approve") || false }
      ))
      card.update!(status: "queued")
      card.log!("status_change", run: run, text: "Answer recorded — waiting for a free agent slot")
      return
    end

    # Atomic claim (§ races): two finishing runs can both kick the queue and
    # double-fire this job — exactly one claimer resumes the session. The
    # claim value is "running", which is what a resume sets anyway.
    return unless Run.where(id: run.id, status: "needs_input")
                     .update_all(status: "running", updated_at: Time.current) == 1
    run.reload

    if (pending = run.briefing["pending_resume"])
      run.update!(briefing: run.briefing.except("pending_resume"))
      message = [pending["message"], message].compact_blank.join("\n\n")
      approve ||= pending["approve"]
    end
    Agent::Runner.resume(run, message, approve: approve)
  end
end
