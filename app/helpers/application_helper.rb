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

  # Timeline text is Markdown (agents write it constantly). escape_html turns
  # any raw HTML in the text into visible text instead of live DOM — an agent
  # pasting `<div class=...>` inside a code fence must never restyle the page.
  MARKDOWN = Redcarpet::Markdown.new(
    Redcarpet::Render::HTML.new(escape_html: true, hard_wrap: true, safe_links_only: true),
    fenced_code_blocks: true, tables: true, autolink: true,
    strikethrough: true, no_intra_emphasis: true, lax_spacing: true
  )

  def render_markdown(text)
    MARKDOWN.render(text.to_s).html_safe
  end

  # Render a column's stored footer config (array of {label, compute} hashes)
  # back into the "Label | compute" line format the gear textarea edits.
  def footer_config_text(column)
    Array(column.footer).map do |row|
      [row["label"], row["compute"].presence].compact.join(" | ")
    end.join("\n")
  end

  def info_tip(text)
    tag.span("i", class: "info",
             data: { controller: "tooltip", tooltip_text_value: text,
                     action: "mouseenter->tooltip#show mouseleave->tooltip#hide focus->tooltip#show blur->tooltip#hide" },
             tabindex: 0)
  end
end
