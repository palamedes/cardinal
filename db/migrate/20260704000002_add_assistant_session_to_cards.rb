class AddAssistantSessionToCards < ActiveRecord::Migration[8.1]
  def change
    add_column :cards, :assistant_session_id, :string
  end
end
