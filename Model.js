// Pure helpers for the sticky-notes plugin. Nothing here touches QML or the
// filesystem, so it can be exercised with plain node (see tests/).

var RECORD_SEP = "\x1e"
var FIELD_SEP = "\x1f"

// "~" and "~/x" expand against $HOME; anything else is returned trimmed.
function expandHome(path, home) {
  var p = String(path || "").trim()
  if (p === "~") return home
  if (p.indexOf("~/") === 0) return home + p.slice(1)
  return p
}

function stripTrailingSlash(path) {
  var p = String(path || "")
  while (p.length > 1 && p.charAt(p.length - 1) === "/") p = p.slice(0, -1)
  return p
}

// The folder notes live in. An Obsidian vault wins over the plain folder.
function resolveNotesDir(settings, home) {
  var s = settings || {}
  var vault = stripTrailingSlash(expandHome(s.obsidianVault, home))
  if (vault !== "") {
    var sub = String(s.vaultFolder === undefined || s.vaultFolder === null ? "Sticky Notes" : s.vaultFolder)
      .trim().replace(/^\/+|\/+$/g, "")
    return sub === "" ? vault : vault + "/" + sub
  }
  var dir = stripTrailingSlash(expandHome(s.notesDir, home))
  return dir !== "" ? dir : home + "/.local/share/sticky-notes"
}

// A title becomes a filename Obsidian and every filesystem accept: no path
// separators or characters Obsidian rejects in links, no leading dots.
function sanitizeTitle(title) {
  var t = String(title || "")
    .replace(/[\\\/:*?"<>|#^\[\]\x00-\x1f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^\.+/, "")
    .trim()
  if (t.length > 80) t = t.slice(0, 80).trim()
  return t
}

function defaultTitle(now) {
  var d = now || new Date()
  function pad(n) { return n < 10 ? "0" + n : String(n) }
  return "Note " + d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
    + " " + pad(d.getHours()) + pad(d.getMinutes())
}

// Picks "<title>.md", or "<title> 2.md", "<title> 3.md", ... when taken.
// Comparison is case-insensitive so it is safe on case-folding filesystems.
function uniqueFileName(title, existingNames) {
  var base = sanitizeTitle(title)
  if (base === "") base = "Untitled"
  var taken = {}
  for (var i = 0; i < (existingNames || []).length; i++)
    taken[String(existingNames[i]).toLowerCase()] = true
  var name = base + ".md"
  var n = 2
  while (taken[name.toLowerCase()]) {
    name = base + " " + n + ".md"
    n++
  }
  return name
}

function baseName(path) {
  var p = String(path || "")
  var slash = p.lastIndexOf("/")
  return slash === -1 ? p : p.slice(slash + 1)
}

function titleFromPath(path) {
  return baseName(path).replace(/\.md$/i, "")
}

// Obsidian notes often open with YAML front matter; it is noise in a preview.
function stripFrontMatter(text) {
  var t = String(text || "")
  if (t.indexOf("---\n") !== 0 && t.indexOf("---\r\n") !== 0) return t
  var end = t.indexOf("\n---", 3)
  if (end === -1) return ""
  var after = t.indexOf("\n", end + 4)
  return after === -1 ? "" : t.slice(after + 1)
}

// A note that opens with "# <its own title>" would just repeat the title.
function dropTitleHeading(text, title) {
  var t = String(text || "").replace(/^\s+/, "")
  var nl = t.indexOf("\n")
  var first = (nl === -1 ? t : t.slice(0, nl)).trim()
  if (first.replace(/^#{1,6}\s+/, "").trim().toLowerCase() !== String(title).toLowerCase()) return text
  return nl === -1 ? "" : t.slice(nl + 1)
}

// One-line-ish preview: front matter dropped, markdown heading/list markers
// trimmed, blank lines collapsed.
function preview(text, maxChars) {
  var limit = maxChars || 120
  var lines = stripFrontMatter(text).split(/\r?\n/)
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s*(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|>\s*)/, "").trim()
    if (line !== "") out.push(line)
  }
  var joined = out.join(" · ")
  return joined.length > limit ? joined.slice(0, limit - 1).trimEnd() + "…" : joined
}

// Parses the listing script's output: records of path, mtime, head-of-file.
// Newest first, so the note you just touched is always at the top.
function parseListing(raw) {
  var records = String(raw || "").split(RECORD_SEP)
  var notes = []
  for (var i = 0; i < records.length; i++) {
    var rec = records[i]
    if (rec === "") continue
    var a = rec.indexOf(FIELD_SEP)
    if (a === -1) continue
    var b = rec.indexOf(FIELD_SEP, a + 1)
    if (b === -1) continue
    var path = rec.slice(0, a)
    var title = titleFromPath(path)
    notes.push({
      path: path,
      name: baseName(path),
      title: title,
      mtime: parseInt(rec.slice(a + 1, b), 10) || 0,
      preview: preview(dropTitleHeading(stripFrontMatter(rec.slice(b + 1)), title))
    })
  }
  notes.sort(function(x, y) {
    if (y.mtime !== x.mtime) return y.mtime - x.mtime
    return x.title.localeCompare(y.title)
  })
  return notes
}

function obsidianUri(path) {
  return "obsidian://open?path=" + encodeURIComponent(String(path || ""))
}

function relativeTime(mtimeSeconds, nowMs) {
  var diff = Math.max(0, Math.floor(((nowMs || Date.now()) - mtimeSeconds * 1000) / 1000))
  if (diff < 60) return "just now"
  if (diff < 3600) return Math.floor(diff / 60) + "m ago"
  if (diff < 86400) return Math.floor(diff / 3600) + "h ago"
  if (diff < 86400 * 30) return Math.floor(diff / 86400) + "d ago"
  var d = new Date(mtimeSeconds * 1000)
  return d.toISOString().slice(0, 10)
}

// Lets node's require() load this file for tests; QML ignores it.
if (typeof module !== "undefined") {
  module.exports = {
    expandHome: expandHome, resolveNotesDir: resolveNotesDir, sanitizeTitle: sanitizeTitle,
    defaultTitle: defaultTitle, uniqueFileName: uniqueFileName, titleFromPath: titleFromPath,
    stripFrontMatter: stripFrontMatter, dropTitleHeading: dropTitleHeading, preview: preview, parseListing: parseListing,
    obsidianUri: obsidianUri, relativeTime: relativeTime, RECORD_SEP: RECORD_SEP, FIELD_SEP: FIELD_SEP
  }
}
