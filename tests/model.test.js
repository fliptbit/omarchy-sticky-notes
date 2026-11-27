// Run with: node tests/model.test.js
const assert = require("assert")

// Quickshell's QML engine has no trimStart/trimEnd (or their trimLeft/
// trimRight aliases); node does. Remove them so the tests fail the way the
// shell would.
for (const m of ["trimStart", "trimEnd", "trimLeft", "trimRight"]) delete String.prototype[m]

const M = require("../Model.js")

const H = "/home/u"
assert.strictEqual(M.resolveNotesDir({}, H), H + "/.local/share/sticky-notes")
assert.strictEqual(M.resolveNotesDir({ notesDir: "~/notes/" }, H), H + "/notes")
assert.strictEqual(M.resolveNotesDir({ notesDir: "~/n", obsidianVault: "~/vault" }, H), H + "/vault/Sticky Notes")
assert.strictEqual(M.resolveNotesDir({ obsidianVault: "/v/", vaultFolder: "/Inbox/Sticky/" }, H), "/v/Inbox/Sticky")
assert.strictEqual(M.resolveNotesDir({ obsidianVault: "/v", vaultFolder: "" }, H), "/v")

assert.strictEqual(M.sanitizeTitle("  a/b: c?  "), "a b c")
assert.strictEqual(M.sanitizeTitle("..hidden"), "hidden")
assert.strictEqual(M.uniqueFileName("Todo", ["todo.md", "Todo 2.md"]), "Todo 3.md")
assert.strictEqual(M.uniqueFileName("///", []), "Untitled.md")
assert.strictEqual(M.defaultTitle(new Date(2026, 9, 4, 9, 5)), "Note 2026-10-04 0905")

assert.strictEqual(M.preview("---\ntags: [x]\n---\n# Hi\n\n- [ ] milk\n- eggs\n"), "Hi · milk · eggs")
assert.strictEqual(M.preview("---\nunterminated"), "")
assert.strictEqual(M.preview("x".repeat(200), 10).length, 10)
assert.strictEqual(M.preview("aaaa bbbb cccc", 6), "aaaa…")

const R = M.RECORD_SEP, F = M.FIELD_SEP
const notes = M.parseListing(R + "/d/Old.md" + F + "100" + F + "old body" + R + "/d/New.md" + F + "200" + F + "")
assert.deepStrictEqual(notes.map(n => n.title), ["New", "Old"])
assert.strictEqual(notes[1].preview, "old body")
const titled = M.parseListing(R + "/d/Groceries.md" + F + "1" + F + "---\na: 1\n---\n# Groceries\n- milk\n")
assert.strictEqual(titled[0].preview, "milk")
assert.deepStrictEqual(M.parseListing(""), [])

assert.strictEqual(M.obsidianUri("/v/Sticky Notes/a&b.md"), "obsidian://open?path=%2Fv%2FSticky%20Notes%2Fa%26b.md")
assert.strictEqual(M.relativeTime(1000, 1000 * 1000 + 30 * 1000), "just now")
assert.strictEqual(M.relativeTime(0, 7200 * 1000), "2h ago")

console.log("ok")
