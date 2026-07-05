require "test_helper"

# GitHub Issues sync (card #49).
class IssuesSyncTest < ActionDispatch::IntegrationTest
  FAKE_ISSUES = [
    GithubIssues::Issue.new(number: 7, title: "Login loops forever", body: "Repro: ...", labels: ["bug"]),
    GithubIssues::Issue.new(number: 9, title: "Dark mode", body: "", labels: [])
  ].freeze

  setup do
    @board = Board.create!(name: "I", default_branch: "main",
                           repo_url: "git@github.com:o/r.git", local_path: "/tmp/x")
    @board.columns.create!(name: "Tasks", archetype: "inbox", position: 0, policy: {})
  end

  test "the issues modal lists open issues with import buttons" do
    GithubIssues.stub(:list, FAKE_ISSUES) do
      get issues_board_path, headers: { "Turbo-Frame" => "modal" }
    end
    assert_response :success
    assert_match "Login loops forever", response.body
    assert_select "form[action=?]", import_issue_board_path(number: 7)
  end

  test "importing creates an inbox card with body, labels, and issue number" do
    GithubIssues.stub(:list, FAKE_ISSUES) do
      Open3.stub(:capture2e, ["", Struct.new(:exitstatus) { def success? = true }.new(0)]) do
        post import_issue_board_path(number: 7)
      end
    end
    card = @board.cards.find_by!(issue_number: 7)
    assert_equal "Login loops forever", card.title
    assert_equal ["bug"], card.tags
    assert_match(/Imported from GitHub issue #7/, card.description)
    assert_equal "inbox", card.column.archetype
  end

  test "importing the same issue twice reuses the card" do
    GithubIssues.stub(:list, FAKE_ISSUES) do
      Open3.stub(:capture2e, ["", Struct.new(:exitstatus) { def success? = true }.new(0)]) do
        post import_issue_board_path(number: 7)
        post import_issue_board_path(number: 7)
      end
    end
    assert_equal 1, @board.cards.where(issue_number: 7).count
  end

  test "a card born from an issue gets Closes #N in its PR body" do
    card = @board.cards.create!(column: @board.columns.first, title: "from issue", issue_number: 7)
    session = card.agent_sessions.create!(status: "ready")
    run = session.runs.create!(status: "running", briefing: {})
    body = Agent::Runner.new(run).send(:pr_body)
    assert body.start_with?("Closes #7"), body
  end
end
