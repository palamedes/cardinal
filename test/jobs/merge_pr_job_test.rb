require "test_helper"

# The merge gate: Done's entry rule never ships over failing CI.
class MergePrJobTest < ActiveSupport::TestCase
  Status = Struct.new(:exitstatus) do
    def success? = exitstatus.zero?
  end

  setup do
    @board = create_board
    @card = create_card(@board, "terminal", status: "done", pr_url: "https://github.com/o/r/pull/9")
  end

  # Route gh calls through a script: each entry maps a subcommand ("checks",
  # "merge", ...) to [output, exit]. Unlisted subcommands succeed silently.
  def with_gh(script, &block)
    calls = []
    fake = lambda do |*cmd|
      sub = cmd[0] == "gh" ? cmd[2] : cmd[1]
      calls << sub
      out, code = script.fetch(sub, ["", 0])
      [out, Status.new(code)]
    end
    Open3.stub(:capture2e, fake, &block)
    calls
  end

  test "green checks merge the PR and stamp it" do
    calls = with_gh("checks" => ["all passing", 0]) { MergePrJob.perform_now(@card.id) }
    assert_includes calls, "merge"
    assert_equal "merged", @card.reload.pr_state
  end

  test "a repo with no checks configured still merges" do
    calls = with_gh("checks" => ["no checks reported on the 'x' branch", 1]) do
      MergePrJob.perform_now(@card.id)
    end
    assert_includes calls, "merge"
    assert_equal "merged", @card.reload.pr_state
  end

  test "failing checks block the card instead of merging" do
    calls = with_gh("checks" => ["build\tfail\t1m2s", 1]) { MergePrJob.perform_now(@card.id) }
    assert_not_includes calls, "merge"
    @card.reload
    assert_not_equal "merged", @card.pr_state
    assert_equal "blocked", @card.status
    assert_match(/CI checks failing/, @card.events.last.payload["text"])
  end

  test "pending checks block with a try-again message" do
    with_gh("checks" => ["build\tpending", 8]) { MergePrJob.perform_now(@card.id) }
    @card.reload
    assert_equal "blocked", @card.status
    assert_match(/still running/, @card.events.last.payload["text"])
  end

  # Card #55 floor: a sibling's merge conflicted this PR after its CI ran.
  test "a conflicting PR blocks with a resolution hint, without attempting the merge" do
    calls = with_gh(
      "checks" => ["all passing", 0],
      "view"   => ['{"mergeable":"CONFLICTING"}', 0]
    ) { MergePrJob.perform_now(@card.id) }
    assert_not_includes calls, "merge"
    @card.reload
    assert_equal "blocked", @card.status
    assert_match(/Merge conflict/, @card.events.last.payload["text"])
    assert_match(/conflict-resolution run/, @card.events.last.payload["text"])
  end

  test "a merge step failure blocks the card instead of leaving it done" do
    with_gh(
      "checks" => ["all passing", 0],
      "view"   => ['{"mergeable":"MERGEABLE"}', 0],
      "merge"  => ["X Pull request is not mergeable", 1]
    ) { MergePrJob.perform_now(@card.id) }
    @card.reload
    assert_equal "blocked", @card.status
    assert_not_equal "merged", @card.pr_state
    assert_match(/Merge step failed/, @card.events.last.payload["text"])
  end
end
