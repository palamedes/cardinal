require "test_helper"

class RunnerTest < ActiveSupport::TestCase
  class FakeWorkspace
    attr_reader :pushed
    def initialize(commits, ahead: false) = (@commits, @ahead = commits, ahead)
    def commits_since(_) = @commits
    def push! = @pushed = true
    def head = "abc123"
    def ahead_of_default? = @ahead
  end

  setup do
    @board = create_board
    @card = create_card(@board, "execution", status: "working",
                        branch_name: "cardinal/1-test", description: "Do the thing")
    @run = create_run(@card, briefing: { "base_sha" => "base" })
    @runner = Agent::Runner.new(@run)
  end

  test "stream init captures the claude session id" do
    @runner.send(:handle_stream_event,
                 { "type" => "system", "subtype" => "init", "session_id" => "sess-123", "model" => "sonnet" }, {})
    assert_equal "sess-123", @run.reload.external_session_id
    assert_equal 1, @card.events.where(kind: "progress").count
  end

  test "assistant text and tool_use become timeline events" do
    json = { "type" => "assistant", "message" => { "content" => [
      { "type" => "text", "text" => "Working on it" },
      { "type" => "tool_use", "name" => "Edit", "input" => { "file" => "a.rb" } }
    ] } }
    @runner.send(:handle_stream_event, json, {})
    assert_equal 1, @card.events.where(kind: "progress").count
    assert_equal 1, @card.events.where(kind: "tool_call").count
  end

  test "result event fills the result hash" do
    result = {}
    @runner.send(:handle_stream_event,
                 { "type" => "result", "subtype" => "success", "is_error" => false,
                   "result" => "Done.", "total_cost_usd" => 0.5, "num_turns" => 3,
                   "usage" => { "input_tokens" => 10, "output_tokens" => 20 } }, result)
    assert result[:success]
    assert_equal "Done.", result[:report]
    assert_equal 0.5, result[:cost]
  end

  test "QUESTION report parks run and card as needs_input" do
    @runner.send(:conclude_execute, FakeWorkspace.new([]),
                 { success: true, report: "QUESTION: apples or oranges?" })
    assert_equal "needs_input", @run.reload.status
    assert_equal "needs_input", @card.reload.status
    assert_equal "apples or oranges?", @card.events.where(kind: "question").last.text
  end

  test "successful execute with commits pushes and completes" do
    ws = FakeWorkspace.new(["abc fix thing"])
    @runner.define_singleton_method(:ensure_pull_request) { |_| } # skip gh
    @runner.send(:conclude_execute, ws, { success: true, report: "All done", turns: 4, cost: 0.2 })
    assert ws.pushed
    assert_equal "succeeded", @run.reload.status
    assert_equal "work_complete", @card.reload.status
    assert_match(/All done/, @card.events.where(kind: "final_report").last.text)
  end

  test "successful execute with no commits skips push" do
    ws = FakeWorkspace.new([])
    @runner.send(:conclude_execute, ws, { success: true, report: "Nothing to do" })
    assert_nil ws.pushed
    assert_equal "work_complete", @card.reload.status
  end

  test "plan success parks with plan_proposed" do
    @run.update!(phase: "plan")
    @runner.send(:conclude_plan, { success: true, report: "1. Do X\n2. Do Y" })
    assert_equal "needs_input", @run.reload.status
    assert_equal "needs_input", @card.reload.status
    assert_match(/Do X/, @card.events.where(kind: "plan_proposed").last.text)
  end

  test "failed result marks run and card failed" do
    @runner.send(:conclude_execute, FakeWorkspace.new([]), { success: false, stderr: "boom" })
    assert_equal "failed", @run.reload.status
    assert_equal "failed", @card.reload.status
  end

  test "usage accumulates across segments" do
    @runner.send(:accumulate_usage, { cost: 0.1, input_tokens: 5, output_tokens: 7 })
    @runner.send(:accumulate_usage, { cost: 0.2, input_tokens: 5, output_tokens: 3 })
    assert_in_delta 0.3, @run.reload.cost.to_f
    assert_equal 10, @run.output_tokens
  end
end

class RunnerBriefingTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @card = create_card(@board, "execution", status: "queued", branch_name: "cardinal/9-t",
                        description: "Do the thing")
    @run = create_run(@card, status: "queued")
  end

  test "planning conversation flows into both prompts" do
    @card.log!("user_message", actor: "user", text: "must support dark mode")
    runner = Agent::Runner.new(@run)
    assert_match(/must support dark mode/, runner.send(:briefing_prompt))
    assert_match(/must support dark mode/, runner.send(:plan_prompt))
  end

  test "a ready-for-execution brief is promoted to its own section" do
    @card.log!("assistant_message", actor: "assistant", text: "Chatter about stuff")
    @card.log!("assistant_message", actor: "assistant",
               text: "Ready for execution: add a dark mode toggle to settings; acceptance: persists per user.")
    prompt = Agent::Runner.new(@run).send(:briefing_prompt)
    assert_match(/## Brief from planning/, prompt)
    assert_match(/dark mode toggle to settings/, prompt)
  end

  test "no brief section when planning never converged" do
    @card.log!("assistant_message", actor: "assistant", text: "Just chatting")
    assert_no_match(/Brief from planning/, Agent::Runner.new(@run).send(:briefing_prompt))
  end

  test "repo brief is injected ahead of the planning brief in both prompts" do
    @card.log!("assistant_message", actor: "assistant",
               text: "Ready for execution: build the thing; acceptance: it works.")
    runner = Agent::Runner.new(@run)
    board = runner.instance_variable_get(:@card).board
    board.define_singleton_method(:repo_brief) { "## Overview\nA Rails app." }

    %i[briefing_prompt plan_prompt].each do |which|
      prompt = runner.send(which)
      assert_match(/## Repo brief\n## Overview\nA Rails app\./, prompt)
      assert_operator prompt.index("## Repo brief"), :<, prompt.index("## Brief from planning"),
                      "repo brief should precede the planning brief in #{which}"
    end
  end

  test "no repo brief section when there is no brief" do
    runner = Agent::Runner.new(@run)
    runner.instance_variable_get(:@card).board.define_singleton_method(:repo_brief) { nil }
    assert_no_match(/## Repo brief/, runner.send(:briefing_prompt))
  end
end

class RunnerSalvagePrTest < ActiveSupport::TestCase
  test "a no-commit success with a branch ahead of default still ensures the PR" do
    board = create_board
    card = create_card(board, "execution", status: "working", branch_name: "cardinal/9-x")
    run = create_run(card, briefing: { "base_sha" => "base" })
    runner = Agent::Runner.new(run)
    ws = RunnerTest::FakeWorkspace.new([], ahead: true)
    called = false
    runner.define_singleton_method(:ensure_pull_request) { |_| called = true }
    runner.send(:conclude_execute, ws, { success: true, report: "verified" })
    assert ws.pushed
    assert called
  end
end

class RunnerBudgetTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @card = create_card(@board, "execution", status: "working", branch_name: "cardinal/9-b")
    @run = create_run(@card, briefing: { "base_sha" => "base" })
    @run.update!(external_session_id: "sess-77")
    @runner = Agent::Runner.new(@run)
  end

  test "execute turn-cap parks with a continue question instead of failing" do
    ws = RunnerTest::FakeWorkspace.new(["abc partial work"])
    @runner.define_singleton_method(:ensure_pull_request) { |_| }
    @runner.send(:conclude_execute, ws, { success: false, subtype: "error_max_turns" })
    assert_equal "needs_input", @run.reload.status
    assert_equal "needs_input", @card.reload.status
    assert_match(/fresh budget/, @card.events.where(kind: "question").last.text)
    assert ws.pushed # partial commits salvaged
  end

  test "plan turn-cap triggers one tool-less wrap-up segment" do
    @run.update!(phase: "plan")
    wrapped = []
    @runner.define_singleton_method(:stream_agent) { |**kw| wrapped << kw }
    @runner.send(:conclude_plan, { success: false, subtype: "error_max_turns" })
    assert_equal 1, wrapped.size
    assert_equal "plan_wrap", wrapped.first[:mode]
    assert wrapped.first[:resuming]
  end

  test "plan wrap-up failing a second time records failure" do
    @run.update!(phase: "plan")
    @runner.instance_variable_set(:@plan_wrap_attempted, true)
    @runner.send(:conclude_plan, { success: false, subtype: "error_max_turns" })
    assert_equal "failed", @run.reload.status
  end
end
