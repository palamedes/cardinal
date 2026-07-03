import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag-and-drop for a column's card list. Moving a card PATCHes /cards/:id/move;
// the server is the authority — a 422 snaps the card back and shows why.
export default class extends Controller {
  static values = { hint: String }

  connect() {
    this.sortable = Sortable.create(this.element, {
      group: "cards",
      animation: 150,
      ghostClass: "card-ghost",
      onEnd: (event) => this.move(event)
    })
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
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify({ column_id: columnId, position: event.newIndex })
    })

    if (!response.ok) {
      event.from.insertBefore(event.item, event.from.children[event.oldIndex])
      const body = await response.json().catch(() => ({}))
      if (body.error) alert(body.error)
    }
  }
}
