import { Controller } from "@hotwired/stimulus"

// Board search & filter (card #51): one global query (topbar center) plus
// optional per-column queries (🔍 in each column header). A card must match
// both the global query and its own column's query; non-matches hide.
//
// Filter state lives HERE, not in the DOM — Turbo morphs and column stream
// replaces rebuild board markup at will, so a MutationObserver restores input
// values and re-applies hiding after every re-render.
export default class extends Controller {
  static targets = ["global"]

  connect() {
    this.state = { global: "", cols: {} }
    this.slash = (e) => {
      if (e.key === "/" && !e.target.closest("input, textarea, [contenteditable]")) {
        e.preventDefault()
        this.globalTarget.focus()
      }
    }
    document.addEventListener("keydown", this.slash)
    // childList only: our own class/value writes are attribute mutations and
    // must not re-trigger (no observe loop).
    this.observer = new MutationObserver(() => this.schedule())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    document.removeEventListener("keydown", this.slash)
    this.observer?.disconnect()
    clearTimeout(this.timer)
  }

  schedule() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.restore(), 60)
  }

  global(event) {
    this.state.global = event.target.value
    this.apply()
  }

  column(event) {
    this.state.cols[event.target.dataset.colId] = event.target.value
    this.apply()
  }

  toggle(event) {
    const col = event.currentTarget.closest(".column")
    const input = col.querySelector(".col-search")
    if (input.classList.toggle("open")) {
      input.focus()
    } else {
      input.value = ""
      this.state.cols[col.dataset.colId] = ""
      this.apply()
    }
  }

  // Esc inside a search box clears just that box.
  clear(event) {
    if (event.key !== "Escape") return
    event.target.value = ""
    if (this.hasGlobalTarget && event.target === this.globalTarget) {
      this.state.global = ""
    } else {
      this.state.cols[event.target.dataset.colId] = ""
    }
    event.target.blur()
    this.apply()
  }

  // After a morph or column replace rebuilt markup: put state back into any
  // re-rendered inputs (never fighting one the user is typing in), re-open
  // column boxes that hold a query, then re-hide.
  restore() {
    if (this.hasGlobalTarget && document.activeElement !== this.globalTarget) {
      this.globalTarget.value = this.state.global
    }
    this.element.querySelectorAll(".col-search").forEach(input => {
      const q = this.state.cols[input.dataset.colId] || ""
      if (document.activeElement !== input) input.value = q
      if (q !== "") input.classList.add("open")
    })
    this.apply()
  }

  apply() {
    const g = this.norm(this.state.global)
    this.element.querySelectorAll(".card[data-search]").forEach(card => {
      const colId = card.closest(".column")?.dataset.colId
      const c = this.norm(this.state.cols[colId])
      const hay = card.dataset.search
      const hit = (!g || hay.includes(g)) && (!c || hay.includes(c))
      card.classList.toggle("filter-hidden", !hit)
    })
  }

  norm(value) {
    return (value || "").trim().toLowerCase()
  }
}
