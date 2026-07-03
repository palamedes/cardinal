require "test_helper"

class BoardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "T", default_branch: "main")
    @inbox = @board.columns.create!(name: "Tasks", archetype: "inbox", position: 0, policy: {})
    @exec = @board.columns.create!(name: "Doing", archetype: "execution", position: 1, policy: {})
  end

  test "inbox column header carries the New Card [+], not the old bottom button" do
    get root_path
    assert_response :success

    # The composer opens from the header now.
    assert_select "##{ActionView::RecordIdentifier.dom_id(@inbox)} .column-title a.add-card[href=?]", new_card_path
    # The old bottom "+ New Card" button is gone.
    assert_select ".new-card-btn", false
  end

  test "inbox background is wired to create a card; other columns are not" do
    get root_path
    assert_response :success

    assert_select "##{ActionView::RecordIdentifier.dom_id(@inbox)} .cards.cards-clickable" \
                  "[data-action=?][data-board-column-new-url-value=?]",
                  "click->board-column#newCard", new_card_path
    # Non-inbox columns get neither the [+] nor the background click.
    assert_select "##{ActionView::RecordIdentifier.dom_id(@exec)} a.add-card", false
    assert_select "##{ActionView::RecordIdentifier.dom_id(@exec)} .cards.cards-clickable", false
  end
end
