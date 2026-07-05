require "test_helper"
require "tmpdir"

# Asana import (card #7): URL in, card out; first use is a connect wizard.
class AsanaServiceTest < ActiveSupport::TestCase
  test "task gid is the last long digit run across URL vintages" do
    assert_equal "1205000000000002",
                 Asana.task_gid("https://app.asana.com/0/1200000000000001/1205000000000002")
    assert_equal "1205000000000002",
                 Asana.task_gid("https://app.asana.com/0/1200000000000001/1205000000000002/f")
    assert_equal "99988877766655",
                 Asana.task_gid("https://app.asana.com/1/111222333/project/444555666777/task/99988877766655?focus=true")
    assert_raises(Asana::Error) { Asana.task_gid("https://example.com/nope") }
  end

  test "import creates an inbox card with title, notes, tags, and backlink; re-import dedupes" do
    board = create_board
    payload = { "name" => "Fix the login loop", "notes" => "Steps to repro…",
                "permalink_url" => "https://app.asana.com/0/1/120500000000",
                "tags" => [{ "name" => "bug" }, { "name" => "auth" }] }
    Asana.stub(:token, "t") do
      Asana.stub(:request, payload) do
        2.times { Asana.import!(board, "https://app.asana.com/0/1/120500000000") }
      end
    end
    cards = board.cards.where(asana_url: "https://app.asana.com/0/1/120500000000")
    assert_equal 1, cards.count
    card = cards.first
    assert_equal "Fix the login loop", card.title
    assert_equal %w[bug auth], card.tags
    assert_match(/Imported from Asana/, card.description)
    assert_equal "inbox", card.column.archetype
  end

  test "token lives as a 0600 file under the data dir" do
    Dir.mktmpdir do |dir|
      prev = ENV["CARDINAL_DATA_DIR"]
      ENV["CARDINAL_DATA_DIR"] = dir
      begin
        assert_not Asana.connected?
        Asana.save_token!("1/secret\n")
        assert Asana.connected?
        assert_equal "1/secret", Asana.token
        assert_equal "600", File.stat(Asana.token_path).mode.to_s(8)[-3..]
        Asana.disconnect!
        assert_not Asana.connected?
      ensure
        ENV["CARDINAL_DATA_DIR"] = prev
      end
    end
  end
end

class AsanaFlowTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "AS", default_branch: "main")
    @board.columns.create!(name: "Tasks", archetype: "inbox", position: 0, policy: {})
  end

  test "unconnected shows the PAT wizard; connected shows the URL prompt" do
    Asana.stub(:connected?, false) do
      get asana_new_card_path, headers: { "Turbo-Frame" => "modal" }
      assert_match "One-time setup", response.body
      assert_select "input[name=token]"
    end
    Asana.stub(:connected?, true) do
      get asana_new_card_path, headers: { "Turbo-Frame" => "modal" }
      assert_select "input[name=url]"
      assert_match "Unlink Asana", response.body
    end
  end

  test "a bad token bounces back into the wizard with the reason" do
    Asana.stub(:verify!, ->(_) { raise Asana::Error, "Asana said no (HTTP 401)" }) do
      post asana_connect_path, params: { token: "junk" }
    end
    assert_redirected_to asana_new_card_path(error: "Asana said no (HTTP 401)")
  end

  test "import lands on the new card" do
    card = @board.cards.create!(column: @board.columns.first!, title: "imported")
    Asana.stub(:import!, card) do
      post asana_import_path, params: { url: "https://app.asana.com/0/1/2222222222" }
    end
    assert_redirected_to card_path(card)
  end

  test "the new-card modal offers New from Asana on the actions row" do
    get new_card_path, headers: { "Turbo-Frame" => "modal" }
    assert_select ".card-edit-actions a.asana-entry[href=?]", asana_new_card_path
  end
end
