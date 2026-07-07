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

class SummaryShareTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "SS", default_branch: "main")
    col = @board.columns.create!(name: "Review", archetype: "review", position: 0, policy: {})
    @card = @board.cards.create!(column: col, title: "share me", status: "in_review",
                                 summary: "We fixed the login loop.",
                                 asana_url: "https://app.asana.com/0/1/1205000000000000",
                                 pr_url: "https://github.com/o/r/pull/3")
  end

  test "the summary panel shows share buttons only for connected destinations" do
    Asana.stub(:connected?, true) do
      get card_path(@card, zoom: "summary"), headers: { "Turbo-Frame" => "modal" }
    end
    assert_match "Post as comment on Asana task", response.body
    assert_match "Post as comment on PR", response.body

    Asana.stub(:connected?, false) do
      get card_path(@card, zoom: "summary"), headers: { "Turbo-Frame" => "modal" }
    end
    assert_no_match(/Post as comment on Asana task/, response.body)
    assert_match "Post as comment on PR", response.body
  end

  test "sharing to asana posts a comment and logs it" do
    sent = []
    Asana.stub(:comment!, ->(url, text) { sent << [url, text] }) do
      post share_summary_card_path(@card, to: "asana")
    end
    assert_equal [@card.asana_url], sent.map(&:first)
    assert_match(/We fixed the login loop/, sent.first.last)
    assert_match(/posted to the Asana task/, @card.events.last.payload["text"])
  end

  test "sharing to the PR shells to gh and logs failure honestly" do
    ok = Struct.new(:exitstatus) { def success? = exitstatus.zero? }
    calls = []
    fake = ->(*cmd) { calls << cmd; ["", ok.new(0)] }
    Open3.stub(:capture2e, fake) { post share_summary_card_path(@card, to: "pr") }
    assert_equal ["gh", "pr", "comment", @card.pr_url, "--body", "We fixed the login loop."], calls.first
    assert_match(/posted as a PR comment/, @card.events.last.payload["text"])

    failing = ->(*_) { ["gh: no auth", ok.new(1)] }
    Open3.stub(:capture2e, failing) { post share_summary_card_path(@card, to: "pr") }
    assert_match(/Couldn't comment on the PR/, @card.events.last.payload["text"])
  end

  test "an empty summary refuses to share" do
    @card.update!(summary: "")
    Asana.stub(:comment!, ->(*) { flunk "must not post" }) do
      post share_summary_card_path(@card, to: "asana")
    end
    assert_match(/Nothing to share/, @card.events.last.payload["text"])
  end
end

class ShareFlashTest < ActionDispatch::IntegrationTest
  setup do
    @board = Board.create!(name: "SF", default_branch: "main")
    col = @board.columns.create!(name: "Review", archetype: "review", position: 0, policy: {})
    @card = @board.cards.create!(column: col, title: "flash", status: "in_review",
                                 summary: "Done and dusted.",
                                 asana_url: "https://app.asana.com/0/1/1205000000000000")
  end

  # The share bar (and its flash slot) only renders when Asana is connected —
  # stub it, or these tests silently depend on a token file in the checkout.
  test "a turbo-stream share re-renders the panel with a ✓ flash" do
    Asana.stub(:connected?, true) do
      Asana.stub(:comment!, ->(*) {}) do
        post share_summary_card_path(@card, to: "asana"),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end
    assert_match 'target="card_summary"', response.body
    assert_match "✓ Posted to Asana", response.body
  end

  test "a failed share flashes the error state" do
    Asana.stub(:connected?, true) do
      Asana.stub(:comment!, ->(*) { raise Asana::Error, "HTTP 401" }) do
        post share_summary_card_path(@card, to: "asana"),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end
    assert_match "share-err", response.body
    assert_match "Asana refused", response.body
  end
end
