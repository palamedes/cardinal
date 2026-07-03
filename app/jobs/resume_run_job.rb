class ResumeRunJob < ApplicationJob
  queue_as :default

  def perform(run_id, message, approve: false)
    run = Run.find(run_id)
    return unless run.needs_input?
    Agent::Runner.resume(run, message, approve: approve)
  end
end
