import org.kde.plasma.configuration 2.0

ConfigModel {
    ConfigCategory {
        name: "General"
        icon: "settings-configure"
        source: "configGeneral.qml"
    }

    ConfigCategory {
        name: "Login"
        icon: "dialog-password"
        source: "configLogin.qml"
    }
}
