import { Controller } from "@hotwired/stimulus"

// Paste files (images + text/code) into a textarea as base64 attachment tokens.
// The token stays inline in the field text — that is how the agent, the timeline
// renderer, and autosave all see it. Format (kept in sync with ApplicationHelper):
//   [[cardinal:file name="foo.png" mime="image/png" size="12345"]]<base64>[[/cardinal:file]]
export default class extends Controller {
  static values = {
    // Hard ceiling and the point where a paste is worth warning about (bytes).
    max: { type: Number, default: 500 * 1024 },
    warn: { type: Number, default: 250 * 1024 }
  }

  paste(event) {
    const files = Array.from(event.clipboardData?.items || [])
      .filter((item) => item.kind === "file")
      .map((item) => item.getAsFile())
      .filter(Boolean)

    // No files on the clipboard — let the browser paste text as usual.
    if (files.length === 0) return

    event.preventDefault()
    files.forEach((file) => this.attach(file))
  }

  attach(file) {
    if (file.size > this.maxValue) {
      this.notify(`"${file.name}" is ${this.kb(file.size)}KB — over the ${this.kb(this.maxValue)}KB limit. Not attached.`)
      return
    }
    if (file.size >= this.warnValue) {
      const proceed = window.confirm(
        `"${file.name}" is ${this.kb(file.size)}KB. Pasting it embeds the full file in this card, ` +
        `and every agent run and planning reply re-sends it as context — that consumes tokens and ` +
        `increases run cost each time. Attach it anyway?`
      )
      if (!proceed) return
    }

    const reader = new FileReader()
    reader.onload = () => {
      // FileReader gives us a data: URL; the base64 payload is after the comma.
      const base64 = String(reader.result).split(",", 2)[1] || ""
      const mime = file.type || "application/octet-stream"
      this.insert(this.token(file.name, mime, file.size, base64))
    }
    reader.readAsDataURL(file)
  }

  // Build one attachment token. The name is sanitized so quotes/brackets can
  // never break the delimiter the renderer parses back out.
  token(name, mime, size, base64) {
    const safeName = String(name || "file").replace(/["\[\]]/g, "").trim() || "file"
    return `[[cardinal:file name="${safeName}" mime="${mime}" size="${size}"]]${base64}[[/cardinal:file]]`
  }

  // Splice the token in at the cursor, then fire input so autosave (description)
  // and any other listeners react as if the user typed it.
  insert(token) {
    const el = this.element
    const start = el.selectionStart ?? el.value.length
    const end = el.selectionEnd ?? el.value.length
    const pad = start > 0 && !/\s$/.test(el.value.slice(0, start)) ? "\n" : ""
    const chunk = `${pad}${token}\n`
    el.value = el.value.slice(0, start) + chunk + el.value.slice(end)
    const caret = start + chunk.length
    el.setSelectionRange(caret, caret)
    el.dispatchEvent(new Event("input", { bubbles: true }))
    el.focus()
  }

  notify(message) {
    window.alert(message)
  }

  kb(bytes) {
    return Math.round(bytes / 1024)
  }
}
