module Agent
  # The worker agent's isolated checkout, behind a strategy factory
  # (cardinal.md §13, §17):
  #
  #   Local     — clone under .cardinal/workspaces/; the agent process runs on
  #               the host with chdir into the checkout. Process-level
  #               isolation only. The default.
  #   Container — same host-side checkout, but the agent runs inside a
  #               cage-style Docker container that mounts ONLY the checkout.
  #               Opt in with CARDINAL_WORKSPACE=container (experimental —
  #               requires a Docker daemon and CARDINAL_AGENT_IMAGE with the
  #               claude CLI installed; ANTHROPIC_API_KEY is passed through).
  #
  # Both strategies share git provisioning: the runner owns clone, branch,
  # and push — the agent only ever commits.
  module Workspace
    def self.provision(card) = strategy.provision(card)
    def self.attach(card) = strategy.attach(card)

    def self.strategy
      ENV["CARDINAL_WORKSPACE"] == "container" ? Container : Local
    end

    class Local
      ROOT = Rails.root.join(".cardinal", "workspaces")

      attr_reader :card, :path

      def self.provision(card) = new(card).tap(&:provision)

      # Reattach without resetting — used when resuming a parked run whose
      # local commits aren't pushed yet.
      def self.attach(card)
        ws = new(card)
        File.directory?(ws.path.join(".git")) ? ws : ws.tap(&:provision)
      end

      def initialize(card)
        @card = card
        @path = ROOT.join("card-#{card.number}")
      end

      def provision
        FileUtils.mkdir_p(ROOT)
        unless File.directory?(path.join(".git"))
          git!(ROOT, "clone", "--quiet", (card.board.local_path.presence || Rails.root).to_s, path.to_s)
          git!(path, "remote", "set-url", "origin", card.board.repo_url) if card.board.repo_url.present?
        end
        salvage_dirty_tree!
        git!(path, "fetch", "--quiet", "origin")
        if git?(path, "rev-parse", "--verify", "origin/#{card.branch_name}")
          git!(path, "checkout", "--quiet", card.branch_name)
          git!(path, "reset", "--quiet", "--hard", "origin/#{card.branch_name}")
        elsif git?(path, "rev-parse", "--verify", card.branch_name)
          # Local-only branch (e.g. WIP salvaged but never pushed): keep it.
          git!(path, "checkout", "--quiet", card.branch_name)
        else
          git!(path, "checkout", "--quiet", "-B", card.branch_name, "origin/#{card.board.default_branch}")
        end
        self
      end

      # A killed run can leave uncommitted edits that block checkout and would
      # otherwise be silently destroyed. Commit them as WIP on the branch and
      # push (best effort) so the interrupted work survives onto the PR.
      def salvage_dirty_tree!
        return if git_out(path, "status", "--porcelain").strip.empty?
        git!(path, "add", "-A")
        git!(path, "commit", "--quiet", "-m", "WIP: salvage uncommitted work from an interrupted run")
        begin
          push!
        rescue RuntimeError
          nil # offline is fine — the local-branch checkout path keeps the WIP
        end
      end

      # How the runner should spawn the agent process for this workspace.
      def agent_spawn(cmd) = [cmd, { chdir: path.to_s }]

      def head = git_out(path, "rev-parse", "HEAD").strip

      def commits_since(sha)
        git_out(path, "log", "--oneline", "#{sha}..HEAD").lines.map(&:strip)
      end

      def ahead_of_default?
        git_out(path, "rev-list", "--count", "origin/#{card.board.default_branch}..HEAD").strip.to_i.positive?
      end

      def push!
        git!(path, "push", "--quiet", "-u", "origin", card.branch_name)
      end

      private

      def git!(dir, *args)
        out, status = Open3.capture2e("git", "-C", dir.to_s, *args)
        raise "git #{args.first} failed: #{out.truncate(300)}" unless status.success?
        out
      end

      def git?(dir, *args)
        _, status = Open3.capture2e("git", "-C", dir.to_s, *args)
        status.success?
      end

      def git_out(dir, *args) = git!(dir, *args)
    end

    # EXPERIMENTAL — written against the cage model; needs a host with Docker
    # to exercise. Git stays host-side; only the agent process is jailed.
    class Container < Local
      WORKDIR = "/workspace/repo"

      def image = ENV.fetch("CARDINAL_AGENT_IMAGE", "cardinal-agent:latest")
      def container_name = "cardinal-card-#{card.number}"

      def agent_spawn(cmd)
        docker = ["docker", "run", "--rm", "-i",
                  "--name", container_name,
                  "--label", "cardinal=agent",
                  "-v", "#{path}:#{WORKDIR}",
                  "-w", WORKDIR]
        # Value-embedded because the runner nils the key in the client env
        # (visible in ps on the host — acceptable for the experimental tier).
        # Instance OAuth token (cardinal up account link) or raw API key —
        # whichever this instance runs on.
        docker += ["-e", "ANTHROPIC_API_KEY=#{ENV["ANTHROPIC_API_KEY"]}"] if ENV["ANTHROPIC_API_KEY"].present?
        docker += ["-e", "CLAUDE_CODE_OAUTH_TOKEN=#{ENV["CLAUDE_CODE_OAUTH_TOKEN"]}"] if ENV["CLAUDE_CODE_OAUTH_TOKEN"].present?
        [docker + [image] + cmd, {}]
      end

      def teardown
        Open3.capture2e("docker", "rm", "-f", container_name)
      end
    end
  end
end
