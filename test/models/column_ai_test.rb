require "test_helper"

class ColumnAiTest < ActiveSupport::TestCase
  setup do
    @board = create_board
  end

  test "inbox is never AI, others default on, explicit off wins" do
    assert_not column(@board, "inbox").ai?
    assert column(@board, "execution").ai?
    col = column(@board, "execution")
    col.update!(policy: col.policy.merge("ai" => false))
    assert_not col.ai?
  end

  test "AI rules are skipped in non-AI columns" do
    col = column(@board, "execution")
    col.update!(policy: { "ai" => false })
    card = create_card(@board)
    assert_no_enqueued_jobs(only: StartRunJob) do
      Rules.fire_entry(card, col)
    end
    assert_match(/AI is off/, card.events.last.text)
  end

  test "entering a non-AI execution column reads as human work" do
    col = column(@board, "execution")
    col.update!(policy: { "ai" => false })
    card = create_card(@board)
    CardTransition.new(card, to_column: col).call
    assert_equal "working", card.reload.status
  end

  test "sweeper leaves human-working cards alone" do
    col = column(@board, "execution")
    col.update!(policy: { "ai" => false })
    card = create_card(@board, "execution", status: "working")
    RunSweeper.sweep
    assert_equal "working", card.reload.status
  end
end
