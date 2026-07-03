class AddRepoBriefToBoards < ActiveRecord::Migration[8.1]
  def change
    add_column :boards, :brief_sha, :string
    add_column :boards, :brief_generated_at, :datetime
    add_column :boards, :brief_model, :string
    add_column :boards, :brief_status, :string
  end
end
