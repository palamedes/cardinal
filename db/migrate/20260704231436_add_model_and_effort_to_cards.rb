class AddModelAndEffortToCards < ActiveRecord::Migration[8.1]
  def change
    add_column :cards, :model, :string
    add_column :cards, :effort, :string
  end
end
