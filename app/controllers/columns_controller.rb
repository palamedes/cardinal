class ColumnsController < ApplicationController
  before_action :set_column, only: [:edit, :update, :destroy]

  def create
    board = Board.first!
    attrs = params.require(:column).permit(:name, :archetype)
    board.columns.create!(
      name: attrs[:name],
      archetype: attrs[:archetype].presence_in(Column::ARCHETYPES) || "inbox",
      position: (board.columns.maximum(:position) || -1) + 1,
      policy: {}
    )
    redirect_to root_path
  end

  def edit
  end

  # The gear modal is the entire policy admin surface (§1, §14.3).
  def update
    attrs = params.require(:column).permit(
      :name, :archetype, :instructions, :model, :effort,
      :concurrency_limit, :max_turns, :timeout_minutes, :plan_approval, :on_entry_json
    )

    policy = @column.policy.dup
    %w[instructions model effort].each { |k| policy[k] = attrs[k].presence }
    %w[concurrency_limit max_turns timeout_minutes].each do |k|
      policy[k] = attrs[k].present? ? attrs[k].to_i : nil
    end
    policy["plan_approval"] = attrs[:plan_approval] == "1"

    if attrs[:on_entry_json].present?
      begin
        policy["on_entry"] = JSON.parse(attrs[:on_entry_json])
      rescue JSON::ParserError => e
        @json_error = "on_entry is not valid JSON: #{e.message.truncate(120)}"
        return render :edit, status: :unprocessable_entity
      end
    else
      policy.delete("on_entry")
    end

    @column.update!(
      name: attrs[:name].presence || @column.name,
      archetype: attrs[:archetype].presence_in(Column::ARCHETYPES) || @column.archetype,
      policy: policy.compact
    )
    redirect_to root_path
  end

  def destroy
    if @column.cards.none?
      @column.destroy!
      redirect_to root_path
    else
      @json_error = "Column still has cards — move them first."
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_column = @column = Column.find(params[:id])
end
