# Two boot modes:
#   - Development of the engine itself: normal Bundler + Bootsnap boot.
#   - Installed-gem instance (`cardinal` executable sets CARDINAL_GEM=1):
#     no Gemfile, no Bundler — dependencies come from the gemspec and are
#     activated by RubyGems; Bootsnap is skipped (its cache writes don't
#     belong in an installed gem directory).
if ENV["CARDINAL_GEM"] == "1"
  require "rubygems"
  # Activate our own gem up front: bare `require`s pick the newest installed
  # version of each dependency, ignoring the gemspec's constraints — in a
  # shared gemset (host app + cardinal) that can activate a version we don't
  # support. Activating cardinal-ai pins the whole tree to the gemspec.
  begin
    require_relative "../lib/cardinal/version"
    gem "cardinal-ai", Cardinal::VERSION
  rescue Gem::LoadError
    # Checkout run with CARDINAL_GEM=1 but no installed gem — requires below
    # fall back to newest-installed. A missing/conflicting DEPENDENCY of an
    # installed gem must surface here, not as a NameError deep in the app.
    raise unless Gem::Specification.find_all_by_name("cardinal-ai").empty?
  end
else
  ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
  require "bundler/setup" # Set up gems listed in the Gemfile.
  require "bootsnap/setup" # Speed up boot time by caching expensive operations.
end
