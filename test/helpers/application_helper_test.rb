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
end
