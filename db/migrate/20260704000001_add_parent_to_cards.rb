class AddParentToCards < ActiveRecord::Migration[8.1]
  def change
    add_reference :cards, :parent, foreign_key: { to_table: :cards }, null: true
  end
end
