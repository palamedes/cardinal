module Agent
  # The worker agent's isolated checkout. Strategy today: a local clone under
  # .cardinal/workspaces/ (dev — process-level isolation only). Production
  # strategy per cardinal.md §13 is a cage-style Docker container per card;
  # that lands when Cardinal runs on a host with a Docker daemon, behind this
  # same interface (provision → path, push!, teardown).
  class Workspace
    ROOT = Rails.root.join(".cardinal", "workspaces")

    attr_reader :card, :path

    def self.provision(card)
      new(card).tap(&:provision)
    end

    def initialize(card)
      @card = card
      @path = ROOT.join("card-#{card.number}")
    end

    def provision
      FileUtils.mkdir_p(ROOT)
      unless File.directory?(path.join(".git"))
        git!(ROOT, "clone", "--quiet", Rails.root.to_s, path.to_s)
        git!(path, "remote", "set-url", "origin", card.board.repo_url) if card.board.repo_url.present?
      end
      git!(path, "fetch", "--quiet", "origin")
      if git?(path, "rev-parse", "--verify", "origin/#{card.branch_name}")
        git!(path, "checkout", "--quiet", card.branch_name)
        git!(path, "reset", "--quiet", "--hard", "origin/#{card.branch_name}")
      else
        git!(path, "checkout", "--quiet", "-B", card.branch_name, "origin/#{card.board.default_branch}")
      end
      self
    end

    def head = git_out(path, "rev-parse", "HEAD").strip

    def commits_since(sha)
      git_out(path, "log", "--oneline", "#{sha}..HEAD").lines.map(&:strip)
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
end
