import { Controller } from "@hotwired/stimulus"

// Silent autosave for the card details form: debounce edits, submit, whisper.
export default class extends Controller {
  static targets = ["status", "form"]

  connect() {
    this.onEnd = (event) => {
      if (!this.hasStatusTarget) return
      this.statusTarget.textContent = event.detail?.success === false ? "✗ not saved" : "Saved ✓"
      clearTimeout(this.fade)
      this.fade = setTimeout(() => (this.statusTarget.textContent = ""), 1500)
    }
    this.element.addEventListener("turbo:submit-end", this.onEnd)

    // A closing modal must not eat a pending debounce — flush immediately.
    this.onModalClose = () => this.flush()
    document.addEventListener("cardinal:modal-closing", this.onModalClose)
  }

  disconnect() {
    clearTimeout(this.timer)
    clearTimeout(this.fade)
    this.element.removeEventListener("turbo:submit-end", this.onEnd)
    document.removeEventListener("cardinal:modal-closing", this.onModalClose)
  }

  flush() {
    if (!this.timer) return
    clearTimeout(this.timer)
    this.timer = null
    this.formTarget.requestSubmit()
  }

  save() {
    if (this.hasStatusTarget) this.statusTarget.textContent = "…"
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.timer = null
      this.formTarget.requestSubmit()
    }, 800)
  }
}
