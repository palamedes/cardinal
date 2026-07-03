require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @card = create_card(@board, "execution", branch_name: "cardinal/1-test")
  end

  test "defaults to the local strategy" do
    assert_equal Agent::Workspace::Local, Agent::Workspace.strategy
  end

  test "container strategy is env opt-in" do
    ENV["CARDINAL_WORKSPACE"] = "container"
    assert_equal Agent::Workspace::Container, Agent::Workspace.strategy
  ensure
    ENV.delete("CARDINAL_WORKSPACE")
  end

  test "local spawn runs in the checkout" do
    ws = Agent::Workspace::Local.new(@card)
    cmd, opts = ws.agent_spawn(["claude", "-p", "hi"])
    assert_equal ["claude", "-p", "hi"], cmd
    assert_equal ws.path.to_s, opts[:chdir]
  end

  test "container spawn wraps the command in docker run with the checkout mounted" do
    ws = Agent::Workspace::Container.new(@card)
    cmd, opts = ws.agent_spawn(["claude", "-p", "hi"])
    assert_equal "docker", cmd.first
    assert_includes cmd, "#{ws.path}:#{Agent::Workspace::Container::WORKDIR}"
    assert_includes cmd, "cardinal-card-#{@card.number}"
    assert_equal ["claude", "-p", "hi"], cmd.last(3)
    assert_empty opts
  end
end
