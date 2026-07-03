# The only code path that moves a card between columns. Validates legality,
# runs the old column's leave policy and the new column's enter policy, and
# emits the transition events (§3, §11). Controllers and future automations
# all call this — never Card#update(column:) directly.
class CardTransition
  Result = Data.define(:success?, :card, :error)

  def initialize(card, to_column:, position: nil, actor: "user")
    @card = card
    @from = card.column
    @to = to_column
    @position = position
    @actor = actor
  end

  def call
    return failure("Card is already in #{@to.name}") if @from == @to
    return failure("Column belongs to a different board") if @to.board_id != @card.board_id
    if @card.working? && @from.execution?
      # An agent process is live — no silent kills (§3). Cancel it first.
      return failure("##{@card.number} has an active run — cancel it before moving the card")
    end

    Card.transaction do
      leave_policy!
      place_in_column!
      enter_policy!
    end
    Result.new(success?: true, card: @card, error: nil)
  rescue ActiveRecord::RecordInvalid => e
    failure(e.message)
  end

  private

  def leave_policy!
    return unless @from.execution?
    # Dequeue / abandon parked runs — nothing live is killed (working cards
    # were already blocked above).
    @card.runs.where(status: %w[queued needs_input]).each do |run|
      run.update!(status: "cancelled", finished_at: Time.current)
    end
  end

  def place_in_column!
    @position ||= (@to.cards.maximum(:position) || -1) + 1
    @to.cards.where("position >= ?", @position).update_all("position = position + 1")
    @card.update!(column: @to, position: @position, status: entry_status)
    @card.log!("column_move", actor: @actor,
               from: @from.name, to: @to.name, text: "Moved from #{@from.name} to #{@to.name}")
  end

  def enter_policy!
    Rules.fire_entry(@card, @to)
  end

  def entry_status
    case @to.archetype
    when "inbox"     then "draft"
    when "planning"  then "discussing"
    when "execution" then "queued"
    when "review"    then "in_review"
    when "terminal"  then "done"
    end
  end

  def failure(message) = Result.new(success?: false, card: @card, error: message)
end
