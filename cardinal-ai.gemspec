require_relative "lib/cardinal/version"

Gem::Specification.new do |spec|
  spec.name        = "cardinal-ai"
  spec.version     = Cardinal::VERSION
  spec.authors     = ["Jason Ellis"]
  spec.summary     = "A Kanban board where dragging a card to In Progress hires an AI agent to do the task."
  spec.description = "Cardinal AI is a local, per-repo AI Kanban tool: columns are policies, cards become " \
                     "Claude-powered worker agents, and work ships as pull requests. Run `cardinal` inside " \
                     "any git repository to get a board for it at http://localhost:4000."
  spec.homepage    = "https://github.com/palamedes/cardinal"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri"    => spec.homepage,
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues"
  }

  spec.files = Dir[
    "app/**/*",
    "config/**/*",
    "db/migrate/**/*", "db/seeds.rb", "db/queue_schema.rb", "db/cable_schema.rb",
    "lib/**/*",
    "public/**/*",
    "vendor/javascript/**/*",
    "bin/rails", "bin/rake",
    "docker/**/*",
    "config.ru", "Rakefile",
    "README.md", "LICENSE", "cardinal.md"
  ].select { |f| File.file?(f) }
   # Dir[] ignores .gitignore — never let key material on the build machine
   # into the public package, whatever else the globs match.
   .reject { |f| f.end_with?(".key", ".enc", ".pem") || f.include?("credentials") }

  spec.bindir      = "exe"
  spec.executables = ["cardinal"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", "~> 8.1"
  spec.add_dependency "propshaft"
  spec.add_dependency "sqlite3", ">= 2.1"
  spec.add_dependency "puma", ">= 6.0"
  spec.add_dependency "importmap-rails"
  spec.add_dependency "turbo-rails"
  spec.add_dependency "stimulus-rails"
  spec.add_dependency "redcarpet", "~> 3.6"
  spec.add_dependency "solid_queue", "~> 1.0"
  spec.add_dependency "solid_cable", "~> 3.0"

  spec.post_install_message = <<~MSG

    Cardinal AI installed. To put a board on a repo:

        cd your-project && cardinal

    Requires the claude CLI (npm install -g @anthropic-ai/claude-code),
    git, and - for pull requests - an authenticated gh CLI.

  MSG
end
