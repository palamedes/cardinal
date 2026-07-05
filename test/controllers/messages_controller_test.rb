require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "T", default_branch: "main")
    %w[inbox planning execution review terminal].each_with_index do |arch, i|
      @board.columns.create!(name: arch, archetype: arch, position: i, policy: {})
    end
  end

  test "a message on a card under review marks it changes_requested" do
    card = @board.cards.create!(column: @board.columns.find_by!(archetype: "review"),
                                title: "reviewme", status: "in_review")
    post card_messages_path(card), params: { message: { text: "the button is the wrong color" } }
    card.reload
    assert_equal "changes_requested", card.status
    assert_equal "the button is the wrong color", card.events.where(kind: "user_message").last.text
  end

  test "a message on a planning card queues the assistant" do
    card = @board.cards.create!(column: @board.columns.find_by!(archetype: "planning"),
                                title: "planme", status: "discussing")
    assert_enqueued_with(job: AssistantReplyJob) do
      post card_messages_path(card), params: { message: { text: "what about mobile?" } }
    end
    assert_equal "discussing", card.reload.status
  end

  test "a pasted attachment token survives into the message and renders as a thumbnail" do
    card = @board.cards.create!(column: @board.columns.find_by!(archetype: "planning"),
                                title: "attachme", status: "discussing")
    token = %([[cardinal:file name="bug.png" mime="image/png" size="1234"]]iVBORw0KGgo=[[/cardinal:file]])
    post card_messages_path(card), params: { message: { text: "repro:\n\n#{token}" } }

    event = card.events.where(kind: "user_message").last
    assert_includes event.text, token # full base64 stored verbatim for the agent
    get card_path(card)
    assert_match %r{<img[^>]+src="data:image/png;base64,iVBORw0KGgo="}, @response.body
    assert_no_match(/cardinal:file/, @response.body) # raw token never reaches the timeline
  end
end
