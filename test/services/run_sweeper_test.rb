require "test_helper"

class RunSweeperTest < ActiveSupport::TestCase
  setup do
    @board = create_board
  end

  test "sweeps runs whose process is gone and heartbeat is stale" do
    card = create_card(@board, "execution", status: "working")
    run = create_run(card)
    run.agent_session.update!(config: { "pid" => 999_999_999 })
    run.update!(heartbeat_at: 10.minutes.ago)

    RunSweeper.sweep
    assert_equal "failed", run.reload.status
    assert_equal "failed", card.reload.status
  end

  test "leaves fresh runs alone" do
    card = create_card(@board, "execution", status: "working")
    run = create_run(card)
    run.update!(heartbeat_at: 10.seconds.ago)

    RunSweeper.sweep
    assert_equal "running", run.reload.status
  end

  # The provisioning window: a just-started run has no pid until the claude
  # process spawns (after clone/fetch). The card must not be declared stuck.
  test "a freshly dragged card provisioning its workspace is not swept" do
    card = create_card(@board, "execution", status: "working")
    create_run(card) # status running, no pid, no heartbeat — just born

    RunSweeper.sweep
    assert_equal "working", card.reload.status
  end

  test "a working card whose only run is long dead with no pid is repaired" do
    card = create_card(@board, "execution", status: "working")
    run = create_run(card)
    run.update!(created_at: 20.minutes.ago, heartbeat_at: nil)

    RunSweeper.sweep
    assert_equal "failed", card.reload.status
    assert_match(/stuck working|lost its runner/, card.events.last.payload["text"])
  end

  test "kicks the queue when slots are free" do
    col = column(@board, "execution")
    card = create_card(@board, "execution", status: "queued")
    assert_enqueued_with(job: StartRunJob, args: [card.id]) do
      RunSweeper.sweep
    end
    assert col
  end

  test "wip limit blocks the kick" do
    col = column(@board, "execution")
    col.update!(policy: { "concurrency_limit" => 1 })
    create_card(@board, "execution", status: "working", title: "busy")
    create_card(@board, "execution", status: "queued", title: "waiting")
    assert_no_enqueued_jobs(only: StartRunJob) do
      col.kick_queue
    end
  end
end
