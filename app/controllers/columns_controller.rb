class ColumnsController < ApplicationController
  def create
    board = Board.first!
    attrs = params.require(:column).permit(:name, :archetype)
    board.columns.create!(
      name: attrs[:name],
      archetype: attrs[:archetype].presence_in(Column::ARCHETYPES) || "inbox",
      position: (board.columns.maximum(:position) || -1) + 1,
      policy: {}
    )
    redirect_to root_path
  end
end
