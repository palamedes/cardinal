class Board < ApplicationRecord
  DEFAULT_COLUMNS = [
    { name: "Tasks",       archetype: "inbox",     policy: {} },
    { name: "Planning",    archetype: "planning",  policy: { "model" => "claude-haiku-4-5-20251001" } },
    { name: "In Progress", archetype: "execution",
      policy: { "model" => "claude-sonnet-4-6", "effort" => "high", "concurrency_limit" => 3,
                "plan_approval" => true, "max_turns" => 25, "timeout_minutes" => 30,
                "on_entry" => [{ "action" => "start_agent_run" }] } },
    { name: "Review",      archetype: "review",    policy: {} },
    { name: "QA",          archetype: "review",
      policy: { "on_entry" => [{ "action" => "mark_pr_ready" }],
                "on_entry_text" => "Take the PR out of draft — mark it ready for review on GitHub." } },
    { name: "Done",        archetype: "terminal",  policy: { "on_entry" => [{ "action" => "merge_pr" }] } }
  ].freeze

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
    DEFAULT_COLUMNS.each_with_index do |attrs, index|
      board.columns.create!(position: index, **attrs)
    end
    board
  end

  def self.sanitize_remote_url(url)
    # Drop any userinfo (tokens from credential-helper rewrites). Regex, not
    # URI#userinfo= — Ruby 3.4's RFC3986 parser silently ignores that setter.
    url.sub(%r{\A(\w+://)[^@/]+@}, '\1')
  end

  # Cards currently waiting on the human, ordered by urgency — feeds the
  # attention inbox in the board header.
  def attention_cards
    cards.where(status: %w[needs_input failed work_complete])
         .order(Arel.sql("CASE status WHEN 'needs_input' THEN 0 WHEN 'failed' THEN 1 ELSE 2 END"), updated_at: :asc)
  end
end
