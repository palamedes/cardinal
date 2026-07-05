class AddAsanaUrlToCards < ActiveRecord::Migration[8.1]
  def change
    add_column :cards, :asana_url, :string
  end
end
