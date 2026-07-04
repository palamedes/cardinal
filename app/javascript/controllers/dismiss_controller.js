import { Controller } from "@hotwired/stimulus"

// Briefly show a confirmation, then minimize the surrounding card modal.
// Rendered into an approval callout so the user sees the verdict land before
// the card snaps back to the columns view. On connect we start a timer; when
// it fires we hand off to the enclosing modal controller's close().
export default class extends Controller {
  static values = { delay: { type: Number, default: 1100 } }

  connect() {
    this.timer = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    const el = this.element.closest("[data-controller~='modal']")
    if (!el) return
    this.application.getControllerForElementAndIdentifier(el, "modal")?.close()
  }
}
