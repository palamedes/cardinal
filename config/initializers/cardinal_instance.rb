# Portable-instance hardening (§16): when running from an installed gem, the
# app directory must be treated as read-only — every write goes to the
# instance's data dir (CARDINAL_DATA_DIR, i.e. <target repo>/.cardinal).
if ENV["CARDINAL_DATA_DIR"].present?
  data_dir = File.expand_path(ENV["CARDINAL_DATA_DIR"])

  Rails.application.configure do
    # (Log path is set in application.rb — the logger exists before initializers.)

    # Stable per-instance secret, generated once — avoids Rails writing
    # tmp/local_secret.txt into the gem directory.
    secret_file = File.join(data_dir, "secret.key")
    unless File.exist?(secret_file)
      require "securerandom"
      File.write(secret_file, SecureRandom.hex(64))
      File.chmod(0o600, secret_file)
    end
    config.secret_key_base = File.read(secret_file).strip

    # Browser cookies ignore ports, so two boards on localhost share a cookie
    # jar. With one shared cookie name, each instance keeps overwriting the
    # other's session (each signs with its own secret) — every POST on the
    # other board then fails CSRF. Scope the session cookie per instance.
    require "digest"
    config.session_store :cookie_store,
                         key: "_cardinal_#{Digest::SHA256.hexdigest(data_dir).first(12)}_session"
  end
end
