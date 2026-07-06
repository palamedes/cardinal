require "test_helper"

# Board default → card override → runner restriction (§ permissions).
class PermissionModeTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @card = create_card(@board, "execution", status: "queued")
  end

  test "resolution: board default, card override in both directions" do
    assert @card.effective_permission_bypass?, "default board = full autonomy"

    @board.update!(settings: { "permission_bypass" => false })
    assert_not @card.reload.effective_permission_bypass?, "board off restricts"

    @card.update!(permission_mode: "bypass")
    assert @card.effective_permission_bypass?, "card override beats board"

    @board.update!(settings: {})
    @card.update!(permission_mode: "ask")
    assert_not @card.effective_permission_bypass?, "card can restrict itself on a permissive board"
  end

  test "the runner restricts for a column shell-off OR a resolved permission-off, and the card cannot reopen a closed column" do
    run = create_run(@card)
    runner = Agent::Runner.new(run)
    assert_not runner.send(:restricted_tools?)

    @board.update!(settings: { "permission_bypass" => false })
    assert Agent::Runner.new(create_run(@card.reload)).send(:restricted_tools?)

    @card.update!(permission_mode: "bypass")
    assert_not Agent::Runner.new(create_run(@card.reload)).send(:restricted_tools?)

    @card.column.update!(policy: @card.column.policy.merge("shell" => false))
    assert Agent::Runner.new(create_run(@card.reload)).send(:restricted_tools?),
           "a card override must not reopen a column whose shell is off"
  end
end

class PermissionSettingsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "P", default_branch: "main")
    @col = @board.columns.create!(name: "t", archetype: "inbox", position: 0, policy: {})
  end

  test "the board settings checkbox round-trips" do
    patch board_path(autosave: 1), params: { board: { permission_bypass: "0" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_not @board.reload.permission_bypass?

    patch board_path(autosave: 1), params: { board: { permission_bypass: "1" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert @board.reload.permission_bypass?
  end

  test "card permission_mode saves and rejects junk" do
    card = @board.cards.create!(column: @col, title: "p")
    patch card_path(card), params: { autosave: "1", card: { permission_mode: "ask" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal "ask", card.reload.permission_mode

    patch card_path(card), params: { autosave: "1", card: { permission_mode: "sudo" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_nil card.reload.permission_mode
  end
end
