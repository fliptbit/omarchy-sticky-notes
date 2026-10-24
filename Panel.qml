import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Sticky Notes popup. Three modes share one card:
//   list   - every note in the folder, newest first
//   create - a title field above the list
//   edit   - a plain-text editor for one note, autosaved
//
// Notes are plain Markdown files in a folder (optionally a vault sub-folder),
// so Obsidian, an editor, or sync tools can all touch them. External edits
// are picked up live as long as the open note has no unsaved typing.
Panel {
  id: root
  moduleName: "io.github.fliptbit.sticky-notes"
  ipcTarget: "io.github.fliptbit.sticky-notes"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot (BarWidget.qml), not this
  // nested panel, so popout coordination must use that widget's identity.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color dimFg: Qt.darker(fg, 1.5)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  readonly property string home: Quickshell.env("HOME")
  readonly property string notesDir: Model.resolveNotesDir(root.settings, root.home)
  readonly property bool obsidianEnabled: String(setting("obsidianVault", "")).trim() !== ""
  readonly property string displayDir: notesDir.indexOf(home + "/") === 0 ? "~" + notesDir.slice(home.length) : notesDir

  property var notes: []
  property int selectedIndex: 0
  property string mode: "list"
  property string currentPath: ""
  readonly property string currentTitle: Model.titleFromPath(currentPath)
  property bool dirty: false
  property bool applyingLoad: false
  property string pendingDeletePath: ""
  property string pendingOpenPath: ""
  // Note to highlight once the next listing lands (the one just edited).
  property string selectPath: ""
  property bool refreshQueued: false
  property string errorText: ""

  onNotesDirChanged: {
    if (root.mode === "edit") root.backToList()
    root.refresh()
  }

  // ---- lifecycle ----------------------------------------------------------

  function open() {
    root.mode = "list"
    root.errorText = ""
    root.pendingDeletePath = ""
    root.controller.show()
    root.refresh()
  }

  function openNew() {
    if (!root.opened) {
      root.errorText = ""
      root.controller.show()
      root.refresh()
    }
    root.startCreate()
  }

  function close() {
    root.saveNow()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function focusLater(item) {
    Qt.callLater(function() { if (item) item.forceActiveFocus() })
  }

  // ---- listing ------------------------------------------------------------

  function refresh() {
    if (listProc.running) {
      root.refreshQueued = true
      return
    }
    listProc.command = ["bash", "-c",
      "dir=\"$0\"; [[ -d \"$dir\" ]] || exit 0; shopt -s nullglob; "
      + "for f in \"$dir\"/*.md; do [[ -f \"$f\" ]] || continue; "
      + "printf '\\036%s\\037%s\\037' \"$f\" \"$(stat -c %Y -- \"$f\")\"; "
      + "head -c 600 -- \"$f\"; done",
      root.notesDir]
    listProc.running = true
  }

  function applyListing(raw) {
    var selectedPath = root.notes[root.selectedIndex] ? root.notes[root.selectedIndex].path : ""
    if (root.selectPath !== "") {
      selectedPath = root.selectPath
      root.selectPath = ""
    }
    root.notes = Model.parseListing(raw)
    var idx = 0
    for (var i = 0; i < root.notes.length; i++) {
      if (root.notes[i].path === selectedPath) { idx = i; break }
    }
    root.selectedIndex = idx
  }

  function moveSelection(dy) {
    if (root.notes.length === 0) return
    root.selectedIndex = Math.max(0, Math.min(root.notes.length - 1, root.selectedIndex + dy))
    root.pendingDeletePath = ""
  }

  // ---- create -------------------------------------------------------------

  function startCreate() {
    root.saveNow()
    root.mode = "create"
    root.errorText = ""
    titleField.text = ""
    root.focusLater(titleField)
  }

  function cancelCreate() {
    root.mode = "list"
    root.focusLater(keyCatcher)
  }

  function commitCreate() {
    var title = titleField.text.trim()
    if (title === "") title = Model.defaultTitle(new Date())
    var names = root.notes.map(function(n) { return n.name })
    var path = root.notesDir + "/" + Model.uniqueFileName(title, names)
    root.pendingOpenPath = path
    // noclobber: never truncate a file that appeared since the last listing.
    createProc.command = ["bash", "-c", "mkdir -p -- \"$0\" && set -C && : > \"$1\"", root.notesDir, path]
    createProc.running = true
  }

  // ---- edit ---------------------------------------------------------------

  function openNote(path) {
    if (!path) return
    root.saveNow()
    root.dirty = false
    root.applyingLoad = true
    editor.text = ""
    root.applyingLoad = false
    root.currentPath = path
    root.mode = "edit"
    root.errorText = ""
    root.pendingDeletePath = ""
    noteFile.reload()
    root.focusLater(editor)
  }

  function applyLoaded(text) {
    if (root.dirty || root.mode !== "edit") return
    if (editor.text === text) return
    var pos = editor.cursorPosition
    root.applyingLoad = true
    editor.text = text
    editor.cursorPosition = Math.min(pos, text.length)
    root.applyingLoad = false
  }

  function saveNow() {
    saveTimer.stop()
    if (!root.dirty || root.currentPath === "") return
    root.dirty = false
    noteFile.setText(editor.text)
    // Finish the write before the caller can repoint the FileView.
    noteFile.waitForJob()
    refreshTimer.restart()
  }

  function backToList() {
    root.saveNow()
    root.selectPath = root.currentPath
    root.mode = "list"
    root.pendingDeletePath = ""
    root.refresh()
    root.focusLater(keyCatcher)
  }

  // ---- delete & obsidian --------------------------------------------------

  // First press arms, second press within a few seconds trashes the file.
  function requestDelete(path) {
    if (!path) return
    if (root.pendingDeletePath !== path) {
      root.pendingDeletePath = path
      deleteArmTimer.restart()
      return
    }
    root.pendingDeletePath = ""
    deleteArmTimer.stop()
    if (path === root.currentPath) {
      saveTimer.stop()
      root.dirty = false
      root.currentPath = ""
      root.mode = "list"
      root.focusLater(keyCatcher)
    }
    deleteProc.command = ["bash", "-c", "gio trash -- \"$0\" 2>/dev/null || rm -f -- \"$0\"", path]
    deleteProc.running = true
  }

  function openInObsidian(path) {
    if (!path || !root.obsidianEnabled) return
    root.saveNow()
    Quickshell.execDetached(["xdg-open", Model.obsidianUri(path)])
    root.close()
  }

  // ---- I/O ----------------------------------------------------------------

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyListing(text)
    }
    onExited: {
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: createProc
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.errorText = "Could not create note in " + root.displayDir
        return
      }
      root.openNote(root.pendingOpenPath)
      root.refresh()
    }
  }

  Process {
    id: deleteProc
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorText = "Could not delete note"
      root.refresh()
    }
  }

  FileView {
    id: noteFile
    path: root.currentPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: if (!root.dirty) reload()
    onLoaded: root.applyLoaded(text())
    onSaveFailed: root.errorText = "Could not save " + root.currentTitle
  }

  Timer {
    id: saveTimer
    interval: 700
    onTriggered: root.saveNow()
  }

  // Coalesces list refreshes after saves so typing doesn't spawn a process
  // per keystroke.
  Timer {
    id: refreshTimer
    interval: 1500
    onTriggered: root.refresh()
  }

  Timer {
    id: deleteArmTimer
    interval: 3000
    onTriggered: root.pendingDeletePath = ""
  }

  // Picks up notes added elsewhere (Obsidian, sync) so the bar count stays
  // honest without the panel being opened.
  Timer {
    interval: 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (root.mode !== "edit") root.refresh()
  }

  // ---- UI -----------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: root.mode === "create" ? titleField : (root.mode === "edit" ? editor : keyCatcher)
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: editor.activeFocus || titleField.activeFocus
      onMoveRequested: function(dx, dy) { root.moveSelection(dy) }
      onActivateRequested: {
        var note = root.notes[root.selectedIndex]
        if (note) root.openNote(note.path)
      }
      onCloseRequested: root.close()
      onDeleteRequested: {
        var note = root.notes[root.selectedIndex]
        if (note) root.requestDelete(note.path)
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "n") root.startCreate()
        else if (t === "o") {
          var note = root.notes[root.selectedIndex]
          if (note) root.openInObsidian(note.path)
        } else if (t === "r") root.refresh()
      }

      Column {
        id: body
        width: parent.width
        spacing: Style.space(10)

        // ---- header
        Item {
          width: parent.width
          height: Math.max(headerLeft.implicitHeight, headerRight.implicitHeight)

          Row {
            id: headerLeft
            anchors.left: parent.left
            anchors.right: headerRight.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
              id: backButton
              visible: root.mode === "edit"
              anchors.verticalCenter: parent.verticalCenter
              iconText: ""  // nf-fa-chevron_left
              tooltipText: "Back to notes (Esc)"
              onClicked: root.backToList()
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: headerLeft.width - (backButton.visible ? backButton.width + headerLeft.spacing : 0)
              spacing: Style.space(2)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: root.mode === "edit" ? root.currentTitle : "Sticky Notes"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                text: root.mode === "edit"
                  ? (root.dirty ? "Editing…" : "Saved")
                  : (root.notes.length === 1 ? "1 note" : root.notes.length + " notes") + " · " + root.displayDir
                color: root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Row {
            id: headerRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Button {
              visible: root.mode !== "edit"
              iconText: ""  // nf-fa-plus
              text: "New"
              tooltipText: "New note (n)"
              onClicked: root.startCreate()
            }
            Button {
              visible: root.mode === "edit" && root.obsidianEnabled
              iconText: ""  // nf-fa-external_link_alt
              text: "Obsidian"
              tooltipText: "Open this note in Obsidian"
              onClicked: root.openInObsidian(root.currentPath)
            }
            Button {
              visible: root.mode === "edit"
              iconText: ""  // nf-fa-trash
              text: root.pendingDeletePath === root.currentPath ? "Confirm" : ""
              active: root.pendingDeletePath === root.currentPath
              tooltipText: "Move note to trash"
              onClicked: root.requestDelete(root.currentPath)
            }
          }
        }

        Text {
          visible: root.errorText !== ""
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.errorText
          color: Commons.Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // ---- create
        TextField {
          id: titleField
          visible: root.mode === "create"
          width: parent.width
          placeholderText: "Note title — Enter to create, Esc to cancel"
          foreground: root.fg
          font.family: root.fontFamily

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.cancelCreate()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.commitCreate()
              event.accepted = true
            }
          }
        }

        // ---- list
        Text {
          visible: root.mode !== "edit" && root.notes.length === 0
          width: parent.width
          topPadding: Style.space(12)
          bottomPadding: Style.space(12)
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: "No notes yet. Press n or click New."
          color: root.dimFg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.italic: true
        }

        Flickable {
          id: listScroll
          visible: root.mode !== "edit" && root.notes.length > 0
          width: parent.width
          height: Math.min(listColumn.implicitHeight, Style.space(420))
          contentWidth: width
          contentHeight: listColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: listColumn
            width: listScroll.width
            spacing: Style.space(2)

            Repeater {
              model: root.notes

              Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool selected: index === root.selectedIndex
                readonly property bool armed: root.pendingDeletePath === modelData.path

                width: listColumn.width
                height: rowContent.implicitHeight + Style.space(14)
                radius: Style.cornerRadius
                color: selected ? Style.hoverFillFor(root.fg, Commons.Color.accent) : "transparent"

                onSelectedChanged: {
                  if (!selected) return
                  var top = row.y
                  var bottom = row.y + row.height
                  if (top < listScroll.contentY) listScroll.contentY = top
                  else if (bottom > listScroll.contentY + listScroll.height)
                    listScroll.contentY = bottom - listScroll.height
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPositionChanged: root.selectedIndex = row.index
                  onClicked: root.openNote(row.modelData.path)
                }

                Column {
                  id: rowContent
                  anchors.left: parent.left
                  anchors.right: trashButton.left
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  Item {
                    width: parent.width
                    height: rowTitle.implicitHeight

                    Text {
                      id: rowTitle
                      anchors.left: parent.left
                      anchors.right: rowTime.left
                      anchors.rightMargin: Style.space(8)
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      text: row.modelData.title
                      color: row.selected ? Style.hoverStateColor(root.fg, Commons.Color.accent) : root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                    Text {
                      id: rowTime
                      anchors.right: parent.right
                      anchors.verticalCenter: rowTitle.verticalCenter
                      textFormat: Text.PlainText
                      text: row.armed ? "x again to delete" : Model.relativeTime(row.modelData.mtime, Date.now())
                      color: row.armed ? Commons.Color.urgent : root.dimFg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    visible: text !== ""
                    width: parent.width
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    text: row.modelData.preview
                    color: root.dimFg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Button {
                  id: trashButton
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: row.selected || row.armed ? 1 : 0
                  iconText: ""  // nf-fa-trash
                  active: row.armed
                  tooltipText: row.armed ? "Click again to delete" : "Move to trash"
                  onClicked: root.requestDelete(row.modelData.path)
                }
              }
            }
          }
        }

        // ---- editor
        BorderSurface {
          id: editorFrame
          visible: root.mode === "edit"
          width: parent.width
          height: Style.space(340)
          radius: Style.cornerRadius
          color: Style.controlFill(editor.activeFocus, false, root.fg, Commons.Color.accent)
          borderSpec: Border.controlSpec(editor.activeFocus ? "focus" : "normal", root.fg, Commons.Color.accent)

          QQC.ScrollView {
            anchors.fill: parent
            anchors.margins: Style.space(4)
            clip: true

            QQC.TextArea {
              id: editor
              wrapMode: TextEdit.Wrap
              textFormat: TextEdit.PlainText
              selectByMouse: true
              persistentSelection: true
              placeholderText: "Write something…"
              placeholderTextColor: Qt.darker(root.fg, 1.6)
              color: root.fg
              selectionColor: Style.selectionFillFor(root.fg, Commons.Color.accent)
              selectedTextColor: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              background: null

              onTextChanged: {
                if (root.applyingLoad || root.mode !== "edit") return
                root.dirty = true
                saveTimer.restart()
              }

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.backToList()
                  event.accepted = true
                } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                  root.saveNow()
                  event.accepted = true
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: root.mode === "edit"
            ? "autosaves · Ctrl+S save · Esc back"
            : (root.obsidianEnabled
              ? "n new · ⏎ open · x delete · o Obsidian · Esc close"
              : "n new · ⏎ open · x delete · Esc close")
          color: Qt.darker(root.fg, 1.8)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
