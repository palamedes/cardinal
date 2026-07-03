require "test_helper"

class ResumeRunJobTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @col = column(@board, "execution")
    @col.update!(policy: { "concurrency_limit" => 1 })
  end

  test "resume defers and re-queues the card when the column is full" do
    create_card(@board, "execution", status: "working", title: "busy")
    parked_card = create_card(@board, "execution", status: "needs_input", title: "parked")
    run = create_run(parked_card, status: "needs_input")

    ResumeRunJob.perform_now(run.id, "here is my answer")

    run.reload
    assert_equal "needs_input", run.status
    assert_equal "here is my answer", run.briefing.dig("pending_resume", "message")
    assert_equal "queued", parked_card.reload.status
  end

  test "second answer while deferred is appended, approve is sticky" do
    create_card(@board, "execution", status: "working", title: "busy")
    parked_card = create_card(@board, "execution", status: "needs_input", title: "parked")
    run = create_run(parked_card, status: "needs_input", phase: "plan")

    ResumeRunJob.perform_now(run.id, "first", approve: true)
    parked_card.update!(status: "needs_input") # simulate user answering again
    ResumeRunJob.perform_now(run.id, "second")

    pending = run.reload.briefing["pending_resume"]
    assert_equal "first\n\nsecond", pending["message"]
    assert pending["approve"]
  end

  test "kick_queue fires the pending resume instead of a fresh run" do
    parked_card = create_card(@board, "execution", status: "queued", title: "parked")
    run = create_run(parked_card, status: "needs_input",
                     briefing: { "pending_resume" => { "message" => "go", "approve" => false } })

    assert_enqueued_with(job: ResumeRunJob, args: [run.id, ""]) do
      @col.kick_queue
    end
    assert_no_enqueued_jobs(only: StartRunJob)
  end
end
