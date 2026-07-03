require "test_helper"

class ClaudeCliTest < ActiveSupport::TestCase
  test "friendly failure messages by subtype" do
    assert_match(/ran out of working turns/, ClaudeCli.friendly_failure({ "subtype" => "error_max_turns" }))
    assert_match(/internal error/, ClaudeCli.friendly_failure({ "subtype" => "error_during_execution" }))
    assert_match(/unknown error/, ClaudeCli.friendly_failure({}))
  end

  test "max_turns failure resumes tool-less and returns the wrap-up answer" do
    calls = []
    fake = lambda do |text, **opts|
      calls << [text, opts]
      if calls.size == 1
        { "is_error" => true, "subtype" => "error_max_turns", "session_id" => "sess-9" }
      else
        { "is_error" => false, "subtype" => "success", "result" => "wrapped answer" }
      end
    end
    ClaudeCli.stub(:invoke, fake) do
      assert_equal "wrapped answer", ClaudeCli.prompt("explore stuff", tools: "Read", max_turns: 5)
    end
    assert_equal 2, calls.size
    assert_equal ClaudeCli::WRAP_UP, calls.last[0]
    assert_equal "sess-9", calls.last[1][:resume]
    assert_equal "", calls.last[1][:tools]
  end

  test "non-turn failures raise a friendly error carrying detail" do
    ClaudeCli.stub(:invoke, { "is_error" => true, "subtype" => "error_during_execution" }) do
      err = assert_raises(ClaudeCli::Error) { ClaudeCli.prompt("hi") }
      assert_match(/internal error/, err.message)
      assert_match(/error_during_execution/, err.detail)
    end
  end
end
