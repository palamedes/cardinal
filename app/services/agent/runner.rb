module Agent
  # Drives one Run through its phases (cardinal.md §4, §11, §17):
  #
  #   start  → plan phase (read-only, --permission-mode plan) when the column
  #            requires approval, else straight to execute
  #   park   → plan_proposed or QUESTION: → run + card go needs_input
  #   resume → same claude session (--resume) with the user's answer,
  #            approval, or plan feedback
  #   finish → push branch, ensure draft PR, final report, work_complete
  #
  # The subprocess is the Claude Agent runtime (`claude -p`, stream-json).
  # Heartbeats are written while streaming; RunSweeper reaps silent runs.
  class Runner
    STRIP_ENV = %w[ANTHROPIC_API_KEY CLAUDECODE CLAUDE_CODE_ENTRYPOINT GH_TOKEN GITHUB_TOKEN].freeze
    HEARTBEAT_EVERY = 10 # seconds

    EXECUTE_RULES = <<~RULES.freeze
      ## Rules
      - You have the FULL toolset now: shell (bash, git), file editing, everything. Run
        commands yourself — never ask who should run them.
      - Work only inside this repository checkout (you are already on the card's branch).
      - If the branch conflicts with origin's default branch, merge it into the card
        branch yourself and resolve the conflicts as part of the work.
      - Commit your work as you go with clear messages. Do NOT push — the runner pushes for you.
      - Stay strictly within the card's scope. Prefer the smallest reasonable interpretation and note assumptions.
      - If you are blocked on a decision only the user can make, output a single line starting with
        "QUESTION:" followed by the question, then stop immediately. Do not guess on genuinely ambiguous choices.
      - Finish with a concise report: what you did, what to check, any open questions.
    RULES

    def self.start(run) = new(run).start
    def self.resume(run, message, approve: false) = new(run).resume(message, approve: approve)

    attr_reader :run, :card, :column

    def initialize(run)
      @run = run
      @card = run.card
      @column = card.column
    end

    def start
      begin_segment!(first: true)
      if plan_gated?
        run.update!(phase: "plan")
        stream_agent(prompt: plan_prompt, mode: "plan")
      else
        stream_agent(prompt: briefing_prompt, mode: "execute")
      end
    rescue => e
      record_failure(e)
    ensure
      column.kick_queue if column.execution?
    end

    def resume(message, approve: false)
      begin_segment!
      if run.phase == "plan" && approve
        run.update!(phase: "execute")
        stream_agent(prompt: "Your plan is approved — execute it now.\n\n#{EXECUTE_RULES}",
                     mode: "execute", resuming: true)
      elsif run.phase == "plan"
        stream_agent(prompt: "Feedback on your plan:\n\n#{message}\n\nRevise the plan accordingly, present it, and stop again for approval. Stay in read-only mode.",
                     mode: "plan", resuming: true)
      else
        stream_agent(prompt: "Answer from the user:\n\n#{message}\n\nContinue the work. The same rules apply (commit, don't push, QUESTION: if blocked again, final report when done).",
                     mode: "execute", resuming: true)
      end
    rescue => e
      record_failure(e)
    ensure
      column.kick_queue if column.execution?
    end

    private

    def plan_gated?
      ActiveModel::Type::Boolean.new.cast(column.plan_approval)
    end

    def begin_segment!(first: false)
      run.update!(status: "running", started_at: run.started_at || Time.current, heartbeat_at: Time.current)
      card.update!(status: "working")
      if first
        card.log!("run_started", run: run, text: "Run ##{run.id} started")
      else
        card.log!("progress", actor: "agent", run: run, text: "Run resumed")
      end
    end

    def stream_agent(prompt:, mode:, resuming: false)
      workspace = resuming ? Workspace.attach(card) : Workspace.provision(card)
      remember_base_sha(workspace) if mode == "execute"

      cmd = ["claude", "-p", prompt, "--output-format", "stream-json", "--verbose",
             "--permission-mode", "bypassPermissions"]
      if mode == "plan"
        # Read-only exploration for the plan phase. (--permission-mode plan
        # hangs headless: ExitPlanMode waits for an approval that never comes.)
        cmd += ["--max-turns", "10", "--tools", "Read,Glob,Grep"]
      else
        cmd += ["--max-turns", (column.max_turns.presence || 25).to_s]
      end
      cmd += ["--model", column.model] if column.model.present?
      cmd += ["--effort", column.effort] if column.effort.present?
      cmd += ["--resume", run.external_session_id] if resuming && run.external_session_id.present?

      result = {}
      @base_in, @base_out = run.input_tokens, run.output_tokens
      @seg_in = @seg_out = 0
      env = STRIP_ENV.index_with { nil }
      spawn_cmd, spawn_opts = workspace.agent_spawn(cmd)
      Open3.popen3(env, *spawn_cmd, **spawn_opts) do |stdin, stdout, stderr, wait|
        stdin.close
        run.agent_session.update!(status: "ready", config: run.agent_session.config.merge("pid" => wait.pid))
        timeout_min = (column.timeout_minutes.presence || 30).to_i
        watchdog = Thread.new do
          sleep timeout_min * 60
          @timed_out = true
          Process.kill("TERM", wait.pid) rescue nil
        end
        err_lines = []
        drain = Thread.new { stderr.each_line { |l| err_lines << l.strip; err_lines.shift while err_lines.size > 4 } }
        last_beat = Time.current
        stdout.each_line do |line|
          if Time.current - last_beat > HEARTBEAT_EVERY
            # Heartbeat + live token tally: tokens survive even if this
            # segment is killed before its result event.
            run.update_columns(heartbeat_at: Time.current,
                               input_tokens: @base_in + @seg_in,
                               output_tokens: @base_out + @seg_out)
            last_beat = Time.current
          end
          begin
            handle_stream_event(JSON.parse(line), result)
          rescue JSON::ParserError
            next
          end
        end
        drain.join(1)
        watchdog.kill
        result[:exit_status] = wait.value
        result[:stderr] = err_lines.join(" | ")
        result[:timed_out] = @timed_out
        result[:timeout_min] = timeout_min
      end

      mode == "plan" ? conclude_plan(result) : conclude_execute(workspace, result)
    end

    def handle_stream_event(json, result)
      case json["type"]
      when "system"
        if json["subtype"] == "init"
          run.update_columns(external_session_id: json["session_id"]) if json["session_id"].present?
          card.log!("progress", actor: "agent", run: run, text: "Agent session started (#{json["model"]})")
        end
      when "assistant"
        if (usage = json.dig("message", "usage"))
          @seg_in += usage["input_tokens"].to_i
          @seg_out += usage["output_tokens"].to_i
        end
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

    def conclude_plan(result)
      accumulate_usage(result)
      unless result[:success] && result[:report].present?
        return record_failure(RuntimeError.new("plan phase failed — #{failure_reason(result)}"))
      end
      park!("plan_proposed", result[:report],
            note: "Plan proposed — approve it in the work panel, or reply to redirect.")
    end

    def conclude_execute(workspace, result)
      accumulate_usage(result)
      unless result[:success]
        salvage_commits(workspace)
        return record_failure(RuntimeError.new(failure_reason(result)))
      end

      report = result[:report].to_s
      if report.lstrip.start_with?("QUESTION:")
        return park!("question", report.lstrip.delete_prefix("QUESTION:").strip,
                     note: "Agent is waiting on your answer — reply on the card.")
      end

      commits = workspace.commits_since(base_sha)
      if commits.any?
        workspace.push!
        ensure_pull_request(workspace)
        run.artifacts.create!(kind: "pull_request", name: "PR for #{card.branch_name}",
                              payload: { url: card.pr_url, commits: commits })
      elsif card.pr_url.blank? && workspace.ahead_of_default?
        # No new commits this run, but the branch carries earlier work (e.g. a
        # salvage commit) that still needs a PR.
        workspace.push!
        ensure_pull_request(workspace)
      end

      run.update!(status: "succeeded", finished_at: Time.current,
                  result_summary: report.presence&.truncate(2000))
      card.log!("final_report", actor: "agent", run: run,
                text: [report.presence || "Run finished with no report.",
                       commits.any? ? "\n**Commits (#{commits.size}):**\n#{commits.map { |c| "- #{c}" }.join("\n")}" : "\n_No commits were made._"].join("\n"))
      card.update!(status: "work_complete")
      card.log!("run_finished", run: run,
                text: "Run succeeded — #{result[:turns]} turns, $#{run.cost.round(2)} total")
    end

    def park!(kind, text, note:)
      run.update!(status: "needs_input")
      card.log!(kind, actor: "agent", run: run, text: text)
      card.update!(status: "needs_input")
      card.log!("status_change", run: run, text: note)
    end

    # Say WHY, not just that it died: timeout vs error result vs crash.
    def failure_reason(result)
      return "timed out after #{result[:timeout_min]} minutes and was stopped — raise the column's timeout for bigger tasks, or split the card" if result[:timed_out]
      parts = ["agent did not finish cleanly (exit #{result[:exit_status]&.exitstatus || "?"})"]
      parts << "last output: #{result[:report].truncate(300)}" if result[:report].present?
      parts << "stderr: #{result[:stderr].truncate(300)}" if result[:stderr].present?
      parts.join(" — ")
    end

    # A failed/timed-out segment may still hold real local commits; push them
    # so the branch (and any PR) keeps the partial progress instead of the
    # next provision's reset wiping it.
    def salvage_commits(workspace)
      commits = workspace.commits_since(base_sha)
      return if commits.empty?
      workspace.push!
      card.log!("progress", run: run, text: "Partial work preserved: #{commits.size} commit(s) pushed to #{card.branch_name} before failure")
    rescue => e
      card.log!("progress", run: run, text: "Could not preserve partial work: #{e.message.truncate(120)}")
    end

    def record_failure(error)
      run.update!(status: "failed", finished_at: Time.current,
                  result_summary: error.message.truncate(500))
      card.update!(status: "failed")
      card.log!("error", run: run, text: "Run failed: #{error.message.truncate(500)}")
    end

    # Cost/tokens accumulate across segments of the same run (plan + execute +
    # resumes). Tokens were live-tallied during the stream; the result event's
    # figures are authoritative when present, the live tally is the fallback
    # for killed segments (which never emit a result).
    def accumulate_usage(result)
      base_in = @base_in || run.input_tokens
      base_out = @base_out || run.output_tokens
      run.update!(cost: run.cost + (result[:cost] || 0),
                  input_tokens: base_in + (result[:input_tokens] || @seg_in || 0),
                  output_tokens: base_out + (result[:output_tokens] || @seg_out || 0))
      @base_in = @base_out = @seg_in = @seg_out = nil
    end

    def remember_base_sha(workspace)
      return if run.briefing["base_sha"].present?
      run.update!(briefing: run.briefing.merge("base_sha" => workspace.head))
    end

    def base_sha = run.briefing.fetch("base_sha")

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
      <<~PROMPT
        You are the dedicated worker agent for card ##{card.number} of the Cardinal board: "#{card.title}".

        ## Brief
        #{card.description.presence || "(no description — infer scope from the title and conversation)"}

        #{"## Brief from planning (authoritative — refined with the user)\n#{planning_brief}\n" if planning_brief}
        ## Card conversation so far
        #{conversation_excerpt.presence || "(none)"}

        #{"## Column instructions\n#{column.instructions}\n" if column.instructions.present?}
        #{EXECUTE_RULES}
      PROMPT
    end

    def plan_prompt
      <<~PROMPT
        You are the dedicated worker agent for card ##{card.number} of the Cardinal board: "#{card.title}".
        You are in READ-ONLY PLAN MODE. Do not modify anything yet.

        ## Brief
        #{card.description.presence || "(no description — infer scope from the title and conversation)"}

        #{"## Brief from planning (authoritative — refined with the user)\n#{planning_brief}\n" if planning_brief}
        ## Card conversation so far
        #{conversation_excerpt.presence || "(none)"}

        #{"## Column instructions\n#{column.instructions}\n" if column.instructions.present?}
        Explore the repository as needed, then present a short numbered plan-of-attack
        (files you'll touch, approach, how you'll verify) and stop. The user will approve
        or redirect before any changes are made.

        IMPORTANT: you are read-only ONLY during this planning pass. Once the plan is
        approved you will have the full toolset — shell, git, file editing — in this same
        session. Plan every step as something YOU will do (including git merges and
        running commands); never ask who should run a command or plan around not having
        a shell.
      PROMPT
    end

    # The planning assistant's distilled "Ready for execution" brief, if the
    # conversation produced one — the most load-bearing artifact of planning.
    def planning_brief
      return @planning_brief if defined?(@planning_brief)
      @planning_brief = card.events.where(kind: "assistant_message")
                            .order(:id).filter_map(&:text).reverse
                            .find { |t| t.match?(/ready for execution/i) }
    end

    def conversation_excerpt
      card.events.conversation.filter_map { |e| "#{e.actor}: #{e.text}" if e.text }.last(30).join("\n")
    end
  end
end
