# Opt-in repo deep dive (card #12): a one-shot, read-only agent (the same
# cheap ClaudeCli tier the planning assistant uses — Read/Glob/Grep, no
# workspace) that maps the board's repo into a compact "repo brief". The brief
# is written to .cardinal/repo-brief.md and injected into every worker prompt,
# converting the per-run exploration tax into a one-time cost.
class DeepDiveJob < ApplicationJob
  queue_as :default

  # Enough turns to walk the tree and read a handful of key files, not enough
  # to wander. ClaudeCli wraps up from context if it hits the cap.
  MAX_TURNS = 30
  FALLBACK_MODEL = "claude-haiku-4-5-20251001".freeze

  PROMPT = <<~PROMPT.freeze
    Map this repository as a concise "repo brief" for other AI agents who will
    work in it. The whole point is to save tokens later, so be dense and skip
    the obvious — every line must earn its place.

    Explore with your read-only tools, then output ONLY flat markdown with these
    sections (drop any that genuinely don't apply):

    ## Overview
    One short paragraph: what this project is and its shape.
    ## Directory Structure
    The top-level directories and what each is for (one line each).
    ## Key Directories
    The few places most work actually happens, and what lives there.
    ## Build & Test
    The exact commands to install, build, run, and test.
    ## Key Conventions
    Naming, patterns, and idioms an agent must follow to match the codebase.
    ## Tech Stack
    Languages, frameworks, and notable libraries with their role.
    ## Gotchas
    Non-obvious traps, footguns, and constraints worth knowing before editing.

    Do not include a preamble, closing remarks, or anything outside these sections.
  PROMPT

  def perform(board)
    repo = board.local_path.presence
    return clear_working(board) unless ClaudeCli.available? && repo

    sha = board.head_sha
    model = board.columns.find_by(archetype: "planning")&.model.presence || FALLBACK_MODEL

    brief = ClaudeCli.prompt(PROMPT, model:, tools: "Read,Glob,Grep", cwd: repo, max_turns: MAX_TURNS,
                             ledger: { kind: "deep_dive" })

    File.write(board.brief_path, brief.to_s)
    board.update!(brief_sha: sha, brief_generated_at: Time.current,
                  brief_model: model, brief_status: nil)
    board.broadcast_refresh_to board
  rescue StandardError
    # A failed dive must not leave the button stuck on "Working" forever.
    clear_working(board)
  end

  private

  def clear_working(board)
    board.update!(brief_status: nil)
    board.broadcast_refresh_to board
  end
end
