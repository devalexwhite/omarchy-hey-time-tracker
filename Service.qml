import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property var shell: null
    property var settings: ({})
    property var state: ({ mode: "idle" })
    property bool loaded: false
    property string error: ""
    property string categoryError: ""
    property var categories: []
    property double nowMs: Date.now()
    property string request: ""
    property var pendingResume: null
    readonly property bool busy: operation.running
    readonly property string backend: Qt.resolvedUrl("tracker.py").toString().replace(/^file:\/\//, "")
    readonly property bool running: state.mode === "running"
    readonly property bool reviewing: state.mode === "review"
    readonly property string elapsed: {
        if (state.mode === "idle" || !state.start) return "00:00:00"
        var end = reviewing && state.end ? Date.parse(state.end) : nowMs
        var seconds = Math.max(0, Math.floor((end - Date.parse(state.start)) / 1000))
        function pad(n) { return String(n).padStart(2, "0") }
        return pad(Math.floor(seconds / 3600)) + ":" + pad(Math.floor(seconds / 60) % 60) + ":" + pad(seconds % 60)
    }
    signal finished(string action, bool success)

    function invoke(action, draft) {
        if (busy) {
            if (action === "resume") pendingResume = draft || ({})
            return false
        }
        if (action !== "status") error = ""
        request = action
        var payload = Object.assign({}, draft || ({}))
        payload.account = settings.account || ""
        if (action !== "start" && action !== "status") {
            payload.account = state.account || settings.account || ""
            payload.remoteId = state.remoteId
        }
        operation.command = ["python3", backend, action, JSON.stringify(payload)]
        operation.running = true
        return true
    }
    function start() {
        invoke("start", { category: settings.defaultCategory || "", notes: settings.defaultNotes || "", account: settings.account || "" })
    }
    function refreshCategories() {
        if (categoryProcess.running) return
        categoryProcess.command = ["python3", backend, "categories", JSON.stringify({ account: state.account || settings.account || "" })]
        categoryProcess.running = true
    }

    Component.onCompleted: invoke("status")
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: if (!root.busy) root.invoke("status")
    }
    Process {
        id: operation
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: function(exitCode) {
            var action = root.request
            var success = false
            try {
                var result = JSON.parse(output.text)
                if (result.state) {
                    var synced = result.state
                    if (action === "status" && root.reviewing && synced.remoteId === root.state.remoteId
                            && synced.account === root.state.account) {
                        synced.mode = "review"
                        synced.end = root.state.end
                    }
                    root.state = synced
                }
                success = result.ok === true && exitCode === 0
                if (!success) root.error = result.error || "HEY could not complete this action."
                root.loaded = success
            } catch (e) {
                root.error = "The timer could not sync with HEY. " + errors.text.slice(0, 300)
            }
            if (success) root.error = ""
            root.finished(action, success)
            if (root.pendingResume !== null) {
                var draft = root.pendingResume
                root.pendingResume = null
                Qt.callLater(function() { root.invoke("resume", draft) })
            }
        }
    }
    Process {
        id: categoryProcess
        stdout: StdioCollector { id: categoryOutput }
        onExited: function(exitCode) {
            try {
                var result = JSON.parse(categoryOutput.text)
                root.categories = result.categories || []
                root.categoryError = result.ok ? "" : result.error
            } catch (e) { root.categoryError = "Could not load HEY categories. You can still enter a category title." }
        }
    }
}
