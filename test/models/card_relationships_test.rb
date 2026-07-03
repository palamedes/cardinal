require "test_helper"

class CardRelationshipsTest < ActiveSupport::TestCase
  setup do
    @board = create_board
  end

  test "parent and children associations" do
    parent = create_card(@board, "inbox", title: "epic")
    child = @board.cards.create!(column: parent.column, title: "step 1", parent: parent)
    assert_equal parent, child.parent
    assert_includes parent.children, child
  end

  test "deleting a parent orphans children rather than destroying them" do
    parent = create_card(@board, "inbox", title: "epic")
    child = @board.cards.create!(column: parent.column, title: "step 1", parent: parent)
    parent.destroy!
    assert_nil child.reload.parent_id
  end
end

class CardChildCreationTest < ActionDispatch::IntegrationTest
  test "create with parent_id links the child and logs both cards" do
    board = Board.create!(name: "P", default_branch: "main")
    col = board.columns.create!(name: "t", archetype: "inbox", position: 0, policy: {})
    parent = board.cards.create!(column: col, title: "epic")

    post cards_path, params: { card: { title: "child task", parent_id: parent.id } }
    child = board.cards.find_by!(title: "child task")
    assert_equal parent.id, child.parent_id
    assert_match(/Child card added/, parent.events.last.text)
  end
end
