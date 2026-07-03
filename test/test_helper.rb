ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

class ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # No YAML fixtures — each test builds what it needs.
  def create_board
    board = Board.create!(name: "Test", repo_url: "git@example.com:t/t.git", default_branch: "main")
    %w[inbox planning execution review terminal].each_with_index do |arch, i|
      board.columns.create!(name: arch.capitalize, archetype: arch, position: i,
                            policy: arch == "execution" ? { "concurrency_limit" => 2 } : {})
    end
    board
  end

  def column(board, archetype) = board.columns.find_by!(archetype: archetype)

  def create_card(board, col_archetype = "inbox", **attrs)
    board.cards.create!(column: column(board, col_archetype), title: "Test card", **attrs)
  end

  def create_run(card, status: "running", phase: "execute", briefing: {})
    session = card.agent_sessions.create!(status: "ready")
    session.runs.create!(status: status, phase: phase, briefing: briefing)
  end
end
