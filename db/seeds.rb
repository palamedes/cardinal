# Engine-development seeds only. Portable instances (`cardinal up` in another
# repo) are bootstrapped by config/initializers/cardinal_bootstrap.rb instead.
return if ENV["CARDINAL_TARGET_REPO"].present?

board = Board.find_or_create_by!(name: "Cardinal") do |b|
  b.repo_url = "git@github.com:palamedes/cardinal.git"
  b.default_branch = "main"
  b.local_path = Rails.root.to_s
end

Board::DEFAULT_COLUMNS.each_with_index do |attrs, index|
  board.columns.find_or_create_by!(name: attrs[:name]) do |c|
    c.position = index
    c.archetype = attrs[:archetype]
    c.policy = attrs[:policy]
  end
end

puts "Seeded board '#{board.name}' with #{board.columns.count} columns."
