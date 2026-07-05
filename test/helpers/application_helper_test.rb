require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "renders markdown headers, bold, and fenced code" do
    html = render_markdown("## Plan\n\n**bold** and `inline`\n\n```erb\n<div class=\"x\">\n```")
    assert_match %r{<h2>Plan</h2>}, html
    assert_match %r{<strong>bold</strong>}, html
    assert_match %r{<code}, html
  end

  test "raw HTML in messages is escaped, never injected" do
    html = render_markdown(%(before <div class="topbar-right">boom</div> after))
    assert_no_match %r{<div class="topbar-right">}, html
    assert_match %r{&lt;div}, html
  end

  test "javascript links never become anchors" do
    html = render_markdown("[click](javascript:alert(1))")
    assert_no_match %r{<a[^>]+javascript:}, html
  end

  # --- Attachment tokens (card #21) ---

  PNG_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==".freeze

  def image_token(name: "shot.png", mime: "image/png", size: 1234, data: PNG_B64)
    %([[cardinal:file name="#{name}" mime="#{mime}" size="#{size}"]]#{data}[[/cardinal:file]])
  end

  def file_token(name: "notes.md", mime: "text/markdown", size: 4096, data: "aGVsbG8=")
    %([[cardinal:file name="#{name}" mime="#{mime}" size="#{size}"]]#{data}[[/cardinal:file]])
  end

  test "image attachment renders an inline data-url thumbnail with a caption" do
    html = render_with_attachments("Here is a screenshot:\n\n#{image_token}")
    assert_match %r{<img[^>]+src="data:image/png;base64,#{Regexp.escape(PNG_B64)}"}, html
    assert_match %r{<figcaption>shot\.png}, html
    assert_no_match(/cardinal:file/, html) # the raw token never leaks through
  end

  test "text/code attachment renders a badge, not an image" do
    html = render_with_attachments("See #{file_token}")
    assert_no_match(/<img/, html)
    assert_match %r{attachment-file}, html
    assert_match %r{notes\.md}, html
  end

  test "a spoofed html mime never becomes an image and is escaped" do
    html = render_with_attachments(image_token(name: "x.png", mime: "text/html", data: "PHNjcmlwdD4="))
    assert_no_match(/<img/, html)
    assert_no_match(/<script>/, html)
    assert_match %r{attachment-file}, html
  end

  test "prose around a token is still rendered as markdown" do
    html = render_with_attachments("**bold** #{image_token} after")
    assert_match %r{<strong>bold</strong>}, html
    assert_match %r{<img}, html
    assert_match %r{after}, html
  end

  test "text without tokens renders exactly like plain markdown" do
    assert_equal render_markdown("## Plain\n\ntext"), render_with_attachments("## Plain\n\ntext")
  end

  test "strip_attachment_tokens leaves only the filename for search haystacks" do
    stripped = strip_attachment_tokens("bug repro #{image_token(name: "err.png")} details")
    assert_equal "bug repro err.png details", stripped
    assert_no_match(/#{Regexp.escape(PNG_B64)}/, stripped)
  end
end
