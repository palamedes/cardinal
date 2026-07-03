import { Controller } from "@hotwired/stimulus"

// Keeps the card timeline pinned to the latest entry: on open, and whenever
// an event is appended (user send re-render or live broadcast).
export default class extends Controller {
  connect() {
    this.scrollToBottom()
    this.observer = new MutationObserver(() => this.scrollToBottom())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  scrollToBottom() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
