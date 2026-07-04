require "test_helper"

class SummaryJobTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @card = create_card(@board, "execution", status: "work_complete", title: "Add dark mode")
    @card.log!("progress", actor: "agent", text: "Implemented the theme toggle")
  end

  test "synthesizes a summary and stamps the card" do
    used = nil
    ClaudeCli.stub(:available?, true) do
      ClaudeCli.stub(:prompt, ->(prompt, **) { used = prompt; "We added a dark mode you can toggle on." }) do
        SummaryJob.perform_now(@card)
      end
    end

    @card.reload
    assert_equal "We added a dark mode you can toggle on.", @card.summary
    assert_not_nil @card.summary_generated_at
    assert_nil @card.summary_status # working flag cleared
    # The card's own context feeds the prompt.
    assert_match "Add dark mode", used
    assert_match "Implemented the theme toggle", used
  end

  test "a prior summary rides along as context for a regeneration" do
    @card.update!(summary: "Customer wanted a night theme.")
    used = nil
    ClaudeCli.stub(:available?, true) do
      ClaudeCli.stub(:prompt, ->(prompt, **) { used = prompt; "refined" }) do
        SummaryJob.perform_now(@card)
      end
    end
    assert_match "Customer wanted a night theme.", used
  end

  test "clears the working flag when the CLI is unavailable" do
    @card.update!(summary_status: "working")
    ClaudeCli.stub(:available?, false) do
      SummaryJob.perform_now(@card)
    end
    assert_nil @card.reload.summary_status
    assert_nil @card.summary # never written
  end

  test "a failed generation does not leave the button stuck on working" do
    @card.update!(summary_status: "working")
    ClaudeCli.stub(:available?, true) do
      ClaudeCli.stub(:prompt, ->(*) { raise ClaudeCli::Error.new("boom") }) do
        SummaryJob.perform_now(@card)
      end
    end
    assert_nil @card.reload.summary_status
  end
end
