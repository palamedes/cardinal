class RunsController < ApplicationController
  # Kill switch (cardinal.md §9): TERM the agent subprocess; the runner's
  # failure path records the outcome honestly.
  def cancel
    run = Run.find(params[:id])
    card = run.card
    if run.running? && (pid = run.agent_session.config["pid"])
      Process.kill("TERM", pid) rescue Errno::ESRCH
      run.update!(status: "cancelled", finished_at: Time.current)
      card.update!(status: "failed")
      card.log!("status_change", actor: "user", run: run, text: "Run cancelled by user")
    end
    redirect_to card_path(card)
  end
end
