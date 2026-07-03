module Agent
  # Drives one Run: provisions the workspace, spawns the Claude Agent runtime
  # (`claude -p` with JSON streaming) as a supervised subprocess, translates
  # its stream into timeline Events, enforces the column's budget, then pushes
  # the branch and ensures a draft PR (cardinal.md §4, §11, §13).
  class Runner
    STRIP_ENV = %w[ANTHROPIC_API_KEY CLAUDECODE CLAUDE_CODE_ENTRYPOINT GH_TOKEN GITHUB_TOKEN].freeze

    attr_reader :run, :card, :column

    def initialize(run)
      @run = run
      @card = run.card
      @column = card.column
    end

    def call
      run.update!(status: "running", started_at: Time.current)
      card.update!(status: "working")
      card.log!("run_started", run: run, text: "Run ##{run.id} started")

      workspace = Workspace.provision(card)
      base_sha = workspace.head
      result = drive_agent(workspace)
      finish(workspace, base_sha, result)
    rescue => e
      run.update!(status: "failed", finished_at: Time.current, result_summary: e.message)
      card.update!(status: "failed")
      card.log!("error", run: run, text: "Run failed: #{e.message.truncate(500)}")
    ensure
      card.column.kick_queue if card.column.execution?
    end

    private

    def drive_agent(workspace)
      cmd = ["claude", "-p", briefing_prompt,
             "--output-format", "stream-json", "--verbose",
             "--max-turns", (column.max_turns.presence || 25).to_s,
             "--permission-mode", "bypassPermissions"]
      cmd += ["--model", column.model] if column.model.present?
      env = STRIP_ENV.index_with { nil }

      result = {}
      Open3.popen3(env, *cmd, chdir: workspace.path.to_s) do |stdin, stdout, stderr, wait|
        stdin.close
        run.agent_session.update!(status: "ready", config: run.agent_session.config.merge("pid" => wait.pid))
        watchdog = Thread.new do
          sleep (column.timeout_minutes.presence || 30).to_i * 60
          Process.kill("TERM", wait.pid) rescue nil
        end
        err_tail = +""
        drain = Thread.new { stderr.each_line { |l| err_tail = l } }
        stdout.each_line do |line|
          handle_stream_event(JSON.parse(line), result)
        rescue JSON::ParserError
          next
        end
        drain.join(1)
        watchdog.kill
        result[:exit_status] = wait.value
        result[:stderr] = err_tail.strip
      end
      result
    end

    def handle_stream_event(json, result)
      case json["type"]
      when "system"
        card.log!("progress", actor: "agent", run: run, text: "Agent session started (#{json["model"]})") if json["subtype"] == "init"
      when "assistant"
        Array(json.dig("message", "content")).each do |block|
          case block["type"]
          when "text"
            card.log!("progress", actor: "agent", run: run, text: block["text"].to_s.truncate(400)) if block["text"].present?
          when "tool_use"
            card.log!("tool_call", actor: "agent", run: run,
                      text: "#{block["name"]}: #{block["input"].to_json.truncate(160)}")
          end
        end
      when "result"
        result[:success] = json["subtype"] == "success" && !json["is_error"]
        result[:report] = json["result"].to_s
        result[:cost] = json["total_cost_usd"]
        result[:turns] = json["num_turns"]
        result[:input_tokens] = json.dig("usage", "input_tokens")
        result[:output_tokens] = json.dig("usage", "output_tokens")
      end
    end

    def finish(workspace, base_sha, result)
      commits = workspace.commits_since(base_sha)
      run.update!(
        status: result[:success] ? "succeeded" : "failed",
        finished_at: Time.current,
        result_summary: result[:report].presence&.truncate(2000),
        cost: result[:cost] || 0,
        input_tokens: result[:input_tokens] || 0,
        output_tokens: result[:output_tokens] || 0
      )

      unless result[:success]
        card.update!(status: "failed")
        card.log!("error", run: run,
                  text: "Agent did not finish cleanly#{" — #{result[:stderr]}" if result[:stderr].present?} (exit #{result[:exit_status]&.exitstatus})")
        return
      end

      if commits.any?
        workspace.push!
        ensure_pull_request(workspace)
        run.artifacts.create!(kind: "pull_request", name: "PR for #{card.branch_name}",
                              payload: { url: card.pr_url, commits: commits })
      end

      card.log!("final_report", actor: "agent", run: run,
                text: [result[:report].presence || "Run finished with no report.",
                       commits.any? ? "\n**Commits (#{commits.size}):**\n#{commits.map { |c| "- #{c}" }.join("\n")}" : "\n_No commits were made._"].join("\n"))
      card.update!(status: "work_complete")
      card.log!("run_finished", run: run,
                text: "Run succeeded — #{result[:turns]} turns, $#{result[:cost]&.round(2)}")
    end

    def ensure_pull_request(workspace)
      return if card.pr_url.present?
      out, status = Open3.capture2e(
        "gh", "pr", "create", "--draft",
        "--head", card.branch_name,
        "--title", "##{card.number} #{card.title}",
        "--body", "Automated work by Cardinal card ##{card.number}'s agent.\n\n#{card.description}",
        chdir: workspace.path.to_s
      )
      if status.success? && (url = out[%r{https://github\.com/\S+/pull/\d+}])
        card.update!(pr_url: url, pr_state: "draft")
        card.log!("artifact_created", run: run, text: "Draft PR opened: #{url}")
      else
        card.log!("progress", run: run, text: "Branch pushed (PR not created: #{out.truncate(120)})")
      end
    end

    def briefing_prompt
      conversation = card.events.conversation.filter_map { |e| "#{e.actor}: #{e.text}" if e.text }.last(30).join("\n")
      feedback = card.events.where(kind: "user_message").last(5).filter_map(&:text)
      <<~PROMPT
        You are the dedicated worker agent for card ##{card.number} of the Cardinal board: "#{card.title}".

        ## Brief
        #{card.description.presence || "(no description — infer scope from the title and conversation)"}

        ## Card conversation so far
        #{conversation.presence || "(none)"}

        #{"## Column instructions\n#{column.instructions}\n" if column.instructions.present?}
        ## Rules
        - Work only inside this repository checkout (you are already on branch #{card.branch_name}).
        - Commit your work as you go with clear messages. Do NOT push — the runner pushes for you.
        - Stay strictly within the card's scope. If the brief is ambiguous, choose the smallest reasonable interpretation and note the assumption.
        - Finish with a concise report: what you did, what to check, any open questions.
      PROMPT
    end
  end
end
