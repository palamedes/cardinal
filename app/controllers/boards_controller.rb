class BoardsController < ApplicationController
  def show
    @board = Board.includes(columns: :cards).first!
  end

  # Kick off the repo deep dive (card #12). Non-blocking: flip the board into
  # its "Working" state, morph the topbar so the button reflects it, and let
  # DeepDiveJob do the read-only exploration in the background. Ignored if a
  # dive is already running.
  def deep_dive
    board = Board.first!
    unless board.brief_working?
      board.update!(brief_status: "working")
      board.broadcast_refresh_to board
      DeepDiveJob.perform_later(board)
    end
    redirect_to root_path
  end
end
