import { Controller } from "@hotwired/stimulus"

// (i) tooltips. Rendered into document.body with fixed positioning so they
// can never be clipped by modal overflow; clamped to the viewport.
export default class extends Controller {
  static values = { text: String }

  show() {
    this.hide()
    this.pop = document.createElement("div")
    this.pop.className = "tooltip-pop"
    this.pop.textContent = this.textValue
    document.body.appendChild(this.pop)

    const icon = this.element.getBoundingClientRect()
    const pop = this.pop.getBoundingClientRect()
    const margin = 8

    let left = icon.left + icon.width / 2 - pop.width / 2
    left = Math.max(margin, Math.min(left, window.innerWidth - pop.width - margin))

    let top = icon.top - pop.height - margin
    if (top < margin) top = icon.bottom + margin

    this.pop.style.left = `${left}px`
    this.pop.style.top = `${top}px`
  }

  hide() {
    this.pop?.remove()
    this.pop = null
  }

  disconnect() {
    this.hide()
  }
}
