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

class CardLinkableTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "L", default_branch: "main")
    col = @board.columns.create!(name: "t", archetype: "inbox", position: 0, policy: {})
    @card = @board.cards.create!(column: col, title: "linkable card")
  end

  test "a direct visit to a card renders the whole board with the modal open" do
    get card_path(@card)
    assert_response :success
    # The board is rendered behind the modal (topbar + columns)...
    assert_select "header.topbar"
    assert_select "main.board"
    # ...with the card detail populated inside the permanent modal frame.
    assert_select "turbo-frame#modal .modal.card-detail h1", /linkable card/
  end

  test "a turbo-frame request returns only the modal, not the board" do
    get card_path(@card), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "turbo-frame#modal .modal.card-detail h1", /linkable card/
    assert_select "header.topbar", false
    assert_select "main.board", false
  end
end

class CardAutosaveTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "A", default_branch: "main")
    col = @board.columns.create!(name: "t", archetype: "inbox", position: 0, policy: {})
    @card = @board.cards.create!(column: col, title: "orig")
  end

  test "autosave patches the face only and coalesces changelog entries" do
    patch card_path(@card), params: { autosave: "1", card: { title: "better title" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_no_match 'target="modal"', response.body
    assert_match "card_#{@card.id}", response.body

    patch card_path(@card), params: { autosave: "1", card: { description: "words" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    logs = @card.events.where(kind: "status_change").select { |e| e.payload["changelog"] }
    assert_equal 1, logs.size
    assert_equal %w[title description], logs.first.payload["fields"]
    assert_equal "better title", @card.reload.title
    assert_equal "words", @card.description
  end

  test "blank title on autosave is ignored, not destructive" do
    patch card_path(@card), params: { autosave: "1", card: { title: "", description: "d" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal "orig", @card.reload.title
    assert_equal "d", @card.description
  end
end
