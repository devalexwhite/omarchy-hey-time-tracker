import QtQuick
import QtQuick.Shapes
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "io.github.devalexwhite.hey-time-tracker"
    ipcTarget: "io.github.devalexwhite.hey-time-tracker"
    manageIpc: false
    readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
    property bool awaitingReview: false
    property bool finishing: false
    property var cachedDraft: null
    property var draftId: null
    readonly property color foreground: Color.popups.text
    readonly property var categoryOptions: {
        var result = [{ value: "", label: "Choose a category…" }]
        if (!service) return result
        for (var i = 0; i < service.categories.length; i++) {
            var category = service.categories[i]
            var name = typeof category === "string" ? category : (category.title || category.name || "")
            if (name) result.push({value: name, label: name})
        }
        return result
    }
    function pushSettings() { if (service) service.settings = settings }
    onSettingsChanged: pushSettings()
    onServiceChanged: pushSettings()
    Component.onCompleted: pushSettings()

    function localTime(value) {
        return value ? Qt.formatDateTime(new Date(value), "yyyy-MM-dd'T'HH:mm:ss") : ""
    }
    function draft() {
        return { start: startField.text, end: endField.text, category: categoryField.text, notes: notesField.text }
    }
    function showReview() {
        startField.text = localTime(service.state.start)
        endField.text = localTime(service.state.end)
        categoryField.text = cachedDraft && draftId === service.state.remoteId ? cachedDraft.category : (service.state.category || settings.defaultCategory || "")
        notesField.text = cachedDraft && draftId === service.state.remoteId ? cachedDraft.notes : (service.state.notes || settings.defaultNotes || "")
        finishing = false
        root.open()
        service.refreshCategories()
    }
    function activate() {
        if (!service || !service.loaded || service.busy) return
        if (opened) { root.close(); return }
        if (service.state.mode === "idle") service.start()
        else if (service.reviewing) showReview()
        else {
            awaitingReview = true
            if (!service.invoke("review")) awaitingReview = false
        }
    }
    function close() {
        root.controller.hide()
    }
    onOpenedChanged: {
        if (!opened && service && service.reviewing) {
            cachedDraft = draft()
            draftId = service.state.remoteId
            service.invoke("resume")
        }
    }
    Connections {
        target: root.service
        function onFinished(action, success) {
            if (action === "status" && success && root.opened && !root.service.reviewing) root.close()
            if (action === "review" && root.awaitingReview) {
                root.awaitingReview = false
                if (success) root.showReview()
            }
            if (action === "save" || action === "delete") {
                if (success) { root.cachedDraft = null; root.draftId = null; root.close() }
                root.finishing = false
            }
            if (action === "resume" && !success) root.showReview()
        }
    }
    implicitWidth: barButton.implicitWidth
    implicitHeight: barButton.implicitHeight
    WidgetButton {
        id: barButton
        anchors.fill: parent
        bar: root.bar
        interactive: !!root.service && root.service.loaded && !root.service.busy
        labelVisible: false
        hasVisualContent: true
        dimmed: !root.service || !root.service.loaded || (root.service.busy && root.service.request !== "status")
        readonly property bool showStop: !!root.service && (root.service.running || root.service.reviewing)
        fixedWidth: vertical ? -1 : (showStop ? buttonContent.implicitWidth + scaledHorizontalMargin * 2 : Style.bar.iconSlot)
        fixedHeight: vertical ? (showStop ? buttonContent.implicitHeight + scaledVerticalPadding * 2 : Style.bar.iconSlot) : -1
        Accessible.name: showStop ? "Stop tracking time" : "Start tracking time"
        tooltipText: root.service && root.service.error ? root.service.error
            : "HEY Calendar time tracking · " + (root.service && root.service.reviewing ? "Review tracked time"
                : showStop ? "Stop and review" : "Start tracking")
        onPressed: root.activate()
        Grid {
            id: buttonContent
            anchors.centerIn: parent
            columns: barButton.vertical || !barButton.showStop ? 1 : 2
            spacing: barButton.showStop ? Style.spacing.controlGap : 0
            Item {
                width: Style.bar.iconCanvas
                height: Style.bar.iconCanvas
                Shape {
                    id: actionIcon
                    anchors.centerIn: parent
                    width: Style.space(12)
                    height: Style.space(12)
                    ShapePath {
                        fillColor: barButton.foreground
                        strokeWidth: -1
                        startX: actionIcon.width * (barButton.showStop ? 0.15 : 0.25)
                        startY: actionIcon.height * (barButton.showStop ? 0.15 : 0.1)
                        PathLine {
                            x: actionIcon.width * (barButton.showStop ? 0.85 : 0.9)
                            y: actionIcon.height * (barButton.showStop ? 0.15 : 0.5)
                        }
                        PathLine {
                            x: actionIcon.width * (barButton.showStop ? 0.85 : 0.25)
                            y: actionIcon.height * (barButton.showStop ? 0.85 : 0.9)
                        }
                        PathLine {
                            x: actionIcon.width * (barButton.showStop ? 0.15 : 0.25)
                            y: actionIcon.height * (barButton.showStop ? 0.85 : 0.1)
                        }
                        PathLine {
                            x: actionIcon.width * (barButton.showStop ? 0.15 : 0.25)
                            y: actionIcon.height * (barButton.showStop ? 0.15 : 0.1)
                        }
                    }
                }
            }
            Text {
                visible: barButton.showStop
                text: root.service ? root.service.elapsed : ""
                textFormat: Text.PlainText
                color: barButton.foreground
                font.family: barButton.fontFamily
                font.pixelSize: barButton.fontSize
            }
        }
    }
    IpcHandler {
        target: root.ipcTarget
        function toggle(): void { root.activate() }
        function close(): void { root.close() }
        function status(): string {
            return JSON.stringify({ state: root.service ? root.service.state : null,
                error: root.service ? root.service.error : "Service unavailable", opened: root.opened })
        }
    }
    KeyboardPanel {
        id: popup
        anchorItem: barButton
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: startField
        contentWidth: fittedContentWidth(Style.space(410))
        contentHeight: fittedContentHeight(form.implicitHeight, Style.space(690))
        Flickable {
            anchors.fill: parent
            contentHeight: form.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Keys.onEscapePressed: root.close()
            ColumnLayout {
                id: form
                width: parent.width
                spacing: Style.space(10)
                enabled: !root.finishing
                Text {
                    text: "Save time to HEY"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                }
                Text {
                    text: root.service ? root.service.elapsed + " tracked" : ""
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }
                Text {
                    Layout.topMargin: Style.space(6)
                    text: "Start time"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }
                TextField {
                    id: startField
                    Layout.fillWidth: true
                    foreground: root.foreground
                    selectByMouse: true
                    placeholderText: "YYYY-MM-DDTHH:MM:SS"
                    Accessible.name: "Start time"
                }
                Text {
                    text: "End time"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }
                TextField {
                    id: endField
                    Layout.fillWidth: true
                    foreground: root.foreground
                    selectByMouse: true
                    placeholderText: "YYYY-MM-DDTHH:MM:SS"
                    Accessible.name: "End time"
                }
                Text {
                    Layout.fillWidth: true
                    text: "Times use " + (Quickshell.env("TZ") || "your system time zone") + ". An explicit UTC offset is also accepted."
                    wrapMode: Text.WordWrap
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }
                Text {
                    Layout.topMargin: Style.space(6)
                    text: "Category"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }
                Dropdown {
                    id: categoryPicker
                    Layout.fillWidth: true
                    visible: root.categoryOptions.length > 1
                    options: root.categoryOptions
                    value: categoryField.text
                    showLabel: false
                    foreground: root.foreground
                    onChanged: function(value) { categoryField.text = value }
                }
                TextField {
                    id: categoryField
                    Layout.fillWidth: true
                    foreground: root.foreground
                    selectByMouse: true
                    placeholderText: "Category title (optional)"
                    Accessible.name: "Category"
                }
                Text {
                    Layout.fillWidth: true
                    visible: !!root.service && root.service.categoryError !== ""
                    text: root.service ? root.service.categoryError : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }
                Text {
                    text: "Notes"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }
                Controls.TextArea {
                    id: notesField
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.space(90)
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    activeFocusOnTab: true
                    selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                    selectedTextColor: root.foreground
                    Accessible.name: "Notes"
                    background: BorderSurface {
                        color: Style.controlFill(notesField.activeFocus, notesField.hovered, root.foreground, Color.accent)
                        borderSpec: Border.controlSpec(notesField.activeFocus ? "focus" : "normal", root.foreground, Color.accent)
                        radius: Style.cornerRadius
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: !!root.service && root.service.error !== ""
                    text: root.service ? root.service.error : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Color.urgent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Style.space(6)
                    spacing: Style.space(8)
                    Button {
                        text: "Delete"
                        focusable: true
                        foreground: root.foreground
                        enabled: !!root.service && !root.service.busy
                        onClicked: {
                            root.finishing = true
                            if (!root.service.invoke("delete")) root.finishing = false
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Button {
                        text: "Save"
                        focusable: true
                        selected: true
                        bordered: true
                        foreground: root.foreground
                        enabled: !!root.service && !root.service.busy
                        onClicked: {
                            root.finishing = true
                            if (!root.service.invoke("save", root.draft())) root.finishing = false
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: root.finishing ? "Saving changes…" : "Dismiss this menu to continue tracking."
                    wrapMode: Text.WordWrap
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }
            }
        }
    }
}
