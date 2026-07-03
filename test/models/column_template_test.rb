require "test_helper"

# Archetypes are creation-time TEMPLATES (no runtime magic): creating a column
# stamps the archetype's concrete rules + instructions into the policy, and
# whatever the gear modal shows is everything there is.
class ColumnTemplateTest < ActiveSupport::TestCase
  setup do
    @board = Board.create!(name: "T", default_branch: "main")
  end

  test "creating a planning column stamps greeting rule, text, and instructions" do
    col = @board.columns.create!(name: "Plan", archetype: "planning", position: 0, policy: {})
    assert_equal [{ "action" => "assistant_greeting" }], col.policy["on_entry"]
    assert_match(/planning assistant/, col.policy["on_entry_text"])
    assert_match(/acceptance criteria/, col.policy["instructions"])
  end

  test "creating execution and terminal columns stamps their rules" do
    exec = @board.columns.create!(name: "Work", archetype: "execution", position: 0, policy: {})
    done = @board.columns.create!(name: "Done", archetype: "terminal", position: 1, policy: {})
    assert_equal [{ "action" => "start_agent_run" }], exec.policy["on_entry"]
    assert_equal [{ "action" => "merge_pr" }], done.policy["on_entry"]
  end

  test "template only fills blanks — explicit policy values win at creation" do
    col = @board.columns.create!(name: "Plan", archetype: "planning", position: 0,
                                 policy: { "instructions" => "Be terse." })
    assert_equal "Be terse.", col.policy["instructions"]
    assert_equal [{ "action" => "assistant_greeting" }], col.policy["on_entry"]
  end

  test "blank on_entry fires nothing — there is no archetype fallback at runtime" do
    col = @board.columns.create!(name: "Plan", archetype: "planning", position: 0, policy: {})
    col.update!(policy: col.policy.merge("on_entry" => nil, "on_entry_text" => nil))
    card = @board.cards.create!(column: col, title: "quiet")
    assert_no_enqueued_jobs { Rules.fire_entry(card, col) }
  end

  # Accept rails are EXPLICIT ONLY: nothing checked means nothing may enter.
  test "accepts? is explicit-only — empty list accepts from nowhere" do
    a = @board.columns.create!(name: "A", archetype: "review", position: 0, policy: {})
    b = @board.columns.create!(name: "B", archetype: "review", position: 1, policy: {})
    assert_not a.accepts?(b)
    a.update!(policy: a.policy.merge("accepts_from" => [b.id.to_s]))
    assert a.reload.accepts?(b)
  end
end
