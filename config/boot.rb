# Two boot modes:
#   - Development of the engine itself: normal Bundler + Bootsnap boot.
#   - Installed-gem instance (`cardinal` executable sets CARDINAL_GEM=1):
#     no Gemfile, no Bundler — dependencies come from the gemspec and are
#     activated by RubyGems; Bootsnap is skipped (its cache writes don't
#     belong in an installed gem directory).
if ENV["CARDINAL_GEM"] == "1"
  require "rubygems"
else
  ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
  require "bundler/setup" # Set up gems listed in the Gemfile.
  require "bootsnap/setup" # Speed up boot time by caching expensive operations.
end
