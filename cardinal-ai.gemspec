require_relative "lib/cardinal/version"

Gem::Specification.new do |spec|
  spec.name        = "cardinal-ai"
  spec.version     = Cardinal::VERSION
  spec.authors     = ["Jason Ellis"]
  spec.summary     = "A Kanban board where dragging a card to In Progress hires an AI agent to do the task."
  spec.description = "Cardinal is a local, per-repo AI Kanban tool: columns are policies, cards become " \
                     "Claude-powered worker agents, and work ships as pull requests. This release is a " \
                     "placeholder reserving the gem name while the packaged app is prepared — watch the repo."
  spec.homepage    = "https://github.com/palamedes/cardinal"
  spec.required_ruby_version = ">= 3.2"
  spec.metadata = {
    "homepage_uri"    => spec.homepage,
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues"
  }
  spec.files = ["README.md", "lib/cardinal.rb", "lib/cardinal/version.rb"]
  spec.require_paths = ["lib"]
end
