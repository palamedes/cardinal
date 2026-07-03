import { Controller } from "@hotwired/stimulus"

// GitHub-style copy button: copies textValue, flashes a checkmark.
export default class extends Controller {
  static values = { text: String }
  static targets = ["button"]

  async copy() {
    await navigator.clipboard.writeText(this.textValue)
    const original = this.buttonTarget.textContent
    this.buttonTarget.textContent = "✓"
    this.buttonTarget.classList.add("copied")
    setTimeout(() => {
      this.buttonTarget.textContent = original
      this.buttonTarget.classList.remove("copied")
    }, 1200)
  }
}
