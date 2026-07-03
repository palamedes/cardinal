require "test_helper"
require "tmpdir"

class BoardBootstrapTest < ActiveSupport::TestCase
  test "sanitize_remote_url strips embedded credentials" do
    assert_equal "https://github.com/o/r.git",
                 Board.sanitize_remote_url("https://x-access-token:tok123@github.com/o/r.git")
    assert_equal "git@github.com:o/r.git", Board.sanitize_remote_url("git@github.com:o/r.git")
  end

  test "bootstrap! builds a board with default columns from a repo path" do
    Dir.mktmpdir do |dir|
      system("git", "init", "-qb", "main", dir)
      system("git", "-C", dir, "remote", "add", "origin", "git@example.com:o/r.git")
      board = Board.bootstrap!(dir)
      assert_equal File.basename(dir), board.name
      assert_equal "git@example.com:o/r.git", board.repo_url
      assert_equal %w[inbox planning execution review terminal], board.columns.pluck(:archetype)
      assert_equal dir, board.local_path
    end
  end
end
