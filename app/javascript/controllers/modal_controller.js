import { Controller } from "@hotwired/stimulus"

// Near-fullscreen card modal rendered into the "modal" turbo-frame.
// Closes on Esc, backdrop click, or the ✕ button.
export default class extends Controller {
  connect() {
    this.escHandler = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this.escHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.escHandler)
  }

  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  close() {
    const frame = this.element.closest("turbo-frame")
    frame.removeAttribute("src")
    frame.innerHTML = ""
  }
}
