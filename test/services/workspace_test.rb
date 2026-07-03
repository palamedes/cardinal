require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @card = create_card(@board, "execution", status: "queued", branch_name: "cardinal/1-test")
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

class WorkspaceSalvageTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::Isolation if false # plain test

  test "provision salvages a dirty tree as a WIP commit instead of failing" do
    Dir.mktmpdir do |origin|
      system("git", "init", "-qb", "main", origin)
      File.write(File.join(origin, "a.txt"), "hello")
      system("git", "-C", origin, "add", ".", exception: true)
      system("git", "-C", origin, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init", exception: true)

      board = Board.create!(name: "S", default_branch: "main", local_path: origin)
      col = board.columns.create!(name: "E", archetype: "execution", position: 0, policy: {})
      card = board.cards.create!(column: col, title: "salvage", status: "queued",
                                 branch_name: "cardinal/1-salvage")

      ws = Agent::Workspace::Local.new(card)
      ws.stub(:push!, nil) do
        ws.provision
        File.write(ws.path.join("a.txt"), "uncommitted edit") # simulate killed run
        assert_nothing_raised { Agent::Workspace::Local.new(card).stub(:push!, nil, &:provision) }
      end
      log, = Open3.capture2e("git", "-C", ws.path.to_s, "log", "--oneline", "-2")
      assert_match(/WIP: salvage/, log)
      assert_equal "uncommitted edit", File.read(ws.path.join("a.txt"))
    ensure
      FileUtils.rm_rf(Agent::Workspace::Local::ROOT.join("card-1"))
    end
  end
end
