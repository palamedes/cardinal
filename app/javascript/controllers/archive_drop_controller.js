import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// The topbar 🗄 as a drop bin: cards dragged from whitelisted columns
// (board.archive_accepts_from, set on the archive page) can be dropped here
// to archive in one motion. The link inside keeps its normal click.
export default class extends Controller {
  connect() {
    this.sortable = Sortable.create(this.element, {
      group: {
        name: "cards",
        pull: false,
        put: (_to, from) => this.accepts(from.el.dataset.columnId)
      },
      onAdd: (event) => this.archive(event)
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }

  accepts(columnId) {
    const allowed = (this.element.dataset.accepts || "").split(",").filter(Boolean)
    return allowed.includes(columnId)
  }

  async archive(event) {
    const number = event.item.dataset.cardId
    // Drop the dragged face immediately; the server's refresh broadcast is
    // the durable truth (board re-renders active cards + the 🗄 count).
    event.item.remove()
    await fetch(`/cards/${number}/archive`, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
        "Accept": "text/html"
      }
    })
  }
}
