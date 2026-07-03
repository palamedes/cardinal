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

  # Card #17: the Tasks/inbox column is the board's intake — the AI-work and
  # on-entry settings don't apply, and it can never be deleted.
  test "inbox edit form hides AI-work and on-entry settings, and the delete button" do
    get edit_column_path(@col)
    assert_response :success
    %w[column[instructions] column[model] column[effort] column[concurrency_limit]
       column[max_turns] column[timeout_minutes] column[plan_approval]
       column[on_entry_text] column[on_entry_json]].each do |field|
      assert_select "[name=?]", field, false, "expected #{field} to be hidden for the inbox column"
    end
    assert_select ".delete-column", false, "inbox column must not offer a delete button"
  end

  test "non-inbox edit form still shows AI-work settings and the delete button" do
    exec = @board.columns.create!(name: "In Progress", archetype: "execution", position: 1, policy: {})
    get edit_column_path(exec)
    assert_response :success
    assert_select "[name=?]", "column[model]"
    assert_select "[name=?]", "column[plan_approval]"
    assert_select ".delete-column"
  end

  test "inbox column can never be deleted" do
    assert_no_difference -> { Column.count } do
      delete column_path(@col)
    end
    assert_response :unprocessable_entity
    assert Column.exists?(@col.id)
  end

  # Card #17: the Tasks/inbox column is the board's single intake — a second one
  # can't be created, even from a crafted request asking for the inbox archetype.
  test "create refuses to add a second inbox column" do
    assert_no_difference -> { @board.columns.inbox.count } do
      post columns_path, params: { column: { name: "Intake 2", archetype: "inbox" } }
    end
    created = @board.columns.order(:position).last
    assert_not_equal "inbox", created.archetype
    assert_equal "Intake 2", created.name
  end

  test "create still adds a normal execution column" do
    assert_difference -> { @board.columns.count }, 1 do
      post columns_path, params: { column: { name: "Build", archetype: "execution" } }
    end
    assert_equal "execution", @board.columns.order(:position).last.archetype
  end
end

class ColumnAutosaveTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "AS", default_branch: "main")
    @col = @board.columns.create!(name: "Work", archetype: "execution", position: 0, policy: {})
  end

  test "autosave patches the board column only and clears errors" do
    patch column_path(@col), params: { autosave: "1", column: { name: "Working", archetype: "execution" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match "column_#{@col.id}", response.body
    assert_match 'target="column-form-errors"', response.body
    assert_no_match 'target="modal"', response.body
    assert_equal "Working", @col.reload.name
  end

  test "autosave with invalid rules JSON reports in-modal without nuking the form" do
    patch column_path(@col), params: { autosave: "1", column: { name: "Work", archetype: "execution",
                                                                on_entry_json: "not json" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :unprocessable_entity
    assert_match "column-form-errors", response.body
    assert_match "NOT saved", response.body
    assert_no_match(/modal-body/, response.body)
  end
end
