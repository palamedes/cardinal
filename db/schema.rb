# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_06_141319) do
  create_table "agent_sessions", force: :cascade do |t|
    t.integer "card_id", null: false
    t.json "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "model"
    t.string "status", default: "provisioning", null: false
    t.datetime "updated_at", null: false
    t.string "workspace_ref"
    t.index ["card_id"], name: "index_agent_sessions_on_card_id"
  end

  create_table "ai_calls", force: :cascade do |t|
    t.integer "card_id"
    t.decimal "cost", precision: 10, scale: 6, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.integer "input_tokens", default: 0, null: false
    t.string "kind", null: false
    t.string "model"
    t.integer "output_tokens", default: 0, null: false
    t.index ["card_id"], name: "index_ai_calls_on_card_id"
    t.index ["kind"], name: "index_ai_calls_on_kind"
  end

  create_table "artifacts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.string "name", null: false
    t.json "payload", default: {}, null: false
    t.integer "run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id"], name: "index_artifacts_on_run_id"
  end

  create_table "boards", force: :cascade do |t|
    t.datetime "brief_generated_at"
    t.string "brief_model"
    t.string "brief_sha"
    t.string "brief_status"
    t.datetime "created_at", null: false
    t.string "default_branch", default: "main", null: false
    t.string "local_path"
    t.string "name", null: false
    t.string "repo_url"
    t.json "settings", default: {}, null: false
    t.datetime "updated_at", null: false
  end

  create_table "cards", force: :cascade do |t|
    t.string "asana_url"
    t.string "assistant_session_id"
    t.integer "board_id", null: false
    t.string "branch_name"
    t.integer "column_id", null: false
    t.text "compact"
    t.datetime "compact_generated_at"
    t.string "compact_status"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "effort"
    t.integer "issue_number"
    t.string "model"
    t.integer "number", null: false
    t.integer "parent_id"
    t.string "permission_mode"
    t.integer "position", null: false
    t.string "pr_state"
    t.string "pr_url"
    t.string "status", default: "draft", null: false
    t.text "summary"
    t.datetime "summary_generated_at"
    t.string "summary_status"
    t.json "tags", default: [], null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["board_id", "number"], name: "index_cards_on_board_id_and_number", unique: true
    t.index ["board_id"], name: "index_cards_on_board_id"
    t.index ["column_id", "position"], name: "index_cards_on_column_id_and_position"
    t.index ["column_id"], name: "index_cards_on_column_id"
    t.index ["parent_id"], name: "index_cards_on_parent_id"
  end

  create_table "columns", force: :cascade do |t|
    t.string "archetype", default: "inbox", null: false
    t.integer "board_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.json "policy", default: {}, null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["board_id", "position"], name: "index_columns_on_board_id_and_position"
    t.index ["board_id"], name: "index_columns_on_board_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "actor", default: "system", null: false
    t.integer "card_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.json "payload", default: {}, null: false
    t.integer "run_id"
    t.datetime "updated_at", null: false
    t.index ["card_id", "created_at"], name: "index_events_on_card_id_and_created_at"
    t.index ["card_id"], name: "index_events_on_card_id"
    t.index ["run_id"], name: "index_events_on_run_id"
  end

  create_table "permission_requests", force: :cascade do |t|
    t.datetime "answered_at"
    t.text "command"
    t.datetime "created_at", null: false
    t.json "input", default: {}
    t.text "message"
    t.integer "run_id", null: false
    t.string "status", default: "pending", null: false
    t.string "tool_name", null: false
    t.index ["run_id", "status"], name: "index_permission_requests_on_run_id_and_status"
    t.index ["run_id"], name: "index_permission_requests_on_run_id"
  end

  create_table "runs", force: :cascade do |t|
    t.integer "agent_session_id", null: false
    t.json "briefing", default: {}, null: false
    t.decimal "cost", precision: 10, scale: 4, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "external_session_id"
    t.datetime "finished_at"
    t.datetime "heartbeat_at"
    t.integer "input_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.string "phase", default: "execute", null: false
    t.text "result_summary"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_session_id"], name: "index_runs_on_agent_session_id"
  end

  add_foreign_key "agent_sessions", "cards"
  add_foreign_key "ai_calls", "cards"
  add_foreign_key "artifacts", "runs"
  add_foreign_key "cards", "boards"
  add_foreign_key "cards", "cards", column: "parent_id"
  add_foreign_key "cards", "columns"
  add_foreign_key "columns", "boards"
  add_foreign_key "events", "cards"
  add_foreign_key "events", "runs"
  add_foreign_key "permission_requests", "runs"
  add_foreign_key "runs", "agent_sessions"
end
