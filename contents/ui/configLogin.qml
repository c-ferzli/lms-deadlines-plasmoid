import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.plasma5support 2.0 as Plasma5Support

Kirigami.FormLayout {
    id: root
    wideMode: true

    // Bound to main.xml entries automatically
    property string cfg_baseUrl: "https://lms.aub.edu.lb"
    property string cfg_storagePath: "~/.local/share/lmsdeadlines/storage_state.json"

    property string statusText: ""

    function localPath(urlObj) {
        var s = urlObj.toString();
        return decodeURIComponent(s.replace(/^file:\/\//, ""));
    }

    property string bootstrap: localPath(Qt.resolvedUrl("../scripts/bootstrap.sh"))
    property string refreshScript: localPath(Qt.resolvedUrl("../scripts/refresh_login.py"))

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim();
            var stderr = (data["stderr"] || "").trim();
            var code = data["exit code"];

            if (code !== 0 || stderr.length) {
                root.statusText = "Login failed. " + (stderr.length ? stderr : ("Exit code: " + code));
            } else if (stdout.indexOf("ALREADY_LOGGED_IN") !== -1) {
                root.statusText = "Already logged in.";
            } else if (stdout.indexOf("LOGGED_IN_SAVED") !== -1) {
                root.statusText = "Logged in and saved.";
            } else {
                root.statusText = stdout.length ? stdout : "Done.";
            }

            disconnectSource(sourceName);
        }

        function run(cmd) {
            root.statusText = "Opening login (if needed)…";
            connectSource(cmd);
        }
    }

    QQC2.TextField {
        Kirigami.FormData.label: "Base URL:"
        text: root.cfg_baseUrl
        onTextChanged: root.cfg_baseUrl = text
    }

    QQC2.TextField {
        Kirigami.FormData.label: "Cookie file:"
        text: root.cfg_storagePath
        onTextChanged: root.cfg_storagePath = text
    }

    RowLayout {
        Kirigami.FormData.label: "Action:"
        Layout.fillWidth: true

        QQC2.Button {
            text: "Login only"
            onClicked: exec.run("bash -lc '" +
                "\"" + root.bootstrap + "\" \"" + root.refreshScript + "\" " +
                "--base-url \"" + root.cfg_baseUrl + "\" " +
                "--storage \"" + root.cfg_storagePath + "\"" +
                "'")
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: root.statusText
            wrapMode: Text.WordWrap
        }
    }
}
