# The two faces of ask-first mode: the shim's API (create/show/auto-deny —
# CSRF-exempt: it's a local process with no session) and the human's verdict
# (answer, from timeline buttons).
class PermissionRequestsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :show, :answer]

  def create
    run = Run.find(params.require(:run_id))
    input = params[:input].respond_to?(:to_unsafe_h) ? params[:input].to_unsafe_h : {}
    request_row = run.permission_requests.create!(
      tool_name: params.require(:tool_name), input: input,
      command: input["command"].presence
    )

    if request_row.auto_allowed?
      request_row.update!(status: "allowed", answered_at: Time.current)
      run.card.log!("status_change", run: run, text: "🔐 Auto-approved #{request_row.describe} (pre-approved pattern)")
    else
      run.card.log!("permission_request", actor: "agent", run: run,
                    request_id: request_row.id, tool: request_row.tool_name,
                    command: request_row.command,
                    text: "🔐 Wants to run #{request_row.describe}")
      run.card.update!(status: "needs_input") if run.card.working?
    end
    render json: { id: request_row.id, status: request_row.status, message: request_row.message }
  end

  def show
    request_row = PermissionRequest.find(params[:id])
    # The blocked claude process is alive and waiting — the shim's poll is its
    # proof of life for the sweeper.
    request_row.run.update_columns(heartbeat_at: Time.current)
    render json: { id: request_row.id, status: request_row.status, message: request_row.message }
  end

  def answer
    request_row = PermissionRequest.find(params[:id])
    if params[:auto] == "1"
      request_row.resolve!("auto_denied", actor: "system")
    elsif params[:verdict] == "allow"
      request_row.resolve!("allowed", always: params[:always] == "1")
    else
      request_row.resolve!("denied", message: params[:message])
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("permission_request_#{request_row.id}",
          partial: "events/permission_request_state", locals: { request: request_row })
      end
      format.json { render json: { ok: true } }
      format.html { redirect_to card_path(request_row.run.card) }
    end
  end
end
