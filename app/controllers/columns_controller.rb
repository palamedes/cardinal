class ColumnsController < ApplicationController
  before_action :set_column, only: [:edit, :update, :destroy]

  def create
    board = Board.first!
    attrs = params.require(:column).permit(:name, :archetype)
    # Inbox is the board's single intake and can't be created a second time
    # (card #17) — refuse it even from a crafted request, and default any
    # blank/invalid archetype to a non-special stage rather than inbox.
    archetype = (attrs[:archetype].presence_in(Column::ARCHETYPES - %w[inbox])) || "planning"
    board.columns.create!(
      name: attrs[:name],
      archetype: archetype,
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
      :on_entry_text, :on_entry_json, :color, :custom_color, :arrivals, :ai,
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
    policy["ai"] = (attrs[:ai] == "1") if attrs.key?(:ai) # inbox forms omit it — never AI anyway
    # Accept policy (card #15): store allowed source column ids as strings.
    # EXPLICIT ONLY — an empty list means the column accepts from nowhere.
    policy["accepts_from"] = attrs[:accepts_from].to_a.map(&:to_s).reject(&:blank?).presence

    # Archetype is a TEMPLATE: switching it re-stamps rules + instructions
    # from the new archetype (the submitted fields belong to the old one).
    new_archetype = @column.inbox? ? "inbox" : (attrs[:archetype].presence_in(Column::ARCHETYPES - %w[inbox]) || @column.archetype)
    @archetype_changed = new_archetype != @column.archetype
    if @archetype_changed
      template = Column::ARCHETYPE_TEMPLATES.fetch(new_archetype, {})
      %w[on_entry on_entry_text instructions].each { |k| policy[k] = template[k] }
    end

    # Rules: plain English is the source of truth (compiled on change); the
    # advanced JSON editor applies only when the English box is empty.
    if !@archetype_changed && attrs[:on_entry_text].present?
      if attrs[:on_entry_text].strip != policy["on_entry_text"].to_s.strip
          begin
          policy["on_entry"] = Rules::Compiler.compile(attrs[:on_entry_text])
        rescue Rules::Compiler::Error => e
          return column_error(e.message)
        end
      end
      policy["on_entry_text"] = attrs[:on_entry_text].strip
    elsif !@archetype_changed && attrs[:on_entry_json].present?
      begin
        policy["on_entry"] = JSON.parse(attrs[:on_entry_json])
        policy.delete("on_entry_text")
      rescue JSON::ParserError => e
        return column_error("on_entry is not valid JSON: #{e.message.truncate(120)}")
      end
    elsif !@archetype_changed
      policy.delete("on_entry")
      policy.delete("on_entry_text")
    end

    @column.update!(
      name: attrs[:name].presence || @column.name,
      archetype: new_archetype,
      policy: policy.compact
    )

    if params[:autosave]
      # Silent save: patch the board's column section + clear any prior error.
      # No modal replace — it would steal focus mid-edit.
      streams = [
        turbo_stream.replace(helpers.dom_id(@column), partial: "columns/column", locals: { column: @column.reload }),
        turbo_stream.update("column-form-errors", "")
      ]
      # A re-stamped archetype must re-render the modal (its fields changed
      # server-side); focus loss is fine — the user just picked from a select.
      streams << turbo_stream.replace("modal", template: "columns/edit", formats: [:html]) if @archetype_changed
      render turbo_stream: streams
    else
      redirect_to root_path
    end
  end

  # Autosave-friendly error: surface in the modal without re-rendering the form.
  def column_error(message)
    if params[:autosave]
      render turbo_stream: turbo_stream.update(
        "column-form-errors",
        helpers.tag.p("#{message} — this field was NOT saved.", class: "form-error")
      ), status: :unprocessable_entity
    else
      @json_error = message
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @column.inbox?
      # The Tasks/inbox column is the board's intake — cards enter the flow here
      # to be triaged. It can never be deleted (card #17).
      @json_error = "The Tasks column is the board's intake and can't be deleted."
      render :edit, status: :unprocessable_entity
    elsif @column.cards.none?
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
