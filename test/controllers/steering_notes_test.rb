require "test_helper"

# Card #47: talk to a card without burning tokens (note only) and steer a
# working agent (notes deliver at the next segment boundary).
class SteeringNotesTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "N", default_branch: "main")
    %w[inbox planning execution].each_with_index do |arch, i|
      @board.columns.create!(name: arch.capitalize, archetype: arch, position: i, policy: {})
    end
  end

  test "a note-only message logs without invoking any AI" do
    card = @board.cards.create!(column: @board.columns.find_by!(archetype: "planning"),
                                title: "quiet", status: "discussing")
    assert_no_enqueued_jobs do
      post card_messages_path(card), params: { message: { text: "For the next agent: skip the CSS.", note: "1" } }
    end
    event = card.events.where(kind: "user_message").last
    assert event.payload["note"]
    assert_not card.reload.awaiting_assistant?, "a note must not flip the thinking pencil"
  end

  test "a message to a working agent queues as steering and delivers on resume" do
    col = @board.columns.find_by!(archetype: "execution")
    card = @board.cards.create!(column: col, title: "steer me", status: "working")
    session = card.agent_sessions.create!(status: "ready")
    run = session.runs.create!(status: "running", phase: "execute", briefing: {})

    assert_no_enqueued_jobs do
      post card_messages_path(card), params: { message: { text: "Use the existing helper." } }
    end
    assert_equal ["Use the existing helper."], run.reload.briefing["steering"]
    assert_match(/queued for the agent/i, card.events.last.payload["text"])

    # Boundary reached: the run parks, the user answers, notes ride along.
    run.update!(status: "needs_input")
    delivered = []
    Agent::Runner.stub(:resume, ->(r, msg, approve: false) { delivered << msg }) do
      ResumeRunJob.perform_now(run.id, "continue")
    end
    assert_equal 1, delivered.size
    assert_match(/Notes the user left while you were working:\n- Use the existing helper\./, delivered.first)
    assert_match(/continue/, delivered.first)
    assert_nil run.reload.briefing["steering"], "delivered notes must not redeliver"
  end
end
