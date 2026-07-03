require "test_helper"

class AssistantReplyJobTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @board.update!(local_path: Rails.root.to_s)
    @card = create_card(@board, "planning", status: "discussing", title: "session test")
  end

  test "first reply stores the session; later replies resume it with just the new message" do
    calls = []
    fake = lambda do |text, **opts|
      calls << [text, opts]
      ["a reply", "sess-42"]
    end

    ClaudeCli.stub(:available?, true) do
      ClaudeCli.stub(:prompt, fake) do
        @card.log!("user_message", actor: "user", text: "first question")
        AssistantReplyJob.perform_now(@card)
        assert_equal "sess-42", @card.reload.assistant_session_id
        assert_nil calls[0][1][:resume]

        @card.log!("user_message", actor: "user", text: "second question")
        AssistantReplyJob.perform_now(@card)
        assert_equal "sess-42", calls[1][1][:resume]
        assert_equal "second question", calls[1][0]
      end
    end
  end

  test "a dead session falls back to a fresh transcript conversation" do
    @card.update!(assistant_session_id: "sess-dead")
    @card.log!("user_message", actor: "user", text: "hello again")
    calls = []
    fake = lambda do |text, **opts|
      calls << [text, opts]
      raise ClaudeCli::Error.new("no such session") if opts[:resume]
      ["fresh reply", "sess-new"]
    end

    ClaudeCli.stub(:available?, true) do
      ClaudeCli.stub(:prompt, fake) do
        AssistantReplyJob.perform_now(@card)
      end
    end
    assert_equal 2, calls.size
    assert_match(/Conversation so far/, calls[1][0])
    assert_equal "sess-new", @card.reload.assistant_session_id
    assert_match(/fresh reply/, @card.events.where(kind: "assistant_message").last.text)
  end
end
