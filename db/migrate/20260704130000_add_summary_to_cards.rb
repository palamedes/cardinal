class AddSummaryToCards < ActiveRecord::Migration[8.1]
  def change
    add_column :cards, :summary, :text
    add_column :cards, :summary_generated_at, :datetime
    add_column :cards, :summary_status, :string
  end
end
