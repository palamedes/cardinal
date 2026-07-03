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

  test "same-column drag reorders without firing policies or events" do
    inbox = column(@board, "inbox")
    a, b, c = 3.times.map { |i| create_card(@board, "inbox", title: "card #{i}") }

    result = CardTransition.new(c, to_column: inbox, position: 0).call
    assert result.success?
    assert_equal [c, a, b].map(&:id), inbox.cards.order(:position).pluck(:id)
    assert_equal 0, Event.count

    CardTransition.new(c, to_column: inbox, position: 2).call
    assert_equal [a, b, c].map(&:id), inbox.cards.order(:position).pluck(:id)
  end
end

class AcceptPolicyTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @inbox = column(@board, "inbox")
    @planning = column(@board, "planning")
    @execution = column(@board, "execution")
  end

  test "empty accepts_from allows moves from any column (backward-compatible)" do
    card = create_card(@board, "inbox")
    result = CardTransition.new(card, to_column: @execution).call
    assert result.success?, "unrestricted column rejected a move: #{result.error}"
    assert_equal @execution, card.reload.column
  end

  test "a disallowed source is rejected with a descriptive error and no move" do
    @execution.update!(policy: { "accepts_from" => [@planning.id.to_s] })
    card = create_card(@board, "inbox")
    result = CardTransition.new(card, to_column: @execution).call
    assert_not result.success?
    assert_match(/cannot move directly/, result.error)
    assert_equal @inbox, card.reload.column
  end

  test "a rejected move logs a move_rejected event and no column_move" do
    @execution.update!(policy: { "accepts_from" => [@planning.id.to_s] })
    card = create_card(@board, "inbox")
    CardTransition.new(card, to_column: @execution).call
    assert_equal 1, card.events.where(kind: "move_rejected").count
    assert_equal 0, card.events.where(kind: "column_move").count
  end

  test "an allowed source passes the accept policy" do
    @execution.update!(policy: { "accepts_from" => [@planning.id.to_s] })
    card = create_card(@board, "planning")
    result = CardTransition.new(card, to_column: @execution).call
    assert result.success?, "allowed source rejected: #{result.error}"
    assert_equal @execution, card.reload.column
  end
end

class ArrivalsPolicyTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @done = column(@board, "terminal")
  end

  test "arrivals top forces newcomers to position 0 regardless of drop position" do
    @done.update!(policy: { "arrivals" => "top" })
    first = create_card(@board, "inbox", title: "one")
    second = create_card(@board, "inbox", title: "two")
    CardTransition.new(first, to_column: @done, position: 5).call
    CardTransition.new(second, to_column: @done, position: 5).call
    assert_equal %w[two one], @done.cards.order(:position).pluck(:title)
  end

  test "arrivals bottom forces newcomers to the end" do
    @done.update!(policy: { "arrivals" => "bottom" })
    first = create_card(@board, "inbox", title: "one")
    second = create_card(@board, "inbox", title: "two")
    CardTransition.new(first, to_column: @done, position: 0).call
    CardTransition.new(second, to_column: @done, position: 0).call
    assert_equal %w[one two], @done.cards.order(:position).pluck(:title)
  end

  test "in-column reordering stays manual even with arrivals top" do
    @done.update!(policy: { "arrivals" => "top" })
    a = create_card(@board, "inbox", title: "a")
    b = create_card(@board, "inbox", title: "b")
    CardTransition.new(a, to_column: @done).call
    CardTransition.new(b, to_column: @done).call
    CardTransition.new(b, to_column: @done, position: 1).call # manual reorder down
    assert_equal %w[a b], @done.cards.order(:position).pluck(:title)
  end
end
