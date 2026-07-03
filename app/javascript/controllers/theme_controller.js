import { Controller } from "@hotwired/stimulus"

// Toggles between dark (default) and light themes by setting data-theme on
// <html> and persisting the choice to localStorage. The initial theme is
// applied by an inline boot script in the <head> to avoid a flash of the
// wrong theme; this controller only handles the toggle and keeps its label
// in sync with the current theme.
export default class extends Controller {
  static targets = ["label"]

  connect() {
    this.render()
  }

  toggle() {
    const next = this.current === "light" ? "dark" : "light"
    // Dark is the default, so we only persist/mark an explicit light choice.
    if (next === "light") {
      document.documentElement.setAttribute("data-theme", "light")
      localStorage.setItem("theme", "light")
    } else {
      document.documentElement.removeAttribute("data-theme")
      localStorage.setItem("theme", "dark")
    }
    this.render()
  }

  get current() {
    return document.documentElement.getAttribute("data-theme") === "light" ? "light" : "dark"
  }

  render() {
    // Show the action the button will take, not the current state.
    const toLight = this.current === "dark"
    const text = toLight ? "☀ Light" : "☾ Dark"
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = text
    } else {
      this.element.textContent = text
    }
    this.element.setAttribute("aria-label", toLight ? "Switch to light mode" : "Switch to dark mode")
  }
}
