class BoardsController < ApplicationController
  def show
    @board = Board.includes(columns: :cards).first!
  end

  # Kick off the repo deep dive (card #12). Non-blocking: flip the board into
  # its "Working" state, morph the topbar so the button reflects it, and let
  # DeepDiveJob do the read-only exploration in the background. Skipped when a
  # dive is already running, or when the brief already matches HEAD — nothing
  # changed, so a re-dive would just burn a run (the brief modal's Regenerate
  # button passes force=1 to override).
  def deep_dive
    board = Board.first!
    fresh = board.brief? && board.commits_behind_brief == 0
    unless board.brief_working? || (fresh && params[:force].blank?)
      board.update!(brief_status: "working")
      board.broadcast_refresh_to board
      DeepDiveJob.perform_later(board)
    end
    redirect_to root_path
  end

  # Board settings gear (the board-level analog of the column gear): name and
  # default branch — the branch agents fork from and Done merges toward.
  def edit
    @board = Board.first!
    redirect_to root_path and return unless turbo_frame_request?
  end

  def update
    board = Board.first!
    attrs = params.require(:board).permit(:name, :default_branch, :permission_bypass, :permission_mode, archive_accepts_from: [])
    board.archive_accepts_from = attrs[:archive_accepts_from].to_a.map(&:to_s).reject(&:blank?) if attrs.key?(:archive_accepts_from)
    board.permission_bypass = (attrs[:permission_bypass] == "1") if attrs.key?(:permission_bypass)
    board.settings["permission_mode"] = attrs[:permission_mode].presence_in(Board::PERMISSION_MODES) if attrs.key?(:permission_mode)
    board.update!(
      name: attrs[:name].presence || board.name,
      default_branch: attrs[:default_branch].presence || board.default_branch
    )
    board.broadcast_refresh_to board
    if params[:autosave]
      render turbo_stream: [
        turbo_stream.update("board-name", board.name),
        turbo_stream.update("board-form-errors", "")
      ]
    else
      redirect_to root_path
    end
  end

  # GitHub Issues sync (card #49): list open issues, one click imports one as
  # an inbox card; the card's eventual PR carries "Closes #N".
  def issues
    @board = Board.first!
    redirect_to root_path and return unless turbo_frame_request?
    @issues = GithubIssues.available?(@board) ? GithubIssues.list(@board) : []
    @imported = @board.cards.where.not(issue_number: nil).pluck(:issue_number, :number).to_h
  end

  def import_issue
    board = Board.first!
    card = GithubIssues.import!(board, params.require(:number))
    redirect_to card_path(card)
  rescue ArgumentError => e
    redirect_to root_path, alert: e.message
  end

  # The archive browser (card #42): everything archived, searchable, restorable.
  def archive
    @board = Board.first!
    @cards = @board.cards.archived.includes(:column).order(updated_at: :desc)
  end

  # Inspect the repo brief: what the deep dive wrote, when, from which SHA.
  def brief
    @board = Board.first!
    redirect_to root_path and return unless turbo_frame_request?

    render :brief
  end

  # Cards reaching Done merge PRs on GitHub, so the checkout Cardinal runs
  # against falls behind. The topbar Pull button fast-forwards it. --ff-only
  # on purpose: never invent merge commits or rebase local work — if the tree
  # has diverged, say so and let the human sort it out in a real terminal.
  def pull
    board = Board.first!
    message, ok = pull_repo(board)
    streams = [turbo_stream.update(
      "repo-pull-status",
      helpers.tag.span(message, class: ok ? "pull-ok" : "pull-err")
    )]
    if @pulled_commits
      # New code often means new JS (Stimulus controllers, importmap entries)
      # that an already-open tab will never fetch — Turbo morphs keep the page
      # alive on stale assets forever. A pull is a deliberate "give me the new
      # version", so finish the job with a full reload.
      streams << turbo_stream.append("repo-pull-status",
        helpers.tag.script("setTimeout(() => window.location.reload(), 1200)".html_safe))
    end
    render turbo_stream: streams
  end

  private

  def pull_repo(board)
    repo = board.local_path.presence
    return ["No local repo path on this board", false] unless repo && Dir.exist?(File.join(repo, ".git"))

    before, = Open3.capture2e("git", "-C", repo, "rev-parse", "HEAD")
    out, status = Open3.capture2e("git", "-C", repo, "pull", "--ff-only")
    unless status.success?
      # Surface git's own reason (diverged, offline, auth) — the last
      # non-blank line is usually the one that matters.
      return [out.lines.map(&:strip).reject(&:blank?).last.to_s.truncate(120), false]
    end

    after, = Open3.capture2e("git", "-C", repo, "rev-parse", "HEAD")
    if before.strip == after.strip
      ["Already up to date", true]
    else
      count, = Open3.capture2e("git", "-C", repo, "rev-list", "--count", "#{before.strip}..#{after.strip}")
      migrated = run_pending_migrations
      note = migrated.positive? ? " · ran #{helpers.pluralize(migrated, "migration")}" : ""
      @pulled_commits = true
      ["Pulled #{helpers.pluralize(count.strip.to_i, "new commit")}#{note} · reloading…", true]
    end
  end

  # When the board's repo IS this Cardinal instance (dogfooding) a pull can
  # bring schema changes; without this the running server 500s until someone
  # runs db:migrate by hand. A no-op everywhere else — `cardinal up` already
  # covers cold boots via db:prepare.
  def run_pending_migrations
    context = ActiveRecord::Base.connection_pool.migration_context
    pending = context.migrations.map(&:version) - context.get_all_versions
    context.migrate if pending.any?
    pending.size
  end
end
