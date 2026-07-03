# Engine-development seeds only. Portable instances (`cardinal up` in another
# repo) are bootstrapped by config/initializers/cardinal_bootstrap.rb instead.
return if ENV["CARDINAL_TARGET_REPO"].present?

board = Board.find_or_create_by!(name: "Cardinal") do |b|
  b.repo_url = "git@github.com:palamedes/cardinal.git"
  b.default_branch = "main"
  b.local_path = Rails.root.to_s
end

board.install_default_columns! if board.columns.none?

puts "Seeded board '#{board.name}' with #{board.columns.count} columns."
