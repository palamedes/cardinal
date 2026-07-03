# Portable-instance first run (cardinal.md §16): when launched via
# `cardinal up` inside a target repo, create that repo's board on first boot.
if ENV["CARDINAL_TARGET_REPO"].present?
  Rails.application.config.after_initialize do
    begin
      Board.bootstrap!(ENV["CARDINAL_TARGET_REPO"]) if Board.none?
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      # DB not created yet (e.g. during db:prepare's own boot) — the next boot
      # after prepare will bootstrap.
    end
  end
end
