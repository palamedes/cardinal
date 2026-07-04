require "test_helper"

class RunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @board = create_board
  end

  test "restart resumes a run parked on the turn budget" do
    card = create_card(@board, "execution", status: "needs_input")
    run = create_run(card, status: "needs_input")
    card.log!("question", actor: "agent", run: run, text: "I've used this segment's turn budget mid-work.")

    assert_enqueued_with(job: ResumeRunJob, args: [run.id, ""]) do
      post restart_run_path(run)
    end
    assert_redirected_to card_path(card)
    assert_equal "needs_input", run.reload.status
  end

  test "restart resumes a failed run whose session survived" do
    card = create_card(@board, "execution", status: "failed")
    run = create_run(card, status: "failed")
    run.update!(result_summary: "hit this segment's max-turns budget", external_session_id: "sess-123")

    assert_enqueued_with(job: ResumeRunJob, args: [run.id, ""]) do
      post restart_run_path(run)
    end
    assert_equal "needs_input", run.reload.status
    assert_nil run.finished_at
    assert_equal "needs_input", card.reload.status
  end

  test "restart starts a fresh run when no session remains" do
    card = create_card(@board, "execution", status: "failed")
    run = create_run(card, status: "failed")
    run.update!(result_summary: "hit this segment's max-turns budget")

    assert_enqueued_with(job: StartRunJob, args: [card.id]) do
      post restart_run_path(run)
    end
    assert_equal "queued", card.reload.status
    assert_equal "failed", run.reload.status
  end

  # Card #37: approving a plan resumes the run, then streams a self-dismissing
  # flash so the modal minimizes back to the board.
  test "approve advances a parked plan and streams a self-dismissing flash" do
    card = create_card(@board, "execution", status: "needs_input")
    run = create_run(card, status: "needs_input", phase: "plan")
    card.log!("question", actor: "agent", run: run, text: "Here's my plan — approve to execute.")

    assert_enqueued_with(job: ResumeRunJob) do
      post approve_run_path(run), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_match "plan-callout", response.body
    assert_match 'data-controller="dismiss"', response.body
  end

  test "restart is a no-op for a non-restartable run" do
    card = create_card(@board, "execution", status: "failed")
    run = create_run(card, status: "failed")
    run.update!(result_summary: "agent did not finish cleanly (exit 1)")

    assert_no_enqueued_jobs do
      post restart_run_path(run)
    end
    assert_equal "failed", run.reload.status
  end
end
