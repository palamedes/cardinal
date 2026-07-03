import { Controller } from "@hotwired/stimulus"

// Silent autosave for the card details form: debounce edits, submit, whisper.
export default class extends Controller {
  static targets = ["status", "form"]

  connect() {
    this.onEnd = () => {
      if (!this.hasStatusTarget) return
      this.statusTarget.textContent = "Saved ✓"
      clearTimeout(this.fade)
      this.fade = setTimeout(() => (this.statusTarget.textContent = ""), 1500)
    }
    this.element.addEventListener("turbo:submit-end", this.onEnd)
  }

  disconnect() {
    clearTimeout(this.timer)
    clearTimeout(this.fade)
    this.element.removeEventListener("turbo:submit-end", this.onEnd)
  }

  save() {
    if (this.hasStatusTarget) this.statusTarget.textContent = "…"
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.formTarget.requestSubmit(), 800)
  }
}
