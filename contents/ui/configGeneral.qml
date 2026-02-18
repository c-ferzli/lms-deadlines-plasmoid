import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.kirigami 2.20 as Kirigami

Kirigami.FormLayout {
    id: root

    // Auto-bound to main.xml entries
    property int cfg_refreshMinutes: 5
    property bool cfg_enableNotifications: true
    property int cfg_soonHours: 24
    property int cfg_urgentHours: 6
    property int cfg_notifyCooldownMinutes: 180

    QQC2.ComboBox {
        Kirigami.FormData.label: "Refresh interval:"
        model: [
            { text: "1 minute", value: 1 },
            { text: "2 minutes", value: 2 },
            { text: "5 minutes", value: 5 },
            { text: "10 minutes", value: 10 },
            { text: "15 minutes", value: 15 },
            { text: "30 minutes", value: 30 },
            { text: "60 minutes", value: 60 }
        ]
        textRole: "text"

        function indexForValue(v) {
            for (var i = 0; i < model.length; i++) if (model[i].value === v) return i;
            return 2;
        }

        Component.onCompleted: currentIndex = indexForValue(root.cfg_refreshMinutes)
        onActivated: root.cfg_refreshMinutes = model[currentIndex].value
    }

    QQC2.CheckBox {
        Kirigami.FormData.label: "Notifications:"
        text: "Enable deadline notifications"
        checked: root.cfg_enableNotifications
        onToggled: root.cfg_enableNotifications = checked
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Soon threshold (hours):"
        from: 1
        to: 168
        value: root.cfg_soonHours
        enabled: root.cfg_enableNotifications
        onValueModified: root.cfg_soonHours = value
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Urgent threshold (hours):"
        from: 1
        to: 72
        value: root.cfg_urgentHours
        enabled: root.cfg_enableNotifications
        onValueModified: root.cfg_urgentHours = value
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Notification cooldown (minutes):"
        from: 0
        to: 1440
        value: root.cfg_notifyCooldownMinutes
        enabled: root.cfg_enableNotifications
        onValueModified: root.cfg_notifyCooldownMinutes = value
    }

    Kirigami.InlineMessage {
        visible: root.cfg_enableNotifications && (root.cfg_urgentHours >= root.cfg_soonHours)
        type: Kirigami.MessageType.Warning
        text: "Urgent threshold should be smaller than Soon threshold."
    }
}
