require "test_helper"

class CompactJobTest < ActiveSupport::TestCase
  setup do
    @board = create_board
    @card = create_card(@board, "execution", status: "work_complete", title: "Add dark mode")
    @card.log!("progress", actor: "agent", text: "Implemented the theme toggle in app/assets")
  end

  test "synthesizes a technical compact and stamps the card" do
    used = nil
    ClaudeCli.stub(:available?, true) do
      ClaudeCli.stub(:prompt, ->(prompt, **) { used = prompt; "## Theme toggle\nAdded ThemeController; persists via localStorage." }) do
        CompactJob.perform_now(@card)
      end
    end

    @card.reload
    assert_equal "## Theme toggle\nAdded ThemeController; persists via localStorage.", @card.compact
    assert_not_nil @card.compact_generated_at
    assert_nil @card.compact_status # working flag cleared
    # The card's own technical context feeds the prompt.
    assert_match "Add dark mode", used
    assert_match "Implemented the theme toggle", used
  end

  test "final reports feed the compact prompt" do
    @card.log!("final_report", actor: "agent", text: "Refactored the palette module; blocked on missing API key.")
    used = nil
    ClaudeCli.stub(:available?, true) do
      ClaudeCli.stub(:prompt, ->(prompt, **) { used = prompt; "notes" }) do
        CompactJob.perform_now(@card)
      end
    end
    assert_match "Refactored the palette module", used
  end

  test "a prior compact rides along as context for a regeneration" do
    @card.update!(compact: "Prior notes: uses CSS custom properties.")
    used = nil
    ClaudeCli.stub(:available?, true) do
      ClaudeCli.stub(:prompt, ->(prompt, **) { used = prompt; "refined" }) do
        CompactJob.perform_now(@card)
      end
    end
    assert_match "Prior notes: uses CSS custom properties.", used
  end

  test "clears the working flag when the CLI is unavailable" do
    @card.update!(compact_status: "working")
    ClaudeCli.stub(:available?, false) do
      CompactJob.perform_now(@card)
    end
    assert_nil @card.reload.compact_status
    assert_nil @card.compact # never written
  end

  test "a failed generation does not leave the button stuck on working" do
    @card.update!(compact_status: "working")
    ClaudeCli.stub(:available?, true) do
      ClaudeCli.stub(:prompt, ->(*) { raise ClaudeCli::Error.new("boom") }) do
        CompactJob.perform_now(@card)
      end
    end
    assert_nil @card.reload.compact_status
  end
end
