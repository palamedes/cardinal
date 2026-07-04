class AddCompactToCards < ActiveRecord::Migration[8.1]
  def change
    add_column :cards, :compact, :text
    add_column :cards, :compact_generated_at, :datetime
    add_column :cards, :compact_status, :string
  end
end
