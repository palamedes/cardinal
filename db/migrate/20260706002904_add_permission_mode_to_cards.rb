class AddPermissionModeToCards < ActiveRecord::Migration[8.1]
  def change
    add_column :cards, :permission_mode, :string
  end
end
