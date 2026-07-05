require "net/http"

# Asana import (card #7): paste a task URL, get a card. First use walks
# through connecting a Personal Access Token, which lives as a 0600 file in
# .cardinal/ (like the Claude token) — never in the database, never in git.
module Asana
  API = "https://app.asana.com/api/1.0".freeze

  class Error < StandardError; end

  def self.token_path
    Pathname(File.expand_path(ENV["CARDINAL_DATA_DIR"].presence || Rails.root.join(".cardinal"))).join("asana-token")
  end

  def self.connected? = !!File.size?(token_path)
  def self.token = File.read(token_path).strip

  def self.save_token!(value)
    FileUtils.mkdir_p(File.dirname(token_path))
    File.write(token_path, value.strip)
    File.chmod(0o600, token_path)
  end

  def self.disconnect! = FileUtils.rm_f(token_path)

  # Cheapest possible "does this token work" — also gives us a name to show.
  def self.verify!(candidate)
    data = request("/users/me", candidate)
    data["name"].presence || data["email"].presence || "connected"
  end

  # Task URLs come in several vintages (/0/<project>/<task>, /0/.../f,
  # /1/<ws>/project/<p>/task/<t>) — the task gid is the last long digit run.
  def self.task_gid(url)
    url.to_s.scan(/\d{6,}/).last or raise Error, "That doesn't look like an Asana task URL"
  end

  def self.import!(board, url)
    data = request("/tasks/#{task_gid(url)}?opt_fields=name,notes,permalink_url,tags.name", token)
    permalink = data["permalink_url"].presence || url
    if (existing = board.cards.find_by(asana_url: permalink))
      return existing
    end

    inbox = board.columns.inbox.order(:position).first
    card = board.cards.create!(
      column: inbox,
      title: data["name"].presence || "Asana task",
      asana_url: permalink,
      tags: Array(data["tags"]).filter_map { |t| t["name"] }.first(5),
      description: "#{data["notes"].presence || "(no description on the Asana task)"}\n\n---\n_Imported from Asana: #{permalink}_"
    )
    card.log!("status_change", actor: "user", text: "Imported from Asana: #{permalink}")
    card
  end

  # Post text to the task as a comment (an Asana "story").
  def self.comment!(task_url, text)
    request("/tasks/#{task_gid(task_url)}/stories", token,
            method: :post, body: { data: { text: text } })
  end

  def self.request(path, auth, method: :get, body: nil)
    uri = URI("#{API}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15
    headers = { "Authorization" => "Bearer #{auth}" }
    response =
      if method == :post
        http.post(uri.request_uri, body.to_json, headers.merge("Content-Type" => "application/json"))
      else
        http.get(uri.request_uri, headers)
      end
    unless [200, 201].include?(response.code.to_i)
      raise Error, "Asana said no (HTTP #{response.code}) — check the token, and that it can see this task"
    end
    JSON.parse(response.body)["data"]
  rescue JSON::ParserError
    raise Error, "Asana returned something unreadable"
  rescue SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "Couldn't reach Asana (#{e.class.name.demodulize}) — check your connection"
  end
end
