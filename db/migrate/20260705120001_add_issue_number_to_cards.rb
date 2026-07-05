class AddIssueNumberToCards < ActiveRecord::Migration[8.1]
  def change
    add_column :cards, :issue_number, :integer
  end
end
