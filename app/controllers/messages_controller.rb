class MessagesController < ApplicationController
  def create
    card = Board.first!.cards.find_by!(number: params[:card_id])
    text = params.require(:message)[:text]
    parked_run = card.runs.where(status: "needs_input").order(:id).last
    live_run = card.runs.where(status: "running").order(:id).last

    if params.dig(:message, :note) == "1"
      # Note only (card #47): on the record for any FUTURE reader — the next
      # column's assistant or worker sees it in conversation context — but no
      # AI is invoked now and no verdict changes. Type, drag, done.
      card.log!("user_message", actor: "user", text: text, note: true)
    elsif parked_run
      # Answer / plan feedback: goes back into the same agent session.
      kind = parked_run.phase == "plan" ? "user_message" : "answer"
      card.log!(kind, actor: "user", run: parked_run, text: text)
      ResumeRunJob.perform_later(parked_run.id, text)
    elsif card.column.execution? && card.working? && live_run
      # Mid-run steering (card #47): the run is streaming and can't hear you
      # yet — queue the note on the run; it delivers at the next segment
      # boundary (question, plan approval, budget pause) via ResumeRunJob.
      notes = Array(live_run.briefing["steering"]) << text
      live_run.update!(briefing: live_run.briefing.merge("steering" => notes))
      card.log!("user_message", actor: "user", run: live_run, text: text)
      card.log!("status_change", run: live_run,
                text: "🧭 Note queued for the agent — delivers at its next check-in")
    elsif card.column.review? && %w[in_review approved].include?(card.status)
      # Review is entirely human: feedback IS the conversation. A message on a
      # card under review marks it changes_requested; dragging it back to a
      # work column carries the feedback into the next run's briefing.
      card.log!("user_message", actor: "user", text: text)
      card.update!(status: "changes_requested")
      card.log!("status_change", actor: "user", text: "Changes requested — drag the card back to a work column when ready")
    else
      card.log!("user_message", actor: "user", text: text)
      AssistantReplyJob.perform_later(card) if card.column.planning? && card.column.ai?
    end
    redirect_to card_path(card)
  end
end
