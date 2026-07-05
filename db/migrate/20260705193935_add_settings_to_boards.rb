# Board-level knobs (first tenant: which columns may drag-to-archive).
class AddSettingsToBoards < ActiveRecord::Migration[8.1]
  def change
    add_column :boards, :settings, :json, default: {}, null: false
  end
end
