require "test_helper"

# The compact/summary generators feed a transcript dump to a chat model — if
# the prompt ends on dialogue, the model replies to it ("What would you like
# to work on next?") instead of producing the document. The task must be
# restated at the very end, and the system prompt must forbid conversation.
class PromptShapeTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @card = create_card(@board, "planning", status: "discussing")
    @card.log!("assistant_message", actor: "assistant", text: "Anything else? What would you like to work on next?")
  end

  test "compact prompt ends by restating the task, after any dialogue" do
    prompt = CompactJob.new.send(:build_prompt, @card)
    assert_match(/END OF SOURCE MATERIAL/, prompt)
    assert prompt.strip.end_with?("no reply to anything above."),
           "task restatement must be the LAST thing in the prompt"
    assert_match(/NOT in a conversation/, CompactJob::SYSTEM)
  end

  test "summary prompt ends by restating the task" do
    prompt = SummaryJob.new.send(:build_prompt, @card)
    assert_match(/END OF SOURCE MATERIAL/, prompt)
    assert prompt.strip.end_with?("no reply to anything above.")
    assert_match(/NOT in a conversation/, SummaryJob::SYSTEM)
  end
end
