import { Controller } from "@hotwired/stimulus"

// Tag picker: toggle existing tags, create new ones. Keeps a hidden
// comma-joined field in sync and fires an input event so autosave notices.
export default class extends Controller {
  static targets = ["field", "chips", "newTag"]

  toggle(event) {
    event.preventDefault()
    event.currentTarget.classList.toggle("on")
    this.sync()
  }

  keydown(event) {
    if (event.key !== "Enter") return
    event.preventDefault()
    this.add()
  }

  add() {
    const name = this.newTagTarget.value.trim().toLowerCase()
    this.newTagTarget.value = ""
    if (name === "") return

    const existing = this.chipTagged(name)
    if (existing) {
      existing.classList.add("on")
    } else {
      const chip = document.createElement("button")
      chip.type = "button"
      chip.className = "tag-chip on"
      chip.dataset.tag = name
      chip.dataset.action = "tags#toggle"
      chip.textContent = name
      this.chipsTarget.appendChild(chip)
    }
    this.sync()
  }

  chipTagged(name) {
    return [...this.chipsTarget.querySelectorAll(".tag-chip")].find(c => c.dataset.tag === name)
  }

  sync() {
    const selected = [...this.chipsTarget.querySelectorAll(".tag-chip.on")].map(c => c.dataset.tag)
    this.fieldTarget.value = selected.join(", ")
    this.fieldTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
