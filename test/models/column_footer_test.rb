require "test_helper"

class ColumnFooterTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @col = column(@board, "execution")
  end

  test "no footer config renders no rows" do
    assert_equal [], @col.footer_rows
  end

  test "sum_cost totals run cost across the column's cards" do
    card = create_card(@board, "execution", status: "queued")
    create_run(card).update!(cost: 1.25)
    create_run(card).update!(cost: 11.09)
    # A run in another column must not leak in.
    other = create_card(@board, "review", status: "in_review")
    create_run(other).update!(cost: 99.0)

    @col.update!(policy: @col.policy.merge("footer" => [{ "label" => "Total cost:", "compute" => "sum_cost" }]))

    assert_equal [{ label: "Total cost:", value: "$12.34" }], @col.footer_rows
  end

  test "sum_tokens totals input+output tokens with a delimiter" do
    card = create_card(@board, "execution", status: "queued")
    create_run(card).update!(input_tokens: 1_000_000, output_tokens: 234_567)

    @col.update!(policy: @col.policy.merge("footer" => [{ "label" => "Tokens:", "compute" => "sum_tokens" }]))

    assert_equal "1,234,567", @col.footer_rows.first[:value]
  end

  test "count_cards counts cards in the column" do
    2.times { create_card(@board, "execution", status: "queued") }
    @col.update!(policy: @col.policy.merge("footer" => [{ "label" => "Cards:", "compute" => "count_cards" }]))

    assert_equal "2", @col.footer_rows.first[:value]
  end

  test "a static label with no compute renders just the label" do
    @col.update!(policy: @col.policy.merge("footer" => [{ "label" => "Summary" }]))
    assert_equal [{ label: "Summary", value: "" }], @col.footer_rows
  end

  test "an unknown compute key degrades to a blank value" do
    @col.update!(policy: @col.policy.merge("footer" => [{ "label" => "Odd:", "compute" => "sum_bananas" }]))
    assert_equal [{ label: "Odd:", value: "" }], @col.footer_rows
  end

  test "a fully empty row is dropped" do
    @col.update!(policy: @col.policy.merge("footer" => [{ "label" => "", "compute" => "" }]))
    assert_equal [], @col.footer_rows
  end
end
