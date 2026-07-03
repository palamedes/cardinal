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

  test "create persists an optional branch name and PR url" do
    post cards_path, params: { card: { title: "with git",
                                       branch_name: "cardinal/1-thing",
                                       pr_url: "https://github.com/o/r/pull/7" } }
    card = @board.cards.find_by!(title: "with git")
    assert_equal "cardinal/1-thing", card.branch_name
    assert_equal "https://github.com/o/r/pull/7", card.pr_url
  end

  # The optional git fields left blank on the new-card form must not create a
  # half-real PR: "" would render a "GitHub #" footer with no number.
  test "create with blank git fields stores nil, and the card face shows no PR footer" do
    post cards_path, params: { card: { title: "no git", branch_name: "", pr_url: "  " } }
    card = @board.cards.find_by!(title: "no git")
    assert_nil card.branch_name
    assert_nil card.pr_url

    get root_path
    face = css_select("[data-card-id='#{card.number}']").first
    assert face, "card face should render"
    assert_empty face.css(".card-footer"), "blank pr_url must not render a PR footer"
  end
end

class CardGitFieldsTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "G", default_branch: "main")
    @col = @board.columns.create!(name: "t", archetype: "inbox", position: 0, policy: {})
  end

  test "editing a blank branch name persists it and logs one coalesced changelog entry" do
    card = @board.cards.create!(column: @col, title: "hint me")
    patch card_path(card), params: { autosave: "1", card: { branch_name: "cardinal/2-hint" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal "cardinal/2-hint", card.reload.branch_name
    logs = card.events.where(kind: "status_change").select { |e| e.payload["changelog"] }
    assert_equal 1, logs.size
    assert_includes logs.first.payload["fields"], "branch_name"
  end

  test "a set branch name is locked and cannot be overwritten via update" do
    card = @board.cards.create!(column: @col, title: "locked", branch_name: "cardinal/3-original")
    patch card_path(card), params: { autosave: "1", card: { branch_name: "cardinal/3-hijack" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal "cardinal/3-original", card.reload.branch_name
  end

  test "detail shows an editable branch input when blank and read-only display once set" do
    blank = @board.cards.create!(column: @col, title: "blank")
    get card_path(blank)
    assert_select "input[name=?]", "card[branch_name]"

    set = @board.cards.create!(column: @col, title: "set", branch_name: "cardinal/4-done")
    get card_path(set)
    assert_select "input[name=?]", "card[branch_name]", false
    assert_select ".locked-field code", text: "cardinal/4-done"
  end
end

class CardReviewButtonTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "R", default_branch: "main")
    @review = @board.columns.create!(name: "review", archetype: "review", position: 0, policy: {})
  end

  test "a card in review with a PR shows the full-width View Pull Request button" do
    card = @board.cards.create!(column: @review, title: "reviewable", status: "in_review",
                                pr_url: "https://github.com/o/r/pull/9")
    get card_path(card)
    assert_response :success
    assert_select "a.pr-view-btn[href=?][target=_blank]",
                  "https://github.com/o/r/pull/9", text: "View Pull Request"
  end

  test "a card in review without a PR shows no button" do
    card = @board.cards.create!(column: @review, title: "no pr", status: "in_review")
    get card_path(card)
    assert_response :success
    assert_select "a.pr-view-btn", false
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
