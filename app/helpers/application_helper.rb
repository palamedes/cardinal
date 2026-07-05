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

  # Model options for a card's per-card override (card #33). Same list as the
  # column gear, but the blank option reads "Use column default (<model>)" so the
  # fallback names the concrete model the card runs on when left unset.
  def card_model_options(card)
    options = model_options(card.model)
    default = card.column.model_short.presence
    options[0] = ["Use column default#{" (#{default})" if default}", ""]
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

  # Pasted files live inline in message/description text as attachment tokens
  # (card #21). Format, kept in sync with attach_controller.js:
  #   [[cardinal:file name="foo.png" mime="image/png" size="12345"]]<base64>[[/cardinal:file]]
  # The regex is anchored on delimiters base64 can never contain ([, ], ").
  ATTACHMENT_TOKEN =
    /\[\[cardinal:file name="([^"]*)" mime="([^"]*)" size="(\d+)"\]\]([A-Za-z0-9+\/=\s]*?)\[\[\/cardinal:file\]\]/

  # Only these render as an inline <img> off a data: URL. Anything else — including
  # a spoofed mime like text/html — falls through to an inert badge, never an image.
  ATTACHMENT_IMAGE_MIMES = %w[image/png image/jpeg image/gif image/webp].freeze

  # Render text that may carry attachment tokens: markdown for the prose, a
  # thumbnail (images) or a badge (everything else) for each attachment. Tokens
  # are pulled out BEFORE markdown so the raw base64 never floods the timeline and
  # a token can never be interpreted as HTML.
  def render_with_attachments(text)
    text = text.to_s
    return render_markdown(text) unless text.match?(ATTACHMENT_TOKEN)

    html = +""
    last = 0
    text.scan(ATTACHMENT_TOKEN) do
      match = Regexp.last_match
      html << render_markdown(text[last...match.begin(0)])
      html << render_attachment(match[1], match[2], match[3].to_i, match[4].gsub(/\s+/, ""))
      last = match.end(0)
    end
    html << render_markdown(text[last..])
    html.html_safe
  end

  # One attachment's HTML. All interpolated values are escaped; the base64 is
  # only ever used as an <img> data: URL for a whitelisted image mime.
  def render_attachment(name, mime, size, base64)
    caption = "#{name} · #{number_to_human_size(size)}"
    if ATTACHMENT_IMAGE_MIMES.include?(mime) && base64.present?
      tag.figure(class: "attachment attachment-image") do
        image_tag("data:#{mime};base64,#{base64}", alt: name, class: "attachment-thumb") +
          tag.figcaption(caption)
      end
    else
      tag.span(class: "attachment attachment-file", title: caption) do
        tag.span("📄", class: "attachment-icon") + tag.span(caption, class: "attachment-name")
      end
    end
  end

  # Strip attachment tokens down to just their filename for plain-text contexts
  # like the card-face search haystack — a pasted image must not turn a card's
  # searchable text into base64 noise (card #21).
  def strip_attachment_tokens(text)
    text.to_s.gsub(ATTACHMENT_TOKEN) { Regexp.last_match(1) }
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
