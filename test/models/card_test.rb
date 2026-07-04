require "test_helper"

class CardTest < ActiveSupport::TestCase
  setup do
    @board = create_board
  end

  test "bell glyph when a plan is parked awaiting approval" do
    card = create_card(@board, "execution", status: "needs_input")
    create_run(card, status: "needs_input", phase: "plan")

    assert card.ready_for_approval?
    assert_equal "🔔", card.status_glyph
  end

  test "question glyph when parked on a genuine question" do
    card = create_card(@board, "execution", status: "needs_input")
    create_run(card, status: "needs_input", phase: "execute")

    assert_not card.ready_for_approval?
    assert_equal "❓", card.status_glyph
  end

  test "plain status glyph for a completed card" do
    card = create_card(@board, "execution", status: "work_complete")

    assert_not card.ready_for_approval?
    assert_equal "✅", card.status_glyph
  end
end
