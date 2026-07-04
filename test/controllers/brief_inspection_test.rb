require "test_helper"
require "tmpdir"

# Inspecting the repo brief + the deep-dive re-run guard (card #12 follow-up):
# a brief that already matches HEAD is never silently regenerated.
class BriefInspectionTest < ActionDispatch::IntegrationTest
  setup do
    @dir = Dir.mktmpdir("cardinal-brief")
    @repo = File.join(@dir, "repo")
    @data = File.join(@dir, "data")
    FileUtils.mkdir_p(@data)
    system("git", "init", "-qb", "main", @repo, exception: true)
    File.write(File.join(@repo, "x"), "x")
    system("git", "-C", @repo, "add", ".", exception: true)
    system("git", "-C", @repo, "-c", "user.email=t@t", "-c", "user.name=t",
           "commit", "-qm", "init", exception: true)
    @sha = `git -C #{@repo} rev-parse HEAD`.strip

    @prev_data_dir = ENV["CARDINAL_DATA_DIR"]
    ENV["CARDINAL_DATA_DIR"] = @data
    @board = Board.create!(name: "B", default_branch: "main", local_path: @repo)
  end

  teardown do
    ENV["CARDINAL_DATA_DIR"] = @prev_data_dir
    FileUtils.remove_entry(@dir)
  end

  def write_brief!(sha: @sha)
    File.write(@board.brief_path, "## Overview\nA tiny repo.")
    @board.update!(brief_sha: sha, brief_generated_at: Time.current, brief_model: "claude-haiku-4-5")
  end

  test "brief_path honors CARDINAL_DATA_DIR, not Rails.root" do
    assert_equal File.join(@data, "repo-brief.md"), @board.brief_path.to_s
  end

  test "the brief modal shows the rendered brief and its provenance" do
    write_brief!
    get brief_board_path, headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_match "A tiny repo", response.body
    assert_match @sha.first(7), response.body
    assert_match "current with HEAD", response.body
    assert_match "Regenerate brief", response.body
  end

  test "a deep dive is skipped while the brief matches HEAD" do
    write_brief!
    assert_no_enqueued_jobs(only: DeepDiveJob) do
      post deep_dive_board_path
    end
    assert_nil @board.reload.brief_status
  end

  test "force regenerates even a current brief; new commits re-arm the button" do
    write_brief!
    assert_enqueued_with(job: DeepDiveJob) { post deep_dive_board_path(force: 1) }

    @board.reload.update!(brief_status: nil)
    File.write(File.join(@repo, "y"), "y")
    system("git", "-C", @repo, "add", ".", exception: true)
    system("git", "-C", @repo, "-c", "user.email=t@t", "-c", "user.name=t",
           "commit", "-qm", "more", exception: true)
    assert_enqueued_with(job: DeepDiveJob) { post deep_dive_board_path }
  end
end
