require "test_helper"

# Ask-first permission mode (§ permissions): the agent pauses, the human
# answers by button or chat, patterns pre-approve the boring stuff.
class PermissionRequestsTest < ActionDispatch::IntegrationTest
  setup do
    @board = create_board
    @card = create_card(@board, "execution", status: "working")
    session = @card.agent_sessions.create!(status: "ready")
    @run = session.runs.create!(status: "running", phase: "execute", briefing: {})
  end

  test "the shim's create parks the card with a permission_request event" do
    post permission_requests_path, params: {
      run_id: @run.id, tool_name: "Bash", input: { command: "bundle exec rails test" }
    }, as: :json
    body = JSON.parse(response.body)
    assert_equal "pending", body["status"]
    assert_equal "needs_input", @card.reload.status
    event = @card.events.where(kind: "permission_request").last
    assert_equal body["id"], event.payload["request_id"]
  end

  test "column pre-approved patterns auto-allow without parking" do
    @card.column.update!(policy: @card.column.policy.merge("allowed_commands" => ["bundle exec rails test"]))
    post permission_requests_path, params: {
      run_id: @run.id, tool_name: "Bash", input: { command: "bundle exec rails test test/models" }
    }, as: :json
    assert_equal "allowed", JSON.parse(response.body)["status"]
    assert_equal "working", @card.reload.status
    assert_match(/Auto-approved/, @card.events.last.payload["text"])
  end

  test "allow-always remembers the pattern for the rest of the run" do
    req = @run.permission_requests.create!(tool_name: "Bash", command: "git commit -m x",
                                           input: { "command" => "git commit -m x" })
    post answer_permission_request_path(req, verdict: "allow", always: "1")
    assert_equal "allowed", req.reload.status
    assert_includes @run.reload.briefing["allowed_patterns"], "git commit -m x"

    follow_up = @run.permission_requests.new(tool_name: "Bash", command: "git commit -m y",
                                             input: { "command" => "git commit -m y" })
    assert_not follow_up.auto_allowed? # prefix match is exact-command based
    starts_with = @run.permission_requests.new(tool_name: "Bash", command: "git commit -m x --amend",
                                               input: {})
    assert starts_with.auto_allowed?
  end

  test "the shim's poll heartbeats the run" do
    req = @run.permission_requests.create!(tool_name: "Bash", command: "ls", input: {})
    @run.update_columns(heartbeat_at: 10.minutes.ago)
    get permission_request_path(req), headers: { "Accept" => "application/json" }
    assert_operator @run.reload.heartbeat_at, :>, 1.minute.ago
  end

  test "a chat reply is the verdict: yes approves, anything else denies with the reason" do
    yes_req = @run.permission_requests.create!(tool_name: "Bash", command: "ls", input: {})
    @card.update!(status: "needs_input")
    post card_messages_path(@card), params: { message: { text: "yes" } }
    assert_equal "allowed", yes_req.reload.status
    assert_equal "working", @card.reload.status

    deny_req = @run.permission_requests.create!(tool_name: "Bash", command: "rm -rf tmp", input: {})
    post card_messages_path(@card), params: { message: { text: "no — use rails tmp:clear instead" } }
    deny_req.reload
    assert_equal "denied", deny_req.status
    assert_match(/rails tmp:clear/, deny_req.message)
  end

  test "the shim's timeout auto-denies without CSRF" do
    req = @run.permission_requests.create!(tool_name: "Bash", command: "ls", input: {})
    post answer_permission_request_path(req, auto: "1"), headers: { "Accept" => "application/json" }
    assert_equal "auto_denied", req.reload.status
  end
end

class PermissionModeResolutionTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @card = create_card(@board, "execution", status: "queued")
  end

  test "board tri-mode resolves with back-compat and card override" do
    assert_equal "bypass", @card.effective_permission_mode
    @board.update!(settings: { "permission_mode" => "ask" })
    assert_equal "ask", @card.reload.effective_permission_mode
    @board.update!(settings: { "permission_bypass" => false }) # legacy boolean
    assert_equal "restricted", @card.reload.effective_permission_mode
    @card.update!(permission_mode: "ask")
    assert_equal "ask", @card.effective_permission_mode
  end

  test "runner picks ask rules and flags only when the column allows shell" do
    @board.update!(settings: { "permission_mode" => "ask" })
    run = create_run(@card.reload)
    runner = Agent::Runner.new(run)
    assert runner.send(:ask_mode?)
    assert_not runner.send(:restricted_tools?)
    assert_match(/PAUSE for the user's approval/, runner.send(:execute_rules))
    config = JSON.parse(runner.send(:permission_shim_config))
    assert_equal run.id.to_s, config.dig("mcpServers", "cardinal", "env", "CARDINAL_RUN_ID")
    assert config.dig("mcpServers", "cardinal", "args").first.end_with?("permission_shim.rb")

    @card.column.update!(policy: @card.column.policy.merge("shell" => false))
    assert_not Agent::Runner.new(create_run(@card.reload)).send(:ask_mode?),
               "shell-off column can never be ask mode"
  end
end
