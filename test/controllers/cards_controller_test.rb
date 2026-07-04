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

# Cost footer — running tally on the closed card face and latest-run cost on the
# open card's work panel (card #20).
class CardCostFooterTest < ActionDispatch::IntegrationTest
  setup do
    @board = create_board
    column(@board, "execution").update!(
      policy: column(@board, "execution").policy.merge("model" => "claude-opus-4-8", "effort" => "high")
    )
  end

  test "closed card sums run costs into the footer with the model label" do
    card = create_card(@board, "execution", status: "working")
    create_run(card).update!(cost: 1.25, output_tokens: 100)
    create_run(card).update!(cost: 11.09, output_tokens: 250)

    get root_path
    footer = css_select("[data-card-id='#{card.number}'] .card-footer").first
    assert footer, "a card with run cost should render a footer"
    assert_equal "Opus - High", footer.css(".footer-left").text.strip
    assert_equal "$12.34 · 350 out", footer.css(".footer-cost").text.strip
  end

  test "closed card footer shows both the cost tally and the PR link" do
    card = create_card(@board, "execution", status: "working",
                       pr_url: "https://github.com/o/r/pull/7")
    create_run(card).update!(cost: 2.0, output_tokens: 40)

    get root_path
    footer = css_select("[data-card-id='#{card.number}'] .card-footer").first
    assert footer
    assert_equal "$2.0 · 40 out", footer.css(".footer-cost").text.strip
    assert_includes footer.css(".footer-pr").text, "GitHub #7"
  end

  test "a card with no runs and no PR renders no footer" do
    card = create_card(@board, "execution", status: "queued")
    get root_path
    face = css_select("[data-card-id='#{card.number}']").first
    assert face
    assert_empty face.css(".card-footer")
  end

  test "open card work panel shows the latest run cost and model label" do
    card = create_card(@board, "execution", status: "working")
    create_run(card).update!(cost: 0.10, output_tokens: 5)
    create_run(card).update!(cost: 0.56, output_tokens: 100)

    get card_path(card)
    footer = css_select(".work-footer").first
    assert footer, "the work panel should show a cost footer"
    assert_equal "Opus - High", footer.css(".footer-left").text.strip
    assert_equal "$0.56 · 100 out", footer.css(".footer-cost").text.strip
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

class CardSummaryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @board = Board.create!(name: "S", default_branch: "main")
    %w[inbox planning execution].each_with_index do |arch, i|
      @board.columns.create!(name: arch, archetype: arch, position: i, policy: {})
    end
    @col = @board.columns.find_by!(archetype: "inbox")
    @card = @board.cards.create!(column: @col, title: "shipped a thing")
  end

  test "the summary tab renders the panel with a generate button" do
    get card_path(@card, zoom: "summary")
    assert_response :success
    assert_select "#card_summary textarea[name=?]", "card[summary]"
    assert_select "form[action=?]", summarize_card_path(@card)
  end

  test "summarize flips the card into working and enqueues the job" do
    assert_enqueued_with(job: SummaryJob) do
      post summarize_card_path(@card), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_equal "working", @card.reload.summary_status
    assert_match "card_summary", response.body
    assert_match "Generating…", response.body
  end

  test "summarize is a no-op while one is already running" do
    @card.update!(summary_status: "working")
    assert_no_enqueued_jobs(only: SummaryJob) do
      post summarize_card_path(@card), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "autosave persists a hand-edited summary and logs a changelog entry" do
    patch card_path(@card), params: { autosave: "1", card: { summary: "We fixed the thing." } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal "We fixed the thing.", @card.reload.summary
    log = @card.events.where(kind: "status_change").select { |e| e.payload["changelog"] }.first
    assert_includes log.payload["fields"], "summary"
  end
end

class CardCompactTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @board = Board.create!(name: "C", default_branch: "main")
    %w[inbox planning execution].each_with_index do |arch, i|
      @board.columns.create!(name: arch, archetype: arch, position: i, policy: {})
    end
    @col = @board.columns.find_by!(archetype: "inbox")
    @card = @board.cards.create!(column: @col, title: "shipped a thing")
  end

  test "the compact tab renders the panel with a generate button" do
    get card_path(@card, zoom: "compact")
    assert_response :success
    assert_select "#card_compact textarea[name=?]", "card[compact]"
    assert_select "form[action=?]", compact_card_path(@card)
  end

  test "compact flips the card into working and enqueues the job" do
    assert_enqueued_with(job: CompactJob) do
      post compact_card_path(@card), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_equal "working", @card.reload.compact_status
    assert_match "card_compact", response.body
    assert_match "Generating…", response.body
  end

  test "compact is a no-op while one is already running" do
    @card.update!(compact_status: "working")
    assert_no_enqueued_jobs(only: CompactJob) do
      post compact_card_path(@card), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "autosave persists a hand-edited compact and logs a changelog entry" do
    patch card_path(@card), params: { autosave: "1", card: { compact: "## Notes\nUses X." } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal "## Notes\nUses X.", @card.reload.compact
    log = @card.events.where(kind: "status_change").select { |e| e.payload["changelog"] }.first
    assert_includes log.payload["fields"], "compact"
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
