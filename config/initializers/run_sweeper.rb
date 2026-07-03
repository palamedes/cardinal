# Run the sweeper inside the web server process (dev-grade scheduling; a
# SolidQueue recurring task replaces this in a production deployment).
if defined?(Rails::Server) || ENV["CARDINAL_SWEEPER"] == "1"
  Rails.application.config.after_initialize do
    Thread.new do
      sleep 15 # let boot settle, then repair anything left over from a crash
      loop do
        begin
          RunSweeper.sweep
        rescue => e
          Rails.logger.error("RunSweeper: #{e.class}: #{e.message}")
        end
        sleep 60
      end
    end
  end
end
