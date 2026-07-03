import { Controller } from "@hotwired/stimulus"

// Chat-style timeline scrolling: pinned to the latest entry while you're at
// (or near) the bottom; if you've scrolled up to read, new entries show a
// "new messages" pill instead of yanking you down.
export default class extends Controller {
  static targets = ["scroller", "pill"]

  NEAR = 90 // px from the bottom that still counts as "at the bottom"

  connect() {
    this.scrollToBottom()
    this.observer = new MutationObserver(() => this.onAppend())
    this.observer.observe(this.scrollerTarget, { childList: true, subtree: true })
    this.onScroll = () => { if (this.nearBottom()) this.hidePill() }
    this.scrollerTarget.addEventListener("scroll", this.onScroll)
  }

  disconnect() {
    this.observer?.disconnect()
    this.scrollerTarget?.removeEventListener("scroll", this.onScroll)
  }

  onAppend() {
    this.nearBottom() ? this.scrollToBottom() : this.showPill()
  }

  jump() {
    this.scrollToBottom()
    this.hidePill()
  }

  nearBottom() {
    const el = this.scrollerTarget
    return el.scrollHeight - el.scrollTop - el.clientHeight < this.NEAR
  }

  scrollToBottom() {
    this.scrollerTarget.scrollTop = this.scrollerTarget.scrollHeight
  }

  showPill() { this.pillTarget.classList.add("visible") }
  hidePill() { this.pillTarget.classList.remove("visible") }
}
