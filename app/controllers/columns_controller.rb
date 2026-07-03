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
      :concurrency_limit, :max_turns, :timeout_minutes, :plan_approval,
      :on_entry_text, :on_entry_json, :color, :custom_color, :arrivals,
      accepts_from: []
    )

    policy = @column.policy.dup
    %w[instructions model effort].each { |k| policy[k] = attrs[k].presence }
    policy["color"] = attrs[:custom_color] == "1" && attrs[:color].to_s.match?(/\A#\h{6}\z/) ? attrs[:color] : nil
    %w[concurrency_limit max_turns timeout_minutes].each do |k|
      policy[k] = attrs[k].present? ? attrs[k].to_i : nil
    end
    policy["plan_approval"] = attrs[:plan_approval] == "1"
    policy["arrivals"] = attrs[:arrivals].presence_in(%w[top bottom])
    # Accept policy (card #15): store allowed source column ids as strings;
    # blank means accept from any column (backward-compatible default).
    policy["accepts_from"] = attrs[:accepts_from].to_a.map(&:to_s).reject(&:blank?).presence

    # Rules: plain English is the source of truth (compiled on change); the
    # advanced JSON editor applies only when the English box is empty.
    if attrs[:on_entry_text].present?
      if attrs[:on_entry_text].strip != policy["on_entry_text"].to_s.strip
        begin
          policy["on_entry"] = Rules::Compiler.compile(attrs[:on_entry_text])
        rescue Rules::Compiler::Error => e
          @json_error = e.message
          return render :edit, status: :unprocessable_entity
        end
      end
      policy["on_entry_text"] = attrs[:on_entry_text].strip
    elsif attrs[:on_entry_json].present?
      begin
        policy["on_entry"] = JSON.parse(attrs[:on_entry_json])
        policy.delete("on_entry_text")
      rescue JSON::ParserError => e
        @json_error = "on_entry is not valid JSON: #{e.message.truncate(120)}"
        return render :edit, status: :unprocessable_entity
      end
    else
      policy.delete("on_entry")
      policy.delete("on_entry_text")
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
