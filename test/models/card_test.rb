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

  # Per-card model/effort override (card #33).
  test "effective model and effort fall back to the column, then the card overrides" do
    col = column(@board, "execution")
    col.update!(policy: col.policy.merge("model" => "claude-haiku-4-5-20251001", "effort" => "low"))
    card = create_card(@board, "execution", status: "queued")

    # No override — follows the column, nothing marked overridden.
    assert_equal "claude-haiku-4-5-20251001", card.effective_model
    assert_equal "low", card.effective_effort
    assert_not card.config_overridden?

    # Override — the card's own values win everywhere it resolves a model.
    card.update!(model: "claude-opus-4-8", effort: "high")
    assert_equal "claude-opus-4-8", card.effective_model
    assert_equal "high", card.effective_effort
    assert card.config_overridden?
  end

  test "effective_model_label marks an override with a trailing asterisk" do
    col = column(@board, "execution")
    col.update!(policy: col.policy.merge("model" => "claude-haiku-4-5-20251001"))
    card = create_card(@board, "execution", status: "queued")

    assert_equal "Haiku", card.effective_model_label

    card.update!(model: "claude-opus-4-8", effort: "high")
    assert_equal "Opus - High*", card.effective_model_label
  end

  test "a bare effort override still marks the effective label" do
    col = column(@board, "execution")
    col.update!(policy: col.policy.merge("model" => "claude-sonnet-4-6"))
    card = create_card(@board, "execution", status: "queued")

    card.update!(effort: "max")
    assert_equal "claude-sonnet-4-6", card.effective_model # model still the column's
    assert_equal "Sonnet - Max*", card.effective_model_label
  end
end
