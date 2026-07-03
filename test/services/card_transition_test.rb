require "test_helper"

class CardTransitionTest < ActiveSupport::TestCase
  setup do
    @board = create_board
  end

  test "entry statuses follow the target archetype" do
    card = create_card(@board)
    { "planning" => "discussing", "execution" => "queued",
      "review" => "in_review", "terminal" => "done" }.each do |arch, status|
      result = CardTransition.new(card, to_column: column(@board, arch)).call
      assert result.success?, "move to #{arch} failed: #{result.error}"
      assert_equal status, card.reload.status
    end
  end

  test "execution entry assigns a branch and queues a run job" do
    card = create_card(@board)
    assert_enqueued_with(job: StartRunJob) do
      CardTransition.new(card, to_column: column(@board, "execution")).call
    end
    assert_equal "cardinal/#{card.number}-test-card", card.reload.branch_name
  end

  test "a working card refuses to leave its execution column" do
    card = create_card(@board, "execution", status: "working")
    result = CardTransition.new(card, to_column: column(@board, "review")).call
    assert_not result.success?
    assert_match(/active run/, result.error)
    assert_equal "working", card.reload.status
  end

  test "a parked card can leave — its pending run is cancelled" do
    card = create_card(@board, "execution", status: "needs_input")
    run = create_run(card, status: "needs_input")
    result = CardTransition.new(card, to_column: column(@board, "review")).call
    assert result.success?
    assert_equal "cancelled", run.reload.status
    assert_equal "in_review", card.reload.status
  end

  test "cannot move to a column on another board" do
    other = create_board
    card = create_card(@board)
    result = CardTransition.new(card, to_column: column(other, "planning")).call
    assert_not result.success?
  end

  test "column_move event is written" do
    card = create_card(@board)
    CardTransition.new(card, to_column: column(@board, "planning")).call
    assert_equal 1, card.events.where(kind: "column_move").count
  end
end
