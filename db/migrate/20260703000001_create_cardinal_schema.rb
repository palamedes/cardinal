class CreateCardinalSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :boards do |t|
      t.string :name, null: false
      t.string :repo_url
      t.string :default_branch, null: false, default: "main"
      t.timestamps
    end

    create_table :columns do |t|
      t.references :board, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false
      t.string :archetype, null: false, default: "inbox"
      t.json :policy, null: false, default: {}
      t.timestamps
    end
    add_index :columns, [:board_id, :position]

    create_table :cards do |t|
      t.references :board, null: false, foreign_key: true
      t.references :column, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :title, null: false
      t.text :description
      t.json :tags, null: false, default: []
      t.integer :position, null: false
      t.string :status, null: false, default: "draft"
      t.string :branch_name
      t.string :pr_url
      t.string :pr_state
      t.timestamps
    end
    add_index :cards, [:board_id, :number], unique: true
    add_index :cards, [:column_id, :position]

    create_table :agent_sessions do |t|
      t.references :card, null: false, foreign_key: true
      t.string :status, null: false, default: "provisioning"
      t.string :workspace_ref
      t.string :model
      t.json :config, null: false, default: {}
      t.timestamps
    end

    create_table :runs do |t|
      t.references :agent_session, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.json :briefing, null: false, default: {}
      t.text :result_summary
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.decimal :cost, precision: 10, scale: 4, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :heartbeat_at
      t.timestamps
    end

    create_table :events do |t|
      t.references :card, null: false, foreign_key: true
      t.references :run, foreign_key: true
      t.string :kind, null: false
      t.string :actor, null: false, default: "system"
      t.json :payload, null: false, default: {}
      t.timestamps
    end
    add_index :events, [:card_id, :created_at]

    create_table :artifacts do |t|
      t.references :run, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :name, null: false
      t.json :payload, null: false, default: {}
      t.timestamps
    end
  end
end
