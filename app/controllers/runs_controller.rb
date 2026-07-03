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
    redirect_to card_path(card)
  end

  private

  attr_reader :run

  def set_run = @run = Run.find(params[:id])
  def card = run.card
end
