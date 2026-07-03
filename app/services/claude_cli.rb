# The single auth path for all of Cardinal's AI (§17): every tier — planning
# assistant, maintenance agents, rules compiler, worker agents — goes through
# the claude CLI, so wherever Claude Code is logged in (or an API key is
# exported), Cardinal works. No separate key provisioning.
#
# This module covers the one-shot, tool-less tier; worker agents have their
# own streaming path in Agent::Runner.
module ClaudeCli
  Error = Class.new(StandardError)

  # Nested-session guards + creds the model never needs. A blank
  # ANTHROPIC_API_KEY is removed too (it would shadow CLI session auth).
  STRIP_ENV = %w[CLAUDECODE CLAUDE_CODE_ENTRYPOINT GH_TOKEN GITHUB_TOKEN].freeze

  def self.available?
    return @available if defined?(@available)
    @available = system("which claude > /dev/null 2>&1")
  end

  # tools: comma-separated read-only tool list (e.g. "Read,Glob,Grep") with
  # cwd pointing at the repo — lets the assistant tier ground itself in code.
  # Default remains tool-less single-turn.
  def self.prompt(text, system: nil, model: nil, tools: nil, cwd: nil, max_turns: 1)
    raise Error, "claude CLI not found on PATH" unless available?

    cmd = ["claude", "-p", text, "--output-format", "json",
           "--max-turns", max_turns.to_s, "--tools", tools.presence || ""]
    cmd += ["--append-system-prompt", system] if system.present?
    cmd += ["--model", model] if model.present?

    env = STRIP_ENV.index_with { nil }
    env["ANTHROPIC_API_KEY"] = nil if ENV["ANTHROPIC_API_KEY"].blank?

    spawn_opts = cwd.present? && Dir.exist?(cwd) ? { chdir: cwd } : {}
    out, err, status = Open3.capture3(env, *cmd, **spawn_opts)
    raise Error, "claude exited #{status.exitstatus}: #{err.presence&.truncate(200) || out.truncate(200)}" unless status.success?

    json = JSON.parse(out)
    raise Error, "claude returned an error result: #{json["result"].to_s.truncate(200)}" if json["is_error"]
    json["result"].to_s
  rescue JSON::ParserError
    raise Error, "claude returned unparseable output: #{out.to_s.truncate(200)}"
  end
end
