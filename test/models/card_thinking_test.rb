require "test_helper"

class CardThinkingTest < ActiveSupport::TestCase
  setup do
    @board = create_board
  end

  test "awaiting assistant after entering planning (kickoff pending)" do
    card = create_card(@board, "planning", status: "discussing")
    card.log!("column_move", actor: "user", text: "moved")
    assert card.awaiting_assistant?
    assert card.thinking?
  end

  test "awaiting assistant after a user message, resolved by the reply" do
    card = create_card(@board, "planning", status: "discussing")
    card.log!("user_message", actor: "user", text: "hello?")
    assert card.awaiting_assistant?

    card.log!("assistant_message", actor: "assistant", text: "hi!")
    assert_not card.awaiting_assistant?
    assert_not card.thinking?
  end

  test "an error also resolves the wait" do
    card = create_card(@board, "planning", status: "discussing")
    card.log!("user_message", actor: "user", text: "hello?")
    card.log!("error", text: "boom")
    assert_not card.awaiting_assistant?
  end

  test "working cards think regardless of column" do
    card = create_card(@board, "execution", status: "working")
    assert card.thinking?
  end

  test "cards outside planning do not await the assistant" do
    card = create_card(@board, "inbox")
    card.log!("user_message", actor: "user", text: "note to self")
    assert_not card.awaiting_assistant?
  end
end
