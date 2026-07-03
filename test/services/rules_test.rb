require "test_helper"

class RulesTest < ActiveSupport::TestCase
  setup do
    @board = create_board
  end

  test "planning default enqueues the assistant kickoff" do
    card = create_card(@board)
    assert_enqueued_with(job: AssistantReplyJob) do
      Rules.fire_entry(card, column(@board, "planning"))
    end
  end

  test "assistant kickoff without the claude CLI posts the canned greeting" do
    card = create_card(@board)
    ClaudeCli.stub(:available?, false) do
      AssistantReplyJob.perform_now(card, kickoff: true)
    end
    assert_match(/help shape this card/, card.events.where(kind: "assistant_message").last.text)
  end

  test "terminal default with a PR enqueues the merge job" do
    card = create_card(@board, "inbox", pr_url: "https://github.com/t/t/pull/9")
    assert_enqueued_with(job: MergePrJob) do
      Rules.fire_entry(card, column(@board, "terminal"))
    end
  end

  test "terminal default without a PR just finalizes" do
    card = create_card(@board)
    assert_no_enqueued_jobs(only: MergePrJob) do
      Rules.fire_entry(card, column(@board, "terminal"))
    end
  end

  test "custom ai_task rule enqueues a maintenance agent" do
    col = column(@board, "planning")
    col.update!(policy: col.policy.merge("on_entry" => [{ "action" => "ai_task", "prompt" => "Summarize %{title}" }]))
    card = create_card(@board)
    assert_enqueued_with(job: AiTaskJob) do
      Rules.fire_entry(card, col)
    end
    # custom rules replace archetype defaults
    assert_equal 0, card.events.where(kind: "assistant_message").count
  end

  test "string rules are normalized" do
    col = column(@board, "review") # inbox is never-AI; use an AI-capable column
    col.update!(policy: col.policy.merge("on_entry" => "assistant_greeting"))
    card = create_card(@board)
    assert_enqueued_with(job: AssistantReplyJob) do
      Rules.fire_entry(card, col)
    end
  end

  test "unknown rule logs an error event instead of raising" do
    col = column(@board, "inbox")
    col.update!(policy: col.policy.merge("on_entry" => [{ "action" => "explode" }]))
    card = create_card(@board)
    assert_nothing_raised { Rules.fire_entry(card, col) }
    assert_match(/Unknown column rule/, card.events.where(kind: "error").last.text)
  end
end

class MarkPrReadyRuleTest < ActiveSupport::TestCase
  test "mark_pr_ready enqueues the job when the card has a PR" do
    board = Board.create!(name: "Q", default_branch: "main")
    qa = board.columns.create!(name: "QA", archetype: "review", position: 0,
                               policy: { "on_entry" => [{ "action" => "mark_pr_ready" }] })
    card = board.cards.create!(column: qa, title: "t", status: "in_review",
                               pr_url: "https://github.com/o/r/pull/9")
    assert_enqueued_with(job: MarkPrReadyJob, args: [card.id]) do
      Rules.fire_entry(card, qa)
    end
  end

  test "mark_pr_ready without a PR just logs" do
    board = Board.create!(name: "Q2", default_branch: "main")
    qa = board.columns.create!(name: "QA", archetype: "review", position: 0,
                               policy: { "on_entry" => [{ "action" => "mark_pr_ready" }] })
    card = board.cards.create!(column: qa, title: "t", status: "in_review")
    assert_no_enqueued_jobs(only: MarkPrReadyJob) { Rules.fire_entry(card, qa) }
    assert_match(/No PR/, card.events.last.text)
  end
end

class RulesDescribeTest < ActiveSupport::TestCase
  test "compiled rules describe themselves in English" do
    rules = [{ "action" => "mark_pr_ready" },
             { "action" => "ai_task", "prompt" => "Suggest tags for %{title}" }]
    desc = Rules.describe(rules)
    assert_match(/take the PR out of draft; then run a one-shot AI task/, desc)
    assert_match(/Suggest tags/, desc)
  end

  test "describe handles string and hash shorthands" do
    assert_equal "merge the PR and ship", Rules.describe("merge_pr")
    assert_equal "assign a worker agent and start a run", Rules.describe({ "action" => "start_agent_run" })
  end
end
