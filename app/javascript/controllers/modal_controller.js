import { Controller } from "@hotwired/stimulus"

// Near-fullscreen card modal rendered into the "modal" turbo-frame.
// Closes on Esc, backdrop click, or the ✕ button — unless `sticky`, in
// which case only the explicit close/cancel buttons (and a successful save)
// dismiss it. Sticky guards the new-card form so a stray click or Esc can't
// throw away everything you typed.
export default class extends Controller {
  static values = { sticky: Boolean }

  connect() {
    this.escHandler = (e) => { if (e.key === "Escape" && !this.stickyValue) this.close() }
    document.addEventListener("keydown", this.escHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.escHandler)
  }

  backdrop(event) {
    if (event.target === this.element && !this.stickyValue) this.close()
  }

  // For _top-targeted forms (create card, deletes): the frame is
  // turbo-permanent, so it survives the follow-up page render — close it
  // explicitly once the submission succeeds.
  closeOnSuccess(event) {
    if (event.detail.success) this.close()
  }

  close() {
    // Let autosave forms flush any pending debounce before the frame clears.
    document.dispatchEvent(new CustomEvent("cardinal:modal-closing"))
    const frame = this.element.closest("turbo-frame")
    frame.removeAttribute("src")
    frame.innerHTML = ""
    // Opening a card advances the URL to /cards/:id; closing must return the
    // address bar to the board. The board is still rendered behind the permanent
    // frame, so just rewrite the URL — no navigation needed. Back/forward still
    // work via Turbo's history snapshots.
    if (window.location.pathname.startsWith("/cards/")) {
      window.history.pushState({}, "", "/")
    }
  }
}
