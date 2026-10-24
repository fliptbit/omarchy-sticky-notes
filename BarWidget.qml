import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar slot for Sticky Notes. The panel owns the notes list and file I/O;
// this just shows the icon (plus count) and routes clicks and IPC to it.
//
// Left click opens the panel, right click jumps straight to a new note.
BarWidget {
  id: root
  moduleName: "io.github.fliptbit.sticky-notes"

  // nf-fa-sticky_note
  readonly property string glyph: ""
  readonly property int noteCount: panelLoader.item ? panelLoader.item.notes.length : 0
  readonly property bool showCount: setting("showCount", true) === true

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function newNote() {
    if (panelLoader.item && panelLoader.item.openNew) panelLoader.item.openNew()
  }

  // An IPC target routes to a single handler, but there is a bar per
  // monitor; summon the instance on the focused monitor.
  function focusedInstance() {
    if (root.bar && typeof root.bar.findPanelWidget === "function") {
      var item = root.bar.findPanelWidget(root.moduleName)
      if (item) return item
    }
    return root
  }

  // Shape contract for shell.summon/hide/toggle routing.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.fliptbit.sticky-notes"

    function open(): void { root.focusedInstance().open() }
    function close(): void { root.focusedInstance().close() }
    function show(): void { root.focusedInstance().open() }
    function hide(): void { root.focusedInstance().close() }
    function toggle(): void { root.focusedInstance().togglePanel() }
    function create(): void { root.focusedInstance().newNote() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (!root.vertical && root.showCount && root.noteCount > 0)
      ? root.glyph + " " + root.noteCount
      : root.glyph
    tooltipText: root.noteCount === 1 ? "1 sticky note" : root.noteCount + " sticky notes"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.newNote()
      else root.togglePanel()
    }
  }
}
