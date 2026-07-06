# One "may I run this?" from an agent in ask-first mode (§ permissions). The
# claude process is ALIVE and blocked while this is pending — the MCP shim
# polls for the verdict and the poll keeps the run's heartbeat fresh.
class PermissionRequest < ApplicationRecord
  STATUSES = %w[pending allowed denied auto_denied].freeze

  belongs_to :run

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }

  def pending? = status == "pending"

  def describe
    tool_name == "Bash" && command.present? ? "`#{command.truncate(120)}`" : tool_name
  end

  # The single verdict path — buttons, chat replies, and the shim's timeout
  # all land here. `always` remembers the pattern for the rest of the run.
  def resolve!(verdict, message: nil, always: false, actor: "user")
    return unless pending?

    update!(status: verdict, message: message.presence, answered_at: Time.current)
    card = run.card

    if verdict == "allowed" && always
      pattern = tool_name == "Bash" ? command.to_s : tool_name
      patterns = Array(run.briefing["allowed_patterns"]) | [pattern]
      run.update!(briefing: run.briefing.merge("allowed_patterns" => patterns))
    end

    text =
      case verdict
      when "allowed"     then "🔐 Approved #{describe}#{" — and anything matching it for the rest of this run" if always}"
      when "auto_denied" then "🔐 #{describe} auto-denied (no answer in time) — the agent was told to adapt or park"
      else                    "🔐 Denied #{describe}#{": “#{message}”" if message.present?}"
      end
    card.log!("status_change", actor: actor, run: run, text: text)
    card.update!(status: "working") if card.needs_input? && run.permission_requests.pending.none?
    broadcast_resolution
  end

  # Does an existing pattern (column pre-approved list or earlier
  # allow-for-this-run) already cover this request?
  def auto_allowed?
    patterns = Array(run.card.column.policy["allowed_commands"]) + Array(run.briefing["allowed_patterns"])
    if tool_name == "Bash"
      patterns.any? { |p| p.present? && command.to_s.start_with?(p.strip) }
    else
      patterns.map(&:strip).include?(tool_name)
    end
  end

  private

  # Re-render the timeline callout everywhere (buttons → resolved line).
  def broadcast_resolution
    broadcast_replace_to run.card, target: "permission_request_#{id}",
                         partial: "events/permission_request_state", locals: { request: self }
  end
end
