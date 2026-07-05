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
