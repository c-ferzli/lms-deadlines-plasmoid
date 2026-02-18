import QtQuick 2.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PC3
import org.kde.plasma.plasma5support 2.0 as Plasma5Support
import org.kde.kirigami 2.20 as Kirigami

PlasmoidItem {
    id: root
    preferredRepresentation: compactRepresentation

    // Config
    property int refreshMinutes: (plasmoid.configuration.refreshMinutes > 0) ? plasmoid.configuration.refreshMinutes : 5
    property int refreshMs: refreshMinutes * 60000

    property bool enableNotifications: plasmoid.configuration.enableNotifications
    property int soonHours: (plasmoid.configuration.soonHours > 0) ? plasmoid.configuration.soonHours : 24
    property int urgentHours: (plasmoid.configuration.urgentHours > 0) ? plasmoid.configuration.urgentHours : 6
    property int cooldownMinutes: (plasmoid.configuration.notifyCooldownMinutes >= 0) ? plasmoid.configuration.notifyCooldownMinutes : 180

    // NEW config
    property string baseUrl: plasmoid.configuration.baseUrl || "https://lms.aub.edu.lb"
    property string storagePath: plasmoid.configuration.storagePath || "~/.local/share/lmsdeadlines/storage_state.json"

    property bool hasError: false
    property string errText: ""
    property var items: []

    property var notifyState: ({})

    toolTipMainText: hasError ? "LMS Deadlines (Error)" : ("LMS Deadlines (" + items.length + ")")
    toolTipSubText: hasError ? errText : (items.length ? (items[0].course + " — " + items[0].title) : "No deadlines")

    function decodeHtml(s) {
        if (!s) return "";
        return s
            .replace(/&amp;/g, "&")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"")
            .replace(/&#39;/g, "'")
            .replace(/&nbsp;/g, " ");
    }

    function parseOutput(txt) {
        var out = [];
        var lines = (txt || "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (!line) continue;
            if (line === "No upcoming deadlines") continue;

            // course | title | YYYY-MM-DD HH:MM | 3d 4h
            var parts = line.split(" | ");
            if (parts.length < 4) continue;

            out.push({
                course: decodeHtml(parts[0]),
                title: decodeHtml(parts[1]),
                due: parts[2],
                remain: parts.slice(3).join(" | ")
            });
        }
        return out;
    }

    function remainToMinutes(rem) {
        if (!rem) return 999999;
        if (rem.indexOf("OVERDUE") !== -1) return -1;
        var d = 0, h = 0, m = 0;
        var md = rem.match(/(\d+)\s*d/);
        var mh = rem.match(/(\d+)\s*h/);
        var mm = rem.match(/(\d+)\s*m/);
        if (md) d = parseInt(md[1]);
        if (mh) h = parseInt(mh[1]);
        if (mm) m = parseInt(mm[1]);
        return d * 1440 + h * 60 + m;
    }

    function hash01(s) {
        var x = 0;
        for (var i = 0; i < s.length; i++) x = (x * 31 + s.charCodeAt(i)) >>> 0;
        return (x % 10000) / 10000.0;
    }

    function hsvToRgb(h, s, v) {
        var i = Math.floor(h * 6);
        var f = h * 6 - i;
        var p = v * (1 - s);
        var q = v * (1 - f * s);
        var t = v * (1 - (1 - f) * s);
        var r, g, b;
        switch (i % 6) {
            case 0: r = v; g = t; b = p; break;
            case 1: r = q; g = v; b = p; break;
            case 2: r = p; g = v; b = t; break;
            case 3: r = p; g = q; b = v; break;
            case 4: r = t; g = p; b = v; break;
            case 5: r = v; g = p; b = q; break;
        }
        return Qt.rgba(r, g, b, 1);
    }

    function accentColor(course, title) {
        var h = hash01(course + "|" + title);
        return hsvToRgb(h, 0.55, 0.95);
    }

    function dueColor(remain) {
        var mins = remainToMinutes(remain);
        if (mins < 0) return Kirigami.Theme.negativeTextColor;
        if (mins <= urgentHours * 60) return Kirigami.Theme.negativeTextColor;
        if (mins <= soonHours * 60) return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.positiveTextColor;
    }

    function cardTint(remain) {
        var mins = remainToMinutes(remain);
        if (mins < 0) return Qt.rgba(1, 0, 0, 0.08);
        if (mins <= urgentHours * 60) return Qt.rgba(1, 0, 0, 0.07);
        if (mins <= soonHours * 60) return Qt.rgba(1, 1, 0, 0.06);
        return Qt.rgba(0, 1, 0, 0.05);
    }

    function shEscape(s) {
        return String(s).replace(/'/g, "'\\''");
    }

    function localPath(urlObj) {
        var s = urlObj.toString();
        return decodeURIComponent(s.replace(/^file:\/\//, ""));
    }

    function runnerFile() {
        return localPath(Qt.resolvedUrl("../scripts/run_deadlines.sh"));
    }

    function sendNotify(urgency, title, body) {
        var cmd = "notify-send -u " + shEscape(urgency) + " '" + shEscape(title) + "' '" + shEscape(body) + "'";
        notifier.connectSource("bash -lc '" + cmd + "'");
    }

    function maybeNotify(listItems) {
        if (!enableNotifications) return;
        if (!listItems || listItems.length === 0) return;
        if (urgentHours >= soonHours) return;

        var now = Date.now();
        var cooldownMs = cooldownMinutes * 60000;

        for (var i = 0; i < listItems.length; i++) {
            var it = listItems[i];
            var mins = remainToMinutes(it.remain);
            if (mins <= 0) continue;

            var keyBase = it.course + "|" + it.title + "|" + it.due;

            if (mins <= urgentHours * 60) {
                var kU = "U|" + keyBase;
                var lastU = notifyState[kU] || 0;
                if (cooldownMs === 0 || (now - lastU) > cooldownMs) {
                    notifyState[kU] = now;
                    sendNotify("critical", "🚨 Urgent deadline", it.course + "\n" + it.title + "\nDue: " + it.due + " (" + it.remain + ")");
                }
                continue;
            }

            if (mins <= soonHours * 60) {
                var kS = "S|" + keyBase;
                var lastS = notifyState[kS] || 0;
                if (cooldownMs === 0 || (now - lastS) > cooldownMs) {
                    notifyState[kS] = now;
                    sendNotify("normal", "⏰ Deadline soon", it.course + "\n" + it.title + "\nDue: " + it.due + " (" + it.remain + ")");
                }
            }
        }
    }

    Plasma5Support.DataSource {
        id: exe
        engine: "executable"
        interval: Math.max(1000, root.refreshMs)
        connectedSources: [ command() ]

        function command() {
            var runner = root.runnerFile();
            var cmd =
                "'" + root.shEscape(runner) + "'" +
                " --plain" +
                " --base-url '" + root.shEscape(root.baseUrl) + "'" +
                " --storage '" + root.shEscape(root.storagePath) + "'";
            return "bash -lc '" + cmd + "'";
        }

        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim();
            var stderr = (data["stderr"] || "").trim();
            var code = data["exit code"];

            if (stderr.length > 0 || code !== 0) {
                root.hasError = true;
                root.errText = stderr.length ? stderr : ("Exit code: " + code);
                root.items = [];
            } else {
                root.hasError = false;
                root.errText = "";
                root.items = root.parseOutput(stdout);
                root.maybeNotify(root.items);
            }
        }
    }

    Plasma5Support.DataSource {
        id: notifier
        engine: "executable"
        onNewData: function(sourceName, data) { notifier.disconnectSource(sourceName); }
    }

    compactRepresentation: Item {
        implicitWidth: 34
        implicitHeight: 34
        MouseArea { anchors.fill: parent; onClicked: root.expanded = !root.expanded }

        Image {
            anchors.centerIn: parent
            width: 22; height: 22
            source: root.hasError ? "" : Qt.resolvedUrl("../images/lms.svg")
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: !root.hasError
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 22; height: 22
            source: "dialog-error"
            visible: root.hasError
        }

        Rectangle {
            visible: !root.hasError && root.items.length > 0
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 1
            anchors.topMargin: 1
            radius: 8
            implicitHeight: 16
            implicitWidth: Math.max(16, badgeText.implicitWidth + 8)
            color: Kirigami.Theme.highlightColor

            PC3.Label {
                id: badgeText
                anchors.centerIn: parent
                text: String(root.items.length)
                color: Kirigami.Theme.highlightedTextColor
                font.pixelSize: 10
            }
        }
    }

    fullRepresentation: Item {
        implicitWidth: 520
        implicitHeight: 340

        Rectangle {
            anchors.fill: parent
            anchors.margins: 10
            radius: 12
            color: Kirigami.Theme.backgroundColor
            border.width: 1
            border.color: Kirigami.Theme.disabledTextColor

            Item {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 40

                Image {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20
                    source: root.hasError ? "" : Qt.resolvedUrl("../images/lms.svg")
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    visible: !root.hasError
                }

                Kirigami.Icon {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20
                    source: "dialog-error"
                    visible: root.hasError
                }

                PC3.Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 12 + 20 + 10
                    anchors.right: refreshLabel.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hasError ? "LMS Deadlines — Error" : ("Upcoming deadlines (" + root.items.length + ")")
                    font.bold: true
                    elide: Text.ElideRight
                    color: root.hasError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                }

                PC3.Label {
                    id: refreshLabel
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Refresh: " + root.refreshMinutes + "m"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: 11
                }
            }

            Rectangle {
                id: sep
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: header.bottom
                height: 1
                color: Kirigami.Theme.disabledTextColor
                opacity: 0.6
            }

            PC3.TextArea {
                visible: root.hasError
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: sep.bottom
                anchors.bottom: parent.bottom
                anchors.margins: 12
                readOnly: true
                wrapMode: TextEdit.Wrap
                text: root.errText
                color: Kirigami.Theme.negativeTextColor
            }

            PC3.ScrollView {
                visible: !root.hasError
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: sep.bottom
                anchors.bottom: parent.bottom
                anchors.margins: 12

                ListView {
                    id: list
                    model: root.items
                    clip: true
                    spacing: 10

                    delegate: Rectangle {
                        width: list.width
                        radius: 12
                        color: Kirigami.Theme.alternateBackgroundColor

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: root.cardTint(modelData.remain)
                        }

                        Rectangle {
                            width: 6
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            radius: 12
                            color: root.accentColor(modelData.course, modelData.title)
                            opacity: 0.95
                        }

                        implicitHeight: content.implicitHeight + 20
                        height: implicitHeight

                        Column {
                            id: content
                            width: parent.width - 6 - 24
                            anchors.left: parent.left
                            anchors.leftMargin: 6 + 12
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            spacing: 6

                            PC3.Label {
                                width: parent.width
                                text: modelData.course
                                font.bold: true
                                wrapMode: Text.WordWrap
                                color: Kirigami.Theme.textColor
                            }

                            PC3.Label {
                                width: parent.width
                                text: modelData.title
                                wrapMode: Text.WordWrap
                                color: Kirigami.Theme.textColor
                            }

                            Row {
                                width: parent.width
                                spacing: 10

                                PC3.Label {
                                    text: "Due: " + modelData.due
                                    color: Kirigami.Theme.disabledTextColor
                                    font.pixelSize: 11
                                }

                                PC3.Label {
                                    text: "•"
                                    color: Kirigami.Theme.disabledTextColor
                                    font.pixelSize: 11
                                }

                                PC3.Label {
                                    text: modelData.remain
                                    color: root.dueColor(modelData.remain)
                                    font.bold: true
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }

                    footer: Item {
                        width: list.width
                        height: root.items.length === 0 ? 60 : 0
                        visible: root.items.length === 0
                        PC3.Label {
                            anchors.centerIn: parent
                            text: "No upcoming deadlines"
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }
                }
            }
        }
    }
}
