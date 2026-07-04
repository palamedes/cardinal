require "test_helper"

# § races: starts and resumes are claimed atomically — a double-fired job
# (two finishing runs both kicking the queue) acts exactly once.
class StartRunJobClaimTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @card = create_card(@board, "execution", status: "queued")
  end

  test "double-fired start claims once — one session, one runner start" do
    starts = []
    Agent::Runner.stub(:start, ->(run) { starts << run }) do
      StartRunJob.perform_now(@card.id)
      StartRunJob.perform_now(@card.id)
    end
    assert_equal 1, starts.size
    assert_equal 1, @card.agent_sessions.count
    assert_equal "working", @card.reload.status
  end

  test "a card that lost its claim window is left alone" do
    @card.update!(status: "working") # someone else already claimed it
    Agent::Runner.stub(:start, ->(_) { flunk "must not start" }) do
      StartRunJob.perform_now(@card.id)
    end
    assert_equal 0, @card.agent_sessions.count
  end

  test "double-fired resume claims once" do
    run = create_run(@card, status: "needs_input", phase: "execute")
    resumes = []
    Agent::Runner.stub(:resume, ->(r, _msg, approve: false) { resumes << r }) do
      ResumeRunJob.perform_now(run.id, "go")
      ResumeRunJob.perform_now(run.id, "go")
    end
    assert_equal 1, resumes.size
  end
end

class ShellAccessTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @col = column(@board, "execution")
  end

  test "shell access defaults on; the checkbox turns it off" do
    assert @col.shell_access?
    @col.update!(policy: @col.policy.merge("shell" => false))
    assert_not @col.shell_access?
  end

  test "the gear saves the shell checkbox for execution columns" do
    # Controller path (mirrors the ai checkbox contract: only saved when sent).
    integration = ActionDispatch::Integration::Session.new(Rails.application)
    integration.patch "/columns/#{@col.id}",
      params: { column: { name: @col.name, archetype: "execution", shell: "0" } }
    assert_not @col.reload.shell_access?
    integration.patch "/columns/#{@col.id}",
      params: { column: { name: @col.name, archetype: "execution", shell: "1" } }
    assert @col.reload.shell_access?
  end
end
