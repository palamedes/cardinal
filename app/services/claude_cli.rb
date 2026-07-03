# The single auth path for all of Cardinal's AI (§17): every tier — planning
# assistant, maintenance agents, rules compiler, worker agents — goes through
# the claude CLI, so wherever Claude Code is logged in (or an API key is
# exported), Cardinal works. No separate key provisioning.
#
# This module covers the one-shot tiers; worker agents have their own
# streaming path in Agent::Runner.
module ClaudeCli
  class Error < StandardError
    # Human message in #message; raw technical payload in #detail (shown only
    # behind a disclosure in the timeline).
    attr_reader :detail

    def initialize(message, detail: nil)
      super(message)
      @detail = detail
    end
  end

  # Nested-session guards + creds the model never needs. A blank
  # ANTHROPIC_API_KEY is removed too (it would shadow CLI session auth).
  STRIP_ENV = %w[CLAUDECODE CLAUDE_CODE_ENTRYPOINT GH_TOKEN GITHUB_TOKEN].freeze

  WRAP_UP = "You have hit your exploration limit. Using only what you have already " \
            "learned, give your best complete reply now. Do not use any tools.".freeze

  def self.available?
    return @available if defined?(@available)
    @available = system("which claude > /dev/null 2>&1")
  end

  # tools: comma-separated read-only tool list (e.g. "Read,Glob,Grep") with
  # cwd pointing at the repo. Default remains tool-less single-turn.
  def self.prompt(text, system: nil, model: nil, tools: nil, cwd: nil, max_turns: 1)
    raise Error.new("claude CLI not found on PATH") unless available?

    json = invoke(text, system:, model:, tools:, cwd:, max_turns:)
    return json["result"].to_s if success?(json)

    # Ran out of turns mid-exploration: resume the same session tool-less and
    # force an answer from the context it already gathered.
    if json["subtype"] == "error_max_turns" && json["session_id"].present?
      wrapped = invoke(WRAP_UP, model:, cwd:, tools: "", max_turns: 2, resume: json["session_id"])
      return wrapped["result"].to_s if success?(wrapped)
      raise Error.new("ran out of working turns and couldn't wrap up — try again, or simplify the ask",
                      detail: wrapped.to_json)
    end

    raise Error.new(friendly_failure(json), detail: json.to_json)
  end

  def self.success?(json)
    json["subtype"] == "success" && !json["is_error"]
  end

  def self.friendly_failure(json)
    case json["subtype"]
    when "error_max_turns"        then "ran out of working turns before finishing"
    when "error_during_execution" then "hit an internal error while working"
    else "failed (#{json["subtype"].presence || "unknown error"})"
    end
  end

  def self.invoke(text, system: nil, model: nil, tools: nil, cwd: nil, max_turns: 1, resume: nil)
    cmd = ["claude", "-p", text, "--output-format", "json",
           "--max-turns", max_turns.to_s, "--tools", tools.presence || ""]
    cmd += ["--append-system-prompt", system] if system.present?
    cmd += ["--model", model] if model.present?
    cmd += ["--resume", resume] if resume.present?

    env = STRIP_ENV.index_with { nil }
    env["ANTHROPIC_API_KEY"] = nil if ENV["ANTHROPIC_API_KEY"].blank?

    spawn_opts = cwd.present? && Dir.exist?(cwd) ? { chdir: cwd } : {}
    out, err, status = Open3.capture3(env, *cmd, **spawn_opts)
    JSON.parse(out)
  rescue JSON::ParserError
    raise Error.new("claude produced no readable result (exit #{status&.exitstatus || "?"})",
                    detail: [err, out].compact_blank.join("\n---\n").truncate(1500))
  end
end
