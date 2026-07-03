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

  test "compile without an API key raises a helpful error" do
    original = ENV.delete("ANTHROPIC_API_KEY")
    err = assert_raises(Rules::Compiler::Error) { Rules::Compiler.compile("do things") }
    assert_match(/ANTHROPIC_API_KEY/, err.message)
  ensure
    ENV["ANTHROPIC_API_KEY"] = original if original
  end
end
