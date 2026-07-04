require "test_helper"
require "tmpdir"

class BoardSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "S", default_branch: "main", local_path: "/tmp/x")
  end

  test "the gear modal shows name, branch, and the read-only repo facts" do
    get edit_board_path, headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "input[name='board[name]']"
    assert_select "input[name='board[default_branch]']"
    assert_match "/tmp/x", response.body
  end

  test "autosave updates name and default branch" do
    patch board_path(autosave: 1), params: { board: { name: "Renamed", default_branch: "develop" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    @board.reload
    assert_equal "Renamed", @board.name
    assert_equal "develop", @board.default_branch
    assert_match 'target="board-name"', response.body
  end

  test "blank fields keep their current values instead of erasing them" do
    patch board_path(autosave: 1), params: { board: { name: "", default_branch: "  " } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    @board.reload
    assert_equal "S", @board.name
    assert_equal "main", @board.default_branch
  end
end

class DefaultBranchDetectionTest < ActiveSupport::TestCase
  test "bootstrap prefers the remote's default branch over the checked-out one" do
    Dir.mktmpdir do |dir|
      origin = File.join(dir, "origin.git")
      clone = File.join(dir, "clone")
      system("git", "init", "-qb", "main", "--bare", origin, exception: true)
      work = File.join(dir, "seed")
      system("git", "clone", "-q", origin, work, exception: true)
      File.write(File.join(work, "x"), "x")
      system("git", "-C", work, "add", ".", exception: true)
      system("git", "-C", work, "-c", "user.email=t@t", "-c", "user.name=t",
             "commit", "-qm", "i", exception: true)
      system("git", "-C", work, "push", "-q", "origin", "HEAD:main", exception: true)

      system("git", "clone", "-q", origin, clone, exception: true)
      # Simulate `cardinal up` from a feature branch — the trap being fixed.
      system("git", "-C", clone, "checkout", "-qb", "feature/oops", exception: true)

      board = Board.bootstrap!(clone)
      assert_equal "main", board.default_branch
    end
  end

  test "a repo with no remote falls back to the current branch" do
    Dir.mktmpdir do |repo|
      system("git", "init", "-qb", "trunk", repo, exception: true)
      board = Board.bootstrap!(repo)
      assert_equal "trunk", board.default_branch
    end
  end
end
