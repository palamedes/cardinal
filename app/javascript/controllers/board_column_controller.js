import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import Sortable from "sortablejs"

// Drag-and-drop for a column's card list. Moving a card PATCHes /cards/:id/move;
// the server is the authority — a 422 snaps the card back and shows why.
export default class extends Controller {
  static values = { hint: String, newUrl: String }

  // A bare click on the column background — not on a card — opens the New Card
  // composer, mirroring the header's [+]. Cards keep their own click (open
  // detail); we only act when the click lands on the container itself.
  newCard(event) {
    if (event.target !== this.element || !this.hasNewUrlValue) return
    document.getElementById("modal").src = this.newUrlValue
  }

  connect() {
    this.sortable = Sortable.create(this.element, {
      group: "cards",
      animation: 150,
      ghostClass: "card-ghost",
      onStart: () => {
        document.body.classList.add("dragging")
        this.markBlockedColumns()
      },
      onEnd: (event) => {
        document.body.classList.remove("dragging")
        this.clearBlockedColumns()
        this.move(event)
      }
    })
  }

  // Accept policies made visible: while dragging, columns that won't take a
  // card from THIS column gray out with a blocked hint. Server still rules.
  markBlockedColumns() {
    const sourceId = this.element.dataset.columnId
    document.querySelectorAll(".column").forEach(section => {
      if (section.dataset.colId === sourceId) return // reorder within is always fine
      const allowed = (section.dataset.accepts || "").split(",").filter(Boolean)
      if (!allowed.includes(sourceId)) section.classList.add("drop-blocked")
    })
  }

  clearBlockedColumns() {
    document.querySelectorAll(".column.drop-blocked").forEach(s => s.classList.remove("drop-blocked"))
  }

  disconnect() {
    this.sortable?.destroy()
  }

  async move(event) {
    const cardId = event.item.dataset.cardId
    const columnId = event.to.dataset.columnId
    if (event.to === event.from && event.newIndex === event.oldIndex) return

    const response = await fetch(`/cards/${cardId}/move`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/vnd.turbo-stream.html, application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify({ column_id: columnId, position: event.newIndex })
    })

    if (response.ok) {
      // Server-rendered truth for both columns: instant queued/working
      // styling, ticker counts, queue positions.
      Turbo.renderStreamMessage(await response.text())
    } else {
      // Server said no: snap the card back where it came from and flash a red
      // border so the bounce reads as a rejection, not a glitch.
      event.from.insertBefore(event.item, event.from.children[event.oldIndex])
      const body = await response.json().catch(() => ({}))
      this.flashRejected(event.item, body.error)
    }
  }

  flashRejected(card, message) {
    // Surface the reason on hover for the life of the flash; the durable
    // record lives in the card's event timeline.
    const priorTitle = card.getAttribute("title")
    if (message) card.setAttribute("title", message)
    card.classList.remove("move-rejected")
    // Force a reflow so re-adding the class restarts the animation.
    void card.offsetWidth
    card.classList.add("move-rejected")
    card.addEventListener("animationend", () => {
      card.classList.remove("move-rejected")
      if (message) priorTitle ? card.setAttribute("title", priorTitle) : card.removeAttribute("title")
    }, { once: true })
  }
}
