import { Controller } from "@hotwired/stimulus"

// Chat composer: Enter sends, Shift+Enter inserts a newline.
export default class extends Controller {
  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey) return
    event.preventDefault()
    if (this.element.value.trim() !== "") this.element.form.requestSubmit()
  }
}
