require "test_helper"
require "tmpdir"

class BoardBriefTest < ActiveSupport::TestCase
  setup do
    @board = create_board
  end

  def commit!(dir, msg)
    File.write(File.join(dir, "f.txt"), msg)
    system("git", "-C", dir, "add", "-A")
    system("git", "-C", dir, "commit", "-qm", msg)
    `git -C #{dir} rev-parse HEAD`.strip
  end

  test "commits_behind_brief counts commits since the stored sha" do
    Dir.mktmpdir do |dir|
      system("git", "init", "-qb", "main", dir)
      system("git", "-C", dir, "config", "user.email", "t@t.co")
      system("git", "-C", dir, "config", "user.name", "T")
      sha = commit!(dir, "one")
      @board.update!(local_path: dir, brief_sha: sha)
      assert_equal 0, @board.commits_behind_brief

      commit!(dir, "two")
      commit!(dir, "three")
      # Fresh load (as each request gets) — the count is memoized per instance.
      fresh = Board.find(@board.id)
      assert_equal 2, fresh.commits_behind_brief
      assert_not fresh.brief_stale?
    end
  end

  test "commits_behind_brief is nil without a brief sha or local path" do
    assert_nil @board.commits_behind_brief
    @board.update!(brief_sha: "deadbeef")
    assert_nil @board.commits_behind_brief # no local_path
  end

  test "brief_stale? true once BRIEF_STALE_AT commits behind" do
    board = Board.new
    board.define_singleton_method(:commits_behind_brief) { Board::BRIEF_STALE_AT }
    assert board.brief_stale?
  end

  test "staleness color interpolates grey toward red and clamps" do
    board = Board.new
    board.define_singleton_method(:commits_behind_brief) { 0 }
    assert_equal "#8a8a8a", board.brief_staleness_color

    board.define_singleton_method(:commits_behind_brief) { Board::BRIEF_STALE_AT }
    assert_equal "#d43333", board.brief_staleness_color

    board.define_singleton_method(:commits_behind_brief) { 999 } # clamped
    assert_equal "#d43333", board.brief_staleness_color
  end

  test "repo_brief reads the .cardinal file, brief? gates on sha + file" do
    assert_not @board.brief?
    File.stub(:exist?, ->(p) { p.to_s == @board.brief_path.to_s }) do
      File.stub(:read, "## Overview\nA repo.") do
        assert_equal "## Overview\nA repo.", @board.repo_brief
        assert_not @board.brief? # no sha yet
        @board.update!(brief_sha: "abc")
        assert @board.brief?
      end
    end
  end
end
