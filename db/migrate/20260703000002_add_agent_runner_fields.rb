class AddAgentRunnerFields < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :external_session_id, :string
    add_column :runs, :phase, :string, null: false, default: "execute"
    add_column :boards, :local_path, :string
  end
end
