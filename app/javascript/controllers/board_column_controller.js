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
      onStart: () => document.body.classList.add("dragging"),
      onEnd: (event) => {
        document.body.classList.remove("dragging")
        this.move(event)
      }
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
      event.from.insertBefore(event.item, event.from.children[event.oldIndex])
      const body = await response.json().catch(() => ({}))
      if (body.error) alert(body.error)
    }
  }
}
