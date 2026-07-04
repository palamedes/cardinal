require "test_helper"

# Board search & filter (card #51). The filtering itself is client-side
# (filter_controller.js); these pin the server-rendered contract it relies on.
class BoardSearchTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "F", default_branch: "main")
    %w[inbox planning].each_with_index do |arch, i|
      @board.columns.create!(name: arch.capitalize, archetype: arch, position: i, policy: {})
    end
  end

  test "card faces carry a lowercased searchable haystack" do
    @board.cards.create!(column: @board.columns.first, title: "Fix The Tooltip",
                         tags: ["UI"], description: "Clipping in the Modal")
    get root_path
    face = css_select("[data-search]").first
    assert face, "card face should carry data-search"
    hay = face["data-search"]
    assert_includes hay, "fix the tooltip"
    assert_includes hay, "ui"
    assert_includes hay, "clipping in the modal"
    assert_includes hay, "#1"
    assert_equal hay, hay.downcase
  end

  test "the board renders the global search box and a scoped filter per column" do
    get root_path
    assert_select "#global-search[data-filter-target=global]"
    assert_select ".col-search[data-col-id]", 2
    assert_select ".col-search-toggle", 2
    assert_select "[data-controller=filter]"
  end
end
