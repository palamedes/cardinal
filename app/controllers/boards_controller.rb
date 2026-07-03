class BoardsController < ApplicationController
  def show
    @board = Board.includes(columns: :cards).first!
  end
end
