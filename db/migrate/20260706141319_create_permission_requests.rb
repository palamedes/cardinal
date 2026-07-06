# Ask-first permission mode: one row per "may I run this?" from an agent.
class CreatePermissionRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :permission_requests do |t|
      t.references :run, null: false, foreign_key: true
      t.string :tool_name, null: false
      t.text :command                 # Bash command text, for display + pattern matching
      t.json :input, default: {}
      t.string :status, null: false, default: "pending" # pending/allowed/denied/auto_denied
      t.text :message                 # denial reason shown to the agent
      t.datetime :answered_at
      t.datetime :created_at, null: false
    end
    add_index :permission_requests, [:run_id, :status]
  end
end
