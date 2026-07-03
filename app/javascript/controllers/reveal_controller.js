import { Controller } from "@hotwired/stimulus"

// Show/hide dependent settings when a toggle changes (e.g. the column AI
// checkbox reveals model/effort/budget settings). Autosave still fires via
// the change event bubbling to the autosave controller.
export default class extends Controller {
  static targets = ["toggle", "panel"]

  connect() { this.sync() }

  sync() {
    const on = this.toggleTarget.checked
    this.panelTargets.forEach(p => p.classList.toggle("hidden", !on))
  }
}
