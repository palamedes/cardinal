class BoardsController < ApplicationController
  def show
    @board = Board.includes(columns: :cards).first!
  end

  # Kick off the repo deep dive (card #12). Non-blocking: flip the board into
  # its "Working" state, morph the topbar so the button reflects it, and let
  # DeepDiveJob do the read-only exploration in the background. Ignored if a
  # dive is already running.
  def deep_dive
    board = Board.first!
    unless board.brief_working?
      board.update!(brief_status: "working")
      board.broadcast_refresh_to board
      DeepDiveJob.perform_later(board)
    end
    redirect_to root_path
  end

  # Cards reaching Done merge PRs on GitHub, so the checkout Cardinal runs
  # against falls behind. The topbar Pull button fast-forwards it. --ff-only
  # on purpose: never invent merge commits or rebase local work — if the tree
  # has diverged, say so and let the human sort it out in a real terminal.
  def pull
    board = Board.first!
    message, ok = pull_repo(board)
    render turbo_stream: turbo_stream.update(
      "repo-pull-status",
      helpers.tag.span(message, class: ok ? "pull-ok" : "pull-err")
    )
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
      ["Pulled #{helpers.pluralize(count.strip.to_i, "new commit")}", true]
    end
  end
end
