# Sticky Notes for Omarchy

A small [Omarchy](https://omarchy.org/) shell plugin that puts sticky notes in your bar.
Click the icon to see your notes, open one to edit it, or right-click to start a new one.

Notes are plain Markdown files in a folder, one file per note. By default that folder is
`~/.local/share/sticky-notes`. You can point it at an Obsidian vault instead, and then
Obsidian, your editor and your sync tools all see the same notes.

## Install

```bash
omarchy plugin add https://github.com/fliptbit/omarchy-sticky-notes.git --enable
```

The widget is added to the right side of the bar. Move it with
`omarchy bar move io.github.fliptbit.sticky-notes --section <left|center|right>`.

## Using it

| Where       | Key / action      | Does                                      |
|-------------|-------------------|-------------------------------------------|
| Bar         | Left click        | Open or close the notes panel             |
| Bar         | Right click       | Start a new note                          |
| List        | `n`               | New note (type a title, Enter)            |
| List        | `j`/`k`, arrows   | Move the selection                        |
| List        | Enter / click     | Open the note                             |
| List        | `x` twice         | Move the note to the trash                |
| List        | `o`               | Open in Obsidian (when a vault is set)    |
| Editor      | (just type)       | Saves automatically                       |
| Editor      | Ctrl+S            | Save now                                  |
| Editor      | Esc               | Back to the list                          |

Deleted notes go to the desktop trash (`gio trash`), so they can be restored.

## Settings

Settings are stored on the widget's entry in `~/.config/omarchy/shell.json`.
Set them with `omarchy bar set`, and they apply right away:

| Key             | Default                       | Meaning                                                    |
|-----------------|-------------------------------|------------------------------------------------------------|
| `notesDir`      | `~/.local/share/sticky-notes` | Folder for notes when no vault is set                      |
| `obsidianVault` | *(empty)*                     | Path to an Obsidian vault root; when set, it overrides `notesDir` |
| `vaultFolder`   | `Sticky Notes`                | Sub-folder inside the vault (empty = vault root)           |
| `showCount`     | `true`                        | Show the number of notes next to the bar icon              |

```bash
# Keep notes in an Obsidian vault
omarchy bar set io.github.fliptbit.sticky-notes obsidianVault "~/obsidian-vaults/home-vault"
omarchy bar set io.github.fliptbit.sticky-notes vaultFolder "Inbox/Sticky"

# Back to the plain folder
omarchy bar set io.github.fliptbit.sticky-notes obsidianVault ""
```

When a vault is set, the editor shows an **Obsidian** button that opens the note
through an `obsidian://open?path=…` link.

## Keybinding / IPC

The plugin answers `open`, `close`, `toggle` and `create` over shell IPC:

```bash
omarchy-shell io.github.fliptbit.sticky-notes toggle
omarchy-shell io.github.fliptbit.sticky-notes create
```

For example, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + N", "New sticky note", "omarchy-shell io.github.fliptbit.sticky-notes create")
```

## Development

```bash
node tests/model.test.js          # pure helper tests
omarchy plugin validate .         # manifest check

# Run from a checkout
ln -sfn "$PWD" ~/.config/omarchy/plugins/io.github.fliptbit.sticky-notes
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.fliptbit.sticky-notes
```

The shell's hot reload does not follow symlinks, so run `omarchy restart shell`
after editing files in a symlinked checkout.

## License

MIT
