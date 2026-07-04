class RunsController < ApplicationController
  before_action :set_run

  # Kill switch (cardinal.md §9): TERM the agent subprocess; sweeper and the
  # runner's failure path keep the records honest.
  def cancel
    if run.running? && (pid = run.agent_session.config["pid"])
      Process.kill("TERM", pid) rescue Errno::ESRCH
    end
    if run.running? || run.needs_input?
      run.update!(status: "cancelled", finished_at: Time.current)
      card.update!(status: "failed")
      card.log!("status_change", actor: "user", run: run, text: "Run cancelled by user")
    end
    redirect_to card_path(card)
  end

  # Plan-approval gate (§4): one click sends the agent from plan to execute.
  def approve
    if run.needs_input? && run.phase == "plan"
      card.log!("plan_approved", actor: "user", run: run, text: "Plan approved")
      ResumeRunJob.perform_later(run.id, "", approve: true)
    end

    respond_to do |format|
      # Flash the approval in place, then the dismiss controller minimizes the
      # modal. The run advances asynchronously (ResumeRunJob), so there's no
      # synchronous card state to morph here — just confirm and close.
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("plan-callout", partial: "cards/dismiss_flash",
                                                                  locals: { message: "Plan approved — running…" })
      end
      format.html { redirect_to card_path(card) }
    end
  end

  # Restart a run that parked or failed on its turn budget / timeout. Mirrors
  # Column#kick_queue's branch: resume the saved session for a fresh budget, or
  # (no session left) re-queue for a clean run.
  def restart
    if run.restartable?
      if run.needs_input?
        card.log!("progress", actor: "user", run: run, text: "Restarting run — resuming with a fresh turn budget")
        ResumeRunJob.perform_later(run.id, "")
      elsif run.external_session_id.present?
        # Failed but the session survived: flip back to needs_input so
        # ResumeRunJob's guard passes, then resume it.
        run.update!(status: "needs_input", finished_at: nil)
        card.update!(status: "needs_input")
        card.log!("progress", actor: "user", run: run, text: "Restarting failed run — resuming the saved session with a fresh turn budget")
        ResumeRunJob.perform_later(run.id, "")
      else
        # No session to resume: a clean run from the queue.
        card.update!(status: "queued")
        card.log!("progress", actor: "user", run: run, text: "Restarting failed run — starting a fresh run")
        StartRunJob.perform_later(card.id)
      end
    end
    redirect_to card_path(card)
  end

  private

  attr_reader :run

  def set_run = @run = Run.find(params[:id])
  def card = run.card
end
