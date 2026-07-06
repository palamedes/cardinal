require "test_helper"

# Archive (card #42): off the board, never gone.
class ArchiveTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "A", default_branch: "main")
    %w[inbox terminal].each_with_index do |arch, i|
      @board.columns.create!(name: arch.capitalize, archetype: arch, position: i, policy: {})
    end
    @done = @board.columns.find_by!(archetype: "terminal")
  end

  test "archiving removes a card from the board but keeps it browsable and searchable" do
    card = @board.cards.create!(column: @done, title: "shipped thing", status: "done", tags: ["ui"])
    post archive_card_path(card)
    assert_equal "archived", card.reload.status

    get root_path
    assert_no_match "shipped thing", response.body

    get archive_board_path
    assert_match "shipped thing", response.body
    assert_select ".archive-row[data-search*='shipped thing']"
    assert_select "#global-search", false # archive has its own search box
    assert_select ".archive-tools input[data-filter-target=global]"
  end

  test "a running card cannot be archived" do
    exec = @board.columns.create!(name: "Work", archetype: "execution", position: 2, policy: {})
    card = @board.cards.create!(column: exec, title: "busy", status: "working")
    post archive_card_path(card)
    assert_not_equal "archived", card.reload.status
  end

  test "restore returns the card to its column in an inert status" do
    card = @board.cards.create!(column: @done, title: "resurrect me", status: "archived")
    post unarchive_card_path(card)
    card.reload
    assert_equal "done", card.status
    assert_equal @done.id, card.column_id
    get root_path
    assert_match "resurrect me", response.body
  end

  test "quick-add lives on the inbox column and creates a card with just a title" do
    get root_path
    assert_select ".column-inbox .quick-add input[name='card[title]']"
    assert_select ".column-terminal .quick-add", false

    post cards_path, params: { card: { title: "quick one" } }
    card = @board.cards.find_by!(title: "quick one")
    assert_equal "inbox", card.column.archetype
  end

  test "archived cards drop out of footer counts" do
    @done.update!(policy: @done.policy.merge("footer" => [{ "label" => "Cards:", "compute" => "count_cards" }]))
    @board.cards.create!(column: @done, title: "live", status: "done")
    @board.cards.create!(column: @done, title: "gone", status: "archived")
    assert_equal "1", @done.footer_value("count_cards")
  end
end

class ArchiveRailsTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "AR", default_branch: "main")
    @done = @board.columns.create!(name: "Done", archetype: "terminal", position: 0, policy: {})
    @plan = @board.columns.create!(name: "Planning", archetype: "planning", position: 1, policy: {})
  end

  test "the archive page offers drag-to-archive checkboxes and saves them" do
    get archive_board_path
    assert_select ".archive-rails input[type=checkbox]", 2

    patch board_path(autosave: 1), params: { board: { archive_accepts_from: ["", @done.id.to_s] } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    @board.reload
    assert @board.archive_accepts?(@done)
    assert_not @board.archive_accepts?(@plan)
  end

  test "the topbar bin carries the whitelist for the drag layer" do
    @board.update!(settings: { "archive_accepts_from" => [@done.id.to_s] })
    get root_path
    assert_select ".archive-drop[data-accepts=?]", @done.id.to_s
  end

  test "unchecking everything empties the whitelist without touching other settings" do
    @board.update!(settings: { "archive_accepts_from" => [@done.id.to_s] })
    patch board_path(autosave: 1), params: { board: { archive_accepts_from: [""] } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal [], @board.reload.archive_accepts_from
  end
end

class ArrivalsOnCreateTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "AC", default_branch: "main")
    @tasks = @board.columns.create!(name: "Tasks", archetype: "inbox", position: 0,
                                    policy: { "arrivals" => "top" })
  end

  test "new cards land at the top of an arrivals-top column, oldest sink" do
    first = @board.cards.create!(column: @tasks, title: "oldest")
    second = @board.cards.create!(column: @tasks, title: "newer")
    post cards_path, params: { card: { title: "newest" } }

    titles = @tasks.cards.reload.order(:position).map(&:title)
    assert_equal %w[newest newer oldest], titles
    assert_equal (0..2).to_a, @tasks.cards.order(:position).map(&:position)
    assert_equal [first, second].map(&:title).reverse + [], titles.last(2)
  end

  test "a column without arrivals still appends" do
    plain = @board.columns.create!(name: "Plain", archetype: "planning", position: 1, policy: {})
    a = @board.cards.create!(column: plain, title: "a")
    b = @board.cards.create!(column: plain, title: "b")
    assert_equal %w[a b], plain.cards.order(:position).map(&:title)
    assert_operator a.position, :<, b.position
  end
end
