module ApplicationHelper
  # Curated model choices for column policies. A custom value already saved on
  # the column stays selectable.
  def model_options(current)
    options = [
      ["(inherit default)", ""],
      ["Haiku 4.5 — fastest, cheapest", "claude-haiku-4-5-20251001"],
      ["Sonnet 4.6 — balanced, recommended for workers", "claude-sonnet-4-6"],
      ["Opus 4.8 — most capable", "claude-opus-4-8"],
      ["Fable 5 — frontier, expensive", "claude-fable-5"]
    ]
    options << [current, current] if current.present? && options.none? { |_, v| v == current }
    options
  end

  def info_tip(text)
    tag.span("i", class: "info", data: { tip: text })
  end
end
