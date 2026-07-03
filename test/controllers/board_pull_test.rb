require "test_helper"

# The topbar Pull button (fast-forward the board's checkout after Done merges
# PRs upstream). Uses real git repos in tmpdirs — no mocks, same seams as prod.
class BoardPullTest < ActionDispatch::IntegrationTest
  setup do
    @dir = Dir.mktmpdir("cardinal-pull")
    @origin = File.join(@dir, "origin.git")
    @local = File.join(@dir, "local")
    @other = File.join(@dir, "other")
    system("git", "init", "--quiet", "--bare", @origin, exception: true)
    system("git", "clone", "--quiet", @origin, @other, exception: true)
    commit(@other, "first")
    system("git", "-C", @other, "push", "--quiet", "origin", "HEAD:main", exception: true)
    system("git", "clone", "--quiet", "--branch", "main", @origin, @local, exception: true)

    @board = Board.create!(name: "P", default_branch: "main", local_path: @local)
  end

  teardown { FileUtils.remove_entry(@dir) }

  test "pull fast-forwards the checkout and reports the commit count" do
    commit(@other, "second")
    system("git", "-C", @other, "push", "--quiet", "origin", "HEAD:main", exception: true)

    post pull_board_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match "Pulled 1 new commit", response.body
    assert_match "pull-ok", response.body
    local_head, = Open3.capture2e("git", "-C", @local, "rev-parse", "HEAD")
    other_head, = Open3.capture2e("git", "-C", @other, "rev-parse", "HEAD")
    assert_equal other_head, local_head
  end

  test "pull with nothing new says so" do
    post pull_board_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_match "Already up to date", response.body
    assert_match "pull-ok", response.body
  end

  test "a diverged checkout is reported, never merged or rebased" do
    commit(@other, "upstream")
    system("git", "-C", @other, "push", "--quiet", "origin", "HEAD:main", exception: true)
    commit(@local, "local-divergence")
    local_head_before, = Open3.capture2e("git", "-C", @local, "rev-parse", "HEAD")

    post pull_board_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_match "pull-err", response.body
    local_head_after, = Open3.capture2e("git", "-C", @local, "rev-parse", "HEAD")
    assert_equal local_head_before, local_head_after, "ff-only must leave a diverged checkout untouched"
  end

  test "a board without a usable local path reports instead of erroring" do
    @board.update!(local_path: nil)
    post pull_board_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_match "No local repo path", response.body
    assert_match "pull-err", response.body
  end

  private

  def commit(repo, name)
    File.write(File.join(repo, name), name)
    system("git", "-C", repo, "add", ".", exception: true)
    system("git", "-C", repo, "-c", "user.email=t@t", "-c", "user.name=t",
           "commit", "--quiet", "-m", name, exception: true)
  end
end
