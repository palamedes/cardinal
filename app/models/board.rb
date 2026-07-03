class Board < ApplicationRecord
  has_many :columns, -> { order(:position) }, dependent: :destroy
  has_many :cards, dependent: :destroy

  validates :name, presence: true

  # Cards currently waiting on the human, ordered by urgency — feeds the
  # attention inbox in the board header.
  def attention_cards
    cards.where(status: %w[needs_input failed work_complete])
         .order(Arel.sql("array_position(ARRAY['needs_input','failed','work_complete'], status)"), updated_at: :asc)
  end
end
