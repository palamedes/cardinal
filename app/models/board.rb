class Board < ApplicationRecord
  # Captured from the author's live board (2026-07-05) — the battle-tested
  # layout. accepts_from is stored as NAMES here and resolved to column ids
  # by install_default_columns! (ids don't exist until creation).
  DEFAULT_COLUMNS = [
    { name: "Tasks",       archetype: "inbox",
      policy: { "plan_approval" => false,
                "accepts_from_names" => ["Planning", "Review", "QA", "Done"] } },
    { name: "Planning",    archetype: "planning",
      policy: { "ai" => true, "model" => "claude-haiku-4-5-20251001", "plan_approval" => false,
                "on_entry" => [{ "action" => "assistant_greeting" }],
                "on_entry_text" => "The planning assistant reads the card and opens the discussion.",
                "accepts_from_names" => ["Tasks", "In Progress", "Review", "QA"] } },
    { name: "In Progress", archetype: "execution",
      policy: { "ai" => true, "model" => "claude-opus-4-8", "effort" => "high",
                "concurrency_limit" => 3, "plan_approval" => true,
                "budget_per_run_cents" => 200, "timeout_minutes" => 90, "max_turns" => 80,
                "tools" => %w[read edit run_commands git_commit_push],
                "on_entry" => [{ "action" => "start_agent_run" }],
                "accepts_from_names" => ["Planning", "Review", "QA"],
                "instructions" => "Follow repo conventions. Write tests when the repo has a suite." } },
    { name: "Review",      archetype: "review",
      policy: { "ai" => true, "plan_approval" => false,
                "accepts_from_names" => ["In Progress", "QA"],
                "on_entry" => [{ "action" => "mark_pr_ready" }],
                "on_entry_text" => "Take the PR out of draft — mark it ready for review on GitHub." } },
    { name: "QA",          archetype: "review",
      policy: { "ai" => true, "plan_approval" => false,
                "accepts_from_names" => ["Review"],
                "on_entry" => [{ "action" => "mark_pr_ready" }] } },
    { name: "Done",        archetype: "terminal",
      policy: { "ai" => false, "plan_approval" => false, "arrivals" => "top",
                "accepts_from_names" => ["Review", "QA", "Planning"],
                "on_entry" => [{ "action" => "merge_pr" }] } }
  ].freeze

  # Create the default columns, then resolve accepts_from_names -> ids.
  def install_default_columns!
    DEFAULT_COLUMNS.each_with_index do |attrs, index|
      columns.create!(name: attrs[:name], archetype: attrs[:archetype], position: index,
                      policy: attrs[:policy].except("accepts_from_names"))
    end
    DEFAULT_COLUMNS.each do |attrs|
      names = attrs[:policy]["accepts_from_names"] or next
      col = columns.find_by!(name: attrs[:name])
      ids = columns.where(name: names).pluck(:id).map(&:to_s)
      col.update!(policy: col.policy.merge("accepts_from" => ids))
    end
  end

  has_many :columns, -> { order(:position) }, dependent: :destroy
  has_many :cards, dependent: :destroy

  validates :name, presence: true

  # First-run setup for a portable instance (cardinal.md §16): build the board
  # from the repo Cardinal was launched inside.
  def self.bootstrap!(repo_path)
    repo_path = File.expand_path(repo_path)
    # Raw configured URL (get-url applies insteadOf rewrites, which can embed
    # credential-helper tokens); strip any userinfo defensively either way.
    origin, origin_ok = Open3.capture2e("git", "-C", repo_path, "config", "--get", "remote.origin.url")
    branch, branch_ok = Open3.capture2e("git", "-C", repo_path, "rev-parse", "--abbrev-ref", "HEAD")

    board = create!(
      name: File.basename(repo_path),
      repo_url: origin_ok.success? ? sanitize_remote_url(origin.strip) : nil,
      default_branch: branch_ok.success? && branch.strip.present? ? branch.strip : "main",
      local_path: repo_path
    )
    board.install_default_columns!
    board
  end

  def self.sanitize_remote_url(url)
    # Drop any userinfo (tokens from credential-helper rewrites). Regex, not
    # URI#userinfo= — Ruby 3.4's RFC3986 parser silently ignores that setter.
    url.sub(%r{\A(\w+://)[^@/]+@}, '\1')
  end

  # Every tag in use on this board — the pool the tag picker offers.
  def tag_pool
    cards.pluck(:tags).flatten.compact.uniq.sort
  end

  # --- Repo brief (card #12) ---------------------------------------------
  # A one-time deep dive that maps the repo, stored as flat markdown in
  # .cardinal/ (never the host repo) and injected into worker prompts to
  # spare each run the exploration tax. Metadata (which SHA/model/when) lives
  # on the board so staleness can be judged against the current HEAD.
  #
  # Storage is a file + metadata, not one text column, so a structure
  # provider (the Graphify child card) can slot a richer representation in
  # underneath later without a migration.
  BRIEF_STALE_AT = 10 # commits behind → the "refresh me" red/flashing state

  # Honor CARDINAL_DATA_DIR: in gem mode Rails.root is the installed gem
  # (read-only); the instance's data lives in the target repo's .cardinal/.
  def brief_path
    Pathname(File.expand_path(ENV["CARDINAL_DATA_DIR"].presence || Rails.root.join(".cardinal"))).join("repo-brief.md")
  end

  def repo_brief
    File.read(brief_path) if File.exist?(brief_path)
  end

  def brief?
    brief_sha.present? && File.exist?(brief_path)
  end

  def brief_working? = brief_status == "working"

  # HEAD of the board's repo right now — the yardstick staleness measures against.
  def head_sha
    return nil if local_path.blank?
    out, ok = Open3.capture2e("git", "-C", local_path, "rev-parse", "HEAD")
    ok.success? ? out.strip : nil
  end

  # How many commits landed since the brief was generated. nil when there's
  # no brief (nothing to be stale against) or the SHA is unknown to the repo.
  def commits_behind_brief
    return @commits_behind_brief if defined?(@commits_behind_brief)
    @commits_behind_brief =
      if brief_sha.blank? || local_path.blank?
        nil
      else
        out, ok = Open3.capture2e("git", "-C", local_path, "rev-list", "--count", "#{brief_sha}..HEAD")
        ok.success? ? out.strip.to_i : nil
      end
  end

  def brief_stale? = (commits_behind_brief || 0) >= BRIEF_STALE_AT

  # Grey → red interpolation over 0..BRIEF_STALE_AT commits behind, emitted
  # as a validated hex into the button's inline style (mirrors Column#safe_color).
  # Deep red once the brief is stale enough to over-anchor on.
  def brief_staleness_color
    behind = commits_behind_brief || 0
    grey = [0x8a, 0x8a, 0x8a]
    red  = [0xd4, 0x33, 0x33]
    t = [behind.to_f / BRIEF_STALE_AT, 1.0].min
    rgb = grey.zip(red).map { |g, r| (g + (r - g) * t).round }
    format("#%02x%02x%02x", *rgb)
  end

  # Cards currently waiting on the human, ordered by urgency — feeds the
  # attention inbox in the board header.
  def attention_cards
    cards.where(status: %w[needs_input failed work_complete])
         .order(Arel.sql("CASE status WHEN 'needs_input' THEN 0 WHEN 'failed' THEN 1 ELSE 2 END"), updated_at: :asc)
  end
end
