class Board < ApplicationRecord
  # Captured from the author's live board (2026-07-05) — the battle-tested
  # layout. accepts_from is stored as NAMES here and resolved to column ids
  # by install_default_columns! (ids don't exist until creation).
  DEFAULT_COLUMNS = [
    { name: "Tasks",       archetype: "inbox",
      policy: { "plan_approval" => false,
                "accepts_from_names" => ["Planning", "Review", "QA", "Done"] } },
    { name: "Planning",    archetype: "planning",
      policy: { "ai" => true, "model" => "claude-haiku-4-5-20251001", "plan_approval" => false } },
    { name: "In Progress", archetype: "execution",
      policy: { "ai" => true, "model" => "claude-opus-4-8", "effort" => "high",
                "concurrency_limit" => 3, "plan_approval" => true,
                "budget_per_run_cents" => 200, "timeout_minutes" => 90, "max_turns" => 80,
                "tools" => %w[read edit run_commands git_commit_push],
                "on_entry" => [{ "action" => "start_agent_run" }],
                "instructions" => "Follow repo conventions. Write tests when the repo has a suite." } },
    { name: "Review",      archetype: "review",
      policy: { "ai" => true, "plan_approval" => false,
                "on_entry" => [{ "action" => "mark_pr_ready" }],
                "on_entry_text" => "Take the PR out of draft — mark it ready for review on GitHub." } },
    { name: "QA",          archetype: "review",
      policy: { "ai" => true, "plan_approval" => false,
                "on_entry" => [{ "action" => "mark_pr_ready" }] } },
    { name: "Done",        archetype: "terminal",
      policy: { "ai" => false, "plan_approval" => false, "arrivals" => "top",
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

  # Cards currently waiting on the human, ordered by urgency — feeds the
  # attention inbox in the board header.
  def attention_cards
    cards.where(status: %w[needs_input failed work_complete])
         .order(Arel.sql("CASE status WHEN 'needs_input' THEN 0 WHEN 'failed' THEN 1 ELSE 2 END"), updated_at: :asc)
  end
end
