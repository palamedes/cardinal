require "test_helper"

class RulesCompilerTest < ActiveSupport::TestCase
  test "validate! accepts known actions" do
    assert_nothing_raised do
      Rules::Compiler.validate!([{ "action" => "start_agent_run" },
                                 { "action" => "ai_task", "prompt" => "hi" }])
    end
  end

  test "validate! rejects unknown actions and malformed rules" do
    assert_raises(Rules::Compiler::Error) { Rules::Compiler.validate!([{ "action" => "rm_rf" }]) }
    assert_raises(Rules::Compiler::Error) { Rules::Compiler.validate!(["nope"]) }
    assert_raises(Rules::Compiler::Error) { Rules::Compiler.validate!({ "action" => "merge_pr" }) }
  end

  test "compile without the claude CLI raises a helpful error" do
    ClaudeCli.stub(:available?, false) do
      err = assert_raises(Rules::Compiler::Error) { Rules::Compiler.compile("do things") }
      assert_match(/claude CLI/, err.message)
    end
  end

  test "compile parses and validates the CLI's output" do
    ClaudeCli.stub(:prompt, "```json\n[{\"action\": \"start_agent_run\"}]\n```") do
      assert_equal [{ "action" => "start_agent_run" }], Rules::Compiler.compile("start the agent")
    end
  end
end
