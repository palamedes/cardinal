require "test_helper"

class RunTest < ActiveSupport::TestCase
  setup do
    @board = create_board
  end

  test "restartable when parked on the turn budget" do
    card = create_card(@board, "execution", status: "needs_input")
    run = create_run(card, status: "needs_input")
    card.log!("question", actor: "agent", run: run,
              text: "I've used this segment's turn budget mid-work. Reply (anything) to continue.")

    assert run.exhausted?
    assert run.restartable?
  end

  test "not restartable for a genuine question" do
    card = create_card(@board, "execution", status: "needs_input")
    run = create_run(card, status: "needs_input")
    card.log!("question", actor: "agent", run: run, text: "Which database should I use?")

    assert_not run.exhausted?
    assert_not run.restartable?
  end

  test "restartable when a run failed on max-turns" do
    card = create_card(@board, "execution", status: "failed")
    run = create_run(card, status: "failed")
    run.update!(result_summary: "hit this segment's max-turns budget — raise Max turns in the column's gear settings, or split the card")

    assert run.exhausted?
    assert run.restartable?
  end

  test "restartable when a run timed out" do
    card = create_card(@board, "execution", status: "failed")
    run = create_run(card, status: "failed")
    run.update!(result_summary: "timed out after 30 minutes and was stopped — raise the column's timeout")

    assert run.restartable?
  end

  test "not restartable for a non-exhaustion failure" do
    card = create_card(@board, "execution", status: "failed")
    run = create_run(card, status: "failed")
    run.update!(result_summary: "agent did not finish cleanly (exit 1)")

    assert_not run.exhausted?
    assert_not run.restartable?
  end

  test "not restartable outside an execution column" do
    card = create_card(@board, "review", status: "in_review")
    run = create_run(card, status: "failed")
    run.update!(result_summary: "hit this segment's max-turns budget")

    assert run.exhausted?
    assert_not run.restartable?
  end
end
