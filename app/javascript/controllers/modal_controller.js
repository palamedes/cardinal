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

  // For _top-targeted forms (create card, deletes): the frame is
  // turbo-permanent, so it survives the follow-up page render — close it
  // explicitly once the submission succeeds.
  closeOnSuccess(event) {
    if (event.detail.success) this.close()
  }

  close() {
    const frame = this.element.closest("turbo-frame")
    frame.removeAttribute("src")
    frame.innerHTML = ""
  }
}
