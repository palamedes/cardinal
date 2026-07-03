require "test_helper"
require "tmpdir"

class DeepDiveJobTest < ActiveSupport::TestCase
  setup do
    @board = create_board
  end

  test "writes the brief to .cardinal and stamps the board" do
    Dir.mktmpdir do |repo|
      system("git", "init", "-qb", "main", repo)
      system("git", "-C", repo, "config", "user.email", "t@t.co")
      system("git", "-C", repo, "config", "user.name", "T")
      File.write(File.join(repo, "x"), "x")
      system("git", "-C", repo, "add", "-A")
      system("git", "-C", repo, "commit", "-qm", "init")
      sha = `git -C #{repo} rev-parse HEAD`.strip
      @board.update!(local_path: repo, brief_status: "working")

      written = nil
      File.stub(:write, ->(path, content) { written = [path.to_s, content] }) do
        ClaudeCli.stub(:available?, true) do
          ClaudeCli.stub(:prompt, "## Overview\nMapped it.") do
            DeepDiveJob.perform_now(@board)
          end
        end
      end

      assert_equal @board.brief_path.to_s, written[0]
      assert_match(/Mapped it/, written[1])
      @board.reload
      assert_equal sha, @board.brief_sha
      assert_not_nil @board.brief_generated_at
      assert_nil @board.brief_status # working flag cleared
    end
  end

  test "uses the planning column model, falling back when unset" do
    @board.update!(local_path: Rails.root.to_s)
    column(@board, "planning").update!(policy: { "model" => "claude-sonnet-4-6" })
    used = nil
    File.stub(:write, true) do
      ClaudeCli.stub(:available?, true) do
        ClaudeCli.stub(:prompt, ->(_p, **opts) { used = opts[:model]; "brief" }) do
          DeepDiveJob.perform_now(@board)
        end
      end
    end
    assert_equal "claude-sonnet-4-6", used
    assert_equal "claude-sonnet-4-6", @board.reload.brief_model
  end

  test "clears the working flag when the CLI is unavailable" do
    @board.update!(local_path: Rails.root.to_s, brief_status: "working")
    ClaudeCli.stub(:available?, false) do
      DeepDiveJob.perform_now(@board)
    end
    assert_nil @board.reload.brief_status
    assert_nil @board.brief_sha # never stamped
  end

  test "a failed dive does not leave the button stuck on working" do
    @board.update!(local_path: Rails.root.to_s, brief_status: "working")
    ClaudeCli.stub(:available?, true) do
      ClaudeCli.stub(:prompt, ->(*) { raise ClaudeCli::Error.new("boom") }) do
        DeepDiveJob.perform_now(@board)
      end
    end
    assert_nil @board.reload.brief_status
  end
end
