require "test_helper"

class CardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "T", default_branch: "main")
    %w[inbox planning execution review terminal].each_with_index do |arch, i|
      @board.columns.create!(name: arch, archetype: arch, position: i, policy: {})
    end
  end

  test "destroy removes the card and its history" do
    card = @board.cards.create!(column: @board.columns.first, title: "bye")
    card.log!("user_message", actor: "user", text: "hello")
    session = card.agent_sessions.create!(status: "ready")
    session.runs.create!(status: "succeeded", briefing: {})

    assert_difference("Card.count", -1) do
      delete card_path(card)
    end
    assert_redirected_to root_path
    assert_equal 0, Event.where(card_id: card.id).count
    assert_equal 0, AgentSession.where(card_id: card.id).count
  end

  test "destroy refuses while the card is working" do
    col = @board.columns.find_by!(archetype: "execution")
    card = @board.cards.create!(column: col, title: "busy", status: "working")
    assert_no_difference("Card.count") do
      delete card_path(card)
    end
    assert_redirected_to card_path(card)
  end
end
