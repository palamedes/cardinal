require "test_helper"

class RulesTest < ActiveSupport::TestCase
  setup do
    @board = create_board
  end

  test "planning default posts the assistant greeting" do
    card = create_card(@board)
    Rules.fire_entry(card, column(@board, "planning"))
    assert_equal 1, card.events.where(kind: "assistant_message").count
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
    col.update!(policy: { "on_entry" => [{ "action" => "ai_task", "prompt" => "Summarize %{title}" }] })
    card = create_card(@board)
    assert_enqueued_with(job: AiTaskJob) do
      Rules.fire_entry(card, col)
    end
    # custom rules replace archetype defaults
    assert_equal 0, card.events.where(kind: "assistant_message").count
  end

  test "string rules are normalized" do
    col = column(@board, "inbox")
    col.update!(policy: { "on_entry" => "assistant_greeting" })
    card = create_card(@board)
    Rules.fire_entry(card, col)
    assert_equal 1, card.events.where(kind: "assistant_message").count
  end

  test "unknown rule logs an error event instead of raising" do
    col = column(@board, "inbox")
    col.update!(policy: { "on_entry" => [{ "action" => "explode" }] })
    card = create_card(@board)
    assert_nothing_raised { Rules.fire_entry(card, col) }
    assert_match(/Unknown column rule/, card.events.where(kind: "error").last.text)
  end
end
