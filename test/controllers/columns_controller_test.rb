require "test_helper"

class ColumnsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "T", default_branch: "main")
    @col = @board.columns.create!(name: "Tasks", archetype: "inbox", position: 0, policy: {})
  end

  test "update stores a valid custom color" do
    patch column_path(@col), params: { column: { name: "Tasks", archetype: "inbox",
                                                 color: "#aa33cc", custom_color: "1" } }
    assert_equal "#aa33cc", @col.reload.safe_color
  end

  test "unchecking custom color clears it; invalid hex never persists" do
    @col.update!(policy: { "color" => "#aa33cc" })
    patch column_path(@col), params: { column: { name: "Tasks", archetype: "inbox",
                                                 color: "#aa33cc", custom_color: "0" } }
    assert_nil @col.reload.safe_color

    patch column_path(@col), params: { column: { name: "Tasks", archetype: "inbox",
                                                 color: "red;} body{display:none", custom_color: "1" } }
    assert_nil @col.reload.safe_color
  end
end
