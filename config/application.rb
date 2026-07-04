require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Stdlib the app leans on — explicit because installed-gem mode has no
# Bundler incidentally loading these.
require "open3"
require "fileutils"
require "securerandom"

if ENV["CARDINAL_GEM"] == "1"
  # Installed-gem mode: no Bundler — load what Bundler.require would have.
  %w[propshaft importmap-rails turbo-rails stimulus-rails redcarpet sqlite3 solid_queue solid_cable].each { |g| require g }
else
  # Require the gems listed in Gemfile, including any gems
  # you've limited to :test, :development, or :production.
  Bundler.require(*Rails.groups)
end

module Cardinal
  class Application < Rails::Application
    # Portable instances (§16): the engine/gem directory is read-only — the
    # log joins the rest of the instance state in the target's .cardinal/.
    # (Set here, not in an initializer: the logger is built before those run.)
    if ENV["CARDINAL_DATA_DIR"].present?
      config.paths["log"] = File.join(File.expand_path(ENV["CARDINAL_DATA_DIR"]), "cardinal.log")
    end

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
