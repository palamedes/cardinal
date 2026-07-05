# Usage ledger for every one-shot AI call (card #-less deep dives included).
# Worker runs track their own usage on Run; this covers the ClaudeCli tier:
# planning assistant, ai_task rules, deep dive, summary/compact, compiler.
class CreateAiCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_calls do |t|
      t.references :card, foreign_key: true, null: true
      t.string :kind, null: false
      t.string :model
      t.integer :input_tokens, default: 0, null: false
      t.integer :output_tokens, default: 0, null: false
      t.decimal :cost, precision: 10, scale: 6, default: 0, null: false
      t.datetime :created_at, null: false
    end
    add_index :ai_calls, :kind
  end
end
