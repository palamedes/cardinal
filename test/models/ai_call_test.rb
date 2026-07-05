require "test_helper"

# The AI usage ledger (§ money honesty): every ClaudeCli call is counted, so
# a card's $ figure includes its planning conversation, not just agent runs.
class AiCallTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @card = create_card(@board, "planning", status: "discussing")
  end

  CLI_JSON = {
    "subtype" => "success", "is_error" => false, "result" => "Sharp question!",
    "session_id" => "s-1", "total_cost_usd" => 0.0421,
    "usage" => { "input_tokens" => 900, "output_tokens" => 150 }
  }.freeze

  test "a ledgered prompt records kind, card, tokens, and cost" do
    ClaudeCli.stub(:available?, true) do
      ClaudeCli.stub(:invoke, CLI_JSON.dup) do
        ClaudeCli.prompt("hi", ledger: { kind: "assistant", card: @card })
      end
    end
    call = AiCall.last
    assert_equal "assistant", call.kind
    assert_equal @card.id, call.card_id
    assert_equal 900, call.input_tokens
    assert_equal 150, call.output_tokens
    assert_in_delta 0.0421, call.cost.to_f, 0.0001
  end

  test "a failed call is still recorded — it cost money" do
    failed = CLI_JSON.merge("subtype" => "error_during_execution", "is_error" => true)
    assert_raises(ClaudeCli::Error) do
      ClaudeCli.stub(:available?, true) do
        ClaudeCli.stub(:invoke, failed) do
          ClaudeCli.prompt("hi", ledger: { kind: "ai_task", card: @card })
        end
      end
    end
    assert_equal 1, AiCall.where(kind: "ai_task").count
  end

  test "no ledger option, no row — and a ledger failure never breaks the call" do
    result = ClaudeCli.stub(:available?, true) do
      ClaudeCli.stub(:invoke, CLI_JSON.dup) { ClaudeCli.prompt("hi") }
    end
    assert_equal "Sharp question!", result
    assert_equal 0, AiCall.count
  end

  test "card totals include ledger spend alongside runs" do
    run = create_run(@card)
    run.update!(cost: 0.50, output_tokens: 1000)
    @card.ai_calls.create!(kind: "assistant", cost: 0.12, input_tokens: 400, output_tokens: 80)

    assert_in_delta 0.62, @card.total_cost.to_f, 0.001
    assert_equal 1080, @card.total_output_tokens
    assert_in_delta 0.12, @card.assistant_cost.to_f, 0.001
  end

  test "column sum_cost footer counts one-shot spend of its cards" do
    col = @card.column
    @card.ai_calls.create!(kind: "assistant", cost: 0.25)
    assert_equal "$0.25", col.footer_value("sum_cost")
  end
end
