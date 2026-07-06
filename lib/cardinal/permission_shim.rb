#!/usr/bin/env ruby
# frozen_string_literal: true

# Cardinal's permission shim (§ ask-first mode): a minimal MCP stdio server
# the claude CLI calls via --permission-prompt-tool. Each permission request
# becomes a PermissionRequest on the card (POST to the local Cardinal server);
# we then poll for the human's verdict — the poll doubles as the run's
# heartbeat — and hand claude back allow/deny. Pure stdlib; fails CLOSED
# (deny) on any transport error.
require "json"
require "net/http"
require "uri"

class CardinalPermissionShim
  PROTOCOL = "2024-11-05"

  def initialize(input: $stdin, output: $stdout,
                 base_url: ENV["CARDINAL_URL"], run_id: ENV["CARDINAL_RUN_ID"],
                 timeout: ENV.fetch("CARDINAL_PERMISSION_TIMEOUT", "600").to_i)
    @input, @output = input, output
    @base_url, @run_id, @timeout = base_url, run_id, timeout
    @output.sync = true
  end

  def run
    while (line = @input.gets)
      line = line.strip
      next if line.empty?
      handle(JSON.parse(line))
    end
  rescue Interrupt
    nil
  end

  def handle(msg)
    case msg["method"]
    when "initialize"
      reply(msg["id"], protocolVersion: msg.dig("params", "protocolVersion") || PROTOCOL,
                       capabilities: { tools: {} },
                       serverInfo: { name: "cardinal", version: "1.0" })
    when "tools/list"
      reply(msg["id"], tools: [{
        name: "permission",
        description: "Ask the Cardinal board's user to approve or deny a tool use.",
        inputSchema: { type: "object",
                       properties: { tool_name: { type: "string" }, input: { type: "object" } },
                       required: ["tool_name"] }
      }])
    when "tools/call"
      args = msg.dig("params", "arguments") || {}
      decision = decide(args)
      reply(msg["id"], content: [{ type: "text", text: decision.to_json }])
    when "ping"
      reply(msg["id"], {})
    else
      reply(msg["id"], {}) if msg["id"] # politely ack anything else that expects an answer
    end
  end

  # POST the request, poll until answered, translate to the CLI's contract.
  def decide(args)
    created = post("/permission_requests",
                   run_id: @run_id, tool_name: args["tool_name"].to_s, input: args["input"] || {})
    return deny("Cardinal couldn't record the permission request — denied for safety.") unless created

    waited = 0
    status, message = created["status"], created["message"]
    while status == "pending"
      if waited >= @timeout
        post("/permission_requests/#{created["id"]}/answer", verdict: "deny", auto: "1")
        return deny("No answer from the user in time. Work around this without the command, or park with a QUESTION:.")
      end
      sleep 2
      waited += 2
      current = get("/permission_requests/#{created["id"]}")
      status, message = current["status"], current["message"] if current
    end

    if status == "allowed"
      { "behavior" => "allow", "updatedInput" => args["input"] || {} }
    else
      deny(message.to_s.empty? ? "The user denied this action." : "The user denied this: #{message}")
    end
  end

  def deny(message) = { "behavior" => "deny", "message" => message }

  def reply(id, payload)
    @output.puts({ jsonrpc: "2.0", id: id, result: payload }.to_json)
  end

  def post(path, body)
    http_json(Net::HTTP::Post, path, body)
  end

  def get(path)
    http_json(Net::HTTP::Get, path, nil)
  end

  def http_json(klass, path, body)
    uri = URI("#{@base_url}#{path}")
    req = klass.new(uri.request_uri, "Content-Type" => "application/json", "Accept" => "application/json")
    req.body = body.to_json if body
    res = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 10) { |h| h.request(req) }
    res.code.to_i.between?(200, 299) ? JSON.parse(res.body) : nil
  rescue StandardError => e
    warn "cardinal-shim: #{e.class}: #{e.message}"
    nil
  end
end

CardinalPermissionShim.new.run if __FILE__ == $PROGRAM_NAME
