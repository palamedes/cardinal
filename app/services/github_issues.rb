# GitHub Issues sync (card #49): issues are the adjacent primitive to cards —
# gh is already authenticated, so import is a listing + a click, and closing
# happens naturally via "Closes #N" in the card's PR body.
module GithubIssues
  Issue = Struct.new(:number, :title, :body, :labels, keyword_init: true)

  def self.available?(board)
    board.repo_url.present? && board.local_path.present?
  end

  # Open issues, newest first. Empty array on any failure (no remote, gh not
  # authed, offline) — the modal explains instead of erroring.
  def self.list(board)
    out, status = Open3.capture2e(
      "gh", "issue", "list", "--state", "open", "--limit", "50",
      "--json", "number,title,body,labels", chdir: board.local_path
    )
    return [] unless status.success?
    JSON.parse(out).map do |i|
      Issue.new(number: i["number"], title: i["title"], body: i["body"].to_s,
                labels: Array(i["labels"]).map { |l| l["name"] })
    end
  rescue JSON::ParserError
    []
  end

  # One click → one card in the inbox, tagged with the issue's labels, body
  # carried as the description with provenance. Best-effort backlink comment
  # on the issue so the GitHub side knows where the work went.
  def self.import!(board, number)
    issue = list(board).find { |i| i.number == number.to_i }
    raise ArgumentError, "issue ##{number} not found among open issues" unless issue

    existing = board.cards.find_by(issue_number: issue.number)
    return existing if existing

    inbox = board.columns.inbox.order(:position).first
    card = board.cards.create!(
      column: inbox, title: issue.title, issue_number: issue.number,
      tags: issue.labels.first(5),
      description: "#{issue.body.presence || "(no issue body)"}\n\n---\n_Imported from GitHub issue ##{issue.number}._"
    )
    card.log!("status_change", actor: "user", text: "Imported from GitHub issue ##{issue.number}")
    Open3.capture2e("gh", "issue", "comment", issue.number.to_s,
                    "--body", "Tracking in Cardinal as card ##{card.number}. The pull request, when opened, will link back and close this issue on merge.",
                    chdir: board.local_path)
    card
  end
end
