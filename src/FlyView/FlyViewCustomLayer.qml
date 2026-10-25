import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import QGroundControl.FactControls

Item {
    id: _root
    anchors.fill: parent
    z: 999

    // Required upstream QGC FlyView properties
    property var occluders
    property var customOccluders: []
    property var mapControl
    property var parentToolInsets
    property var totalToolInsets: parentToolInsets

    // Active Vehicle & Telemetry References
    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property var _videoManager: QGroundControl.videoManager

    // Camera & View State: 0 = Side-by-Side (SBS), 1 = RGB Optical Only, 2 = Thermal IR Only
    property int cameraViewMode: 0
    property int currentZoomLevel: 1
    property int thermalPaletteIndex: 0
    property int gimbalModeIndex: 0 // 0 = Follow, 1 = FPV, 2 = Lock
    property bool isRecording: false
    property int recordSeconds: 0
    property bool settingsDrawerOpen: false
    property bool isAdminUnlocked: false

    // SIYI ZT6 Dual RTSP Endpoints
    property string rgbRtspUrl: "rtsp://192.168.144.25:8554/main.264"
    property string irRtspUrl: "rtsp://192.168.144.25:8554/secondary.264"

    // Recording Timer
    Timer {
        id: recTimer
        interval: 1000
        repeat: true
        running: _root.isRecording
        onTriggered: _root.recordSeconds++
    }

    function formatRecTime(secs) {
        var m = Math.floor(secs / 60);
        var s = secs % 60;
        return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
    }

    // MAVLink Command Helper for SIYI ZT6 & Autopilot
    function sendVehicleMavCmd(cmdId, p1, p2, p3, p4, p5, p6, p7) {
        if (_activeVehicle) {
            _activeVehicle.sendMavCommand(
                _activeVehicle.defaultComponentId,
                cmdId,
                true,
                p1 || 0, p2 || 0, p3 || 0, p4 || 0, p5 || 0, p6 || 0, p7 || 0
            );
        }
    }

    // Dual Simultaneous Recording Trigger (Drone SD + Skydroid G12 Local MP4)
    function toggleDualRecording() {
        _root.isRecording = !_root.isRecording;
        if (_root.isRecording) {
            _root.recordSeconds = 0;
            // 1. Trigger SIYI ZT6 Onboard SD Card Recording (MAV_CMD_VIDEO_START_CAPTURE = 2500)
            sendVehicleMavCmd(2500, 0, 0, 0, 0, 0, 0, 0);
            // 2. Trigger Local Skydroid G12 Recording
            if (_videoManager) {
                _videoManager.startRecording();
            }
        } else {
            // 1. Stop SIYI ZT6 Onboard SD Card Recording (MAV_CMD_VIDEO_STOP_CAPTURE = 2501)
            sendVehicleMavCmd(2501, 0, 0, 0, 0, 0, 0, 0);
            // 2. Stop Local Skydroid G12 Recording
            if (_videoManager) {
                _videoManager.stopRecording();
            }
        }
    }

    // =========================================================================
    // 1. DUAL CAMERA CANVAS (SIDE-BY-SIDE / RGB / THERMAL IR)
    // =========================================================================
    Rectangle {
        id: videoCanvas
        anchors.fill: parent
        color: "#0A0D12"
        z: 1

        RowLayout {
            anchors.fill: parent
            spacing: 3

            // LEFT PANE: SIYI ZT6 Optical (WIDE / ZOOM RGB)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: _root.cameraViewMode === 0 || _root.cameraViewMode === 1
                color: "#11161F"
                clip: true

                MediaPlayer {
                    id: rgbPlayer
                    source: _root.rgbRtspUrl
                    videoOutput: rgbVideoOutput
                    Component.onCompleted: play()
                }

                VideoOutput {
                    id: rgbVideoOutput
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }

                // Crosshair Reticle
                Text {
                    anchors.centerIn: parent
                    text: "✛"
                    color: "#88FFFFFF"
                    font.pixelSize: 22
                }

                // DJI Pilot 2 Lens Badge
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 12
                    anchors.topMargin: 56
                    width: 96; height: 26
                    radius: 4
                    color: "#B3000000"
                    border.color: "#00E5FF"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "RGB  " + _root.currentZoomLevel + "x"
                        color: "#00E5FF"
                        font.bold: true
                        font.pixelSize: 12
                    }
                }
            }

            // RIGHT PANE: SIYI ZT6 Thermal (IR)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: _root.cameraViewMode === 0 || _root.cameraViewMode === 2
                color: "#161219"
                clip: true

                MediaPlayer {
                    id: irPlayer
                    source: _root.irRtspUrl
                    videoOutput: irVideoOutput
                    Component.onCompleted: play()
                }

                VideoOutput {
                    id: irVideoOutput
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }

                // Spot Thermometry Center Reticle
                Rectangle {
                    anchors.centerIn: parent
                    width: 28; height: 28
                    color: "transparent"
                    border.color: "#FF9100"
                    border.width: 1.5
                    radius: 14

                    Rectangle {
                        anchors.centerIn: parent
                        width: 4; height: 4
                        radius: 2
                        color: "#FF3D00"
                    }
                }

                // DJI Pilot 2 Thermal Badge
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 12
                    anchors.topMargin: 56
                    width: 124; height: 26
                    radius: 4
                    color: "#B3000000"
                    border.color: "#FF9100"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: {
                            var palettes = ["WHITE HOT", "BLACK HOT", "IRONBOW", "HOT METAL"];
                            return "IR • " + palettes[_root.thermalPaletteIndex];
                        }
                        color: "#FF9100"
                        font.bold: true
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    // =========================================================================
    // 2. DJI PILOT 2 TOP STATUS BAR (MATRICE 4T STYLE)
    // =========================================================================
    Rectangle {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 46
        color: "#D910141D"
        z: 10

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 16

            // Aircraft Armed / Flight Mode Badge
            Rectangle {
                Layout.preferredWidth: 110
                Layout.preferredHeight: 30
                radius: 4
                color: _activeVehicle && _activeVehicle.armed ? "#D32F2F" : "#263238"
                border.color: "#455A64"

                Text {
                    anchors.centerIn: parent
                    text: _activeVehicle ? _activeVehicle.flightMode : "DISCONNECTED"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 12
                }
            }

            // Camera View Mode Switcher (SBS | WIDE/RGB | IR)
            Row {
                spacing: 4

                Repeater {
                    model: [
                        { label: "SBS (SPLIT)", mode: 0 },
                        { label: "WIDE / RGB", mode: 1 },
                        { label: "THERMAL IR", mode: 2 }
                    ]

                    Rectangle {
                        width: 92; height: 30
                        radius: 4
                        color: _root.cameraViewMode === modelData.mode ? "#00B0FF" : "#263238"

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: _root.cameraViewMode === modelData.mode ? "#000000" : "#ECEFF1"
                            font.bold: true
                            font.pixelSize: 11
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: _root.cameraViewMode = modelData.mode
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Recording Active Pill
            Rectangle {
                visible: _root.isRecording
                Layout.preferredWidth: 96
                Layout.preferredHeight: 28
                radius: 14
                color: "#44FF1744"
                border.color: "#FF1744"

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        width: 10; height: 10; radius: 5; color: "#FF1744"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: _root.formatRecTime(_root.recordSeconds)
                        color: "white"
                        font.bold: true
                        font.pixelSize: 12
                    }
                }
            }

            // GPS / RTK Satellite Count
            Text {
                text: "🛰️ GPS: " + (_activeVehicle ? _activeVehicle.gps.count.valueString : "0")
                color: "#B0BEC5"
                font.bold: true
                font.pixelSize: 12
            }

            // Battery Status
            Text {
                text: "🔋 " + (_activeVehicle && _activeVehicle.batteries.count > 0 ?
                      _activeVehicle.batteries.get(0).percentRemaining.valueString + "%" : "--%")
                color: "#00E676"
                font.bold: true
                font.pixelSize: 13
            }

            // DJI Pilot 2 "•••" Settings Button
            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 32
                radius: 4
                color: _root.settingsDrawerOpen ? "#00B0FF" : "#263238"

                Text {
                    anchors.centerIn: parent
                    text: "•••"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 16
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: _root.settingsDrawerOpen = !_root.settingsDrawerOpen
                }
            }
        }
    }

    // =========================================================================
    // 3. RIGHT-SIDE CAMERA & GIMBAL CONTROL DOCK (DJI MATRICE 4T LAYOUT)
    // =========================================================================
    Rectangle {
        id: rightCameraDock
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 68
        height: 410
        radius: 10
        color: "#BF10141D"
        border.color: "#37474F"
        z: 10

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10

            // Optical / Synchronized Zoom Button (1x -> 2x -> 5x -> 10x)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 6
                color: "#263238"
                border.color: "#00E5FF"

                Column {
                    anchors.centerIn: parent
                    Text {
                        text: _root.currentZoomLevel + ".0x"
                        color: "#00E5FF"
                        font.bold: true
                        font.pixelSize: 13
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: "ZOOM"
                        color: "#90A4AE"
                        font.pixelSize: 9
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        var levels = [1, 2, 5, 10];
                        var idx = (levels.indexOf(_root.currentZoomLevel) + 1) % levels.length;
                        _root.currentZoomLevel = levels[idx];
                        // MAV_CMD_SET_CAMERA_ZOOM = 531 (Zoom Type 1 = Level)
                        _root.sendVehicleMavCmd(531, 1, _root.currentZoomLevel, 0, 0, 0, 0, 0);
                    }
                }
            }

            // Still Photo Shutter Button
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 48; height: 48
                radius: 24
                color: "#263238"
                border.color: "white"
                border.width: 2

                Text {
                    anchors.centerIn: parent
                    text: "📷"
                    font.pixelSize: 20
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        // MAV_CMD_IMAGE_START_CAPTURE = 2000, fallback MAV_CMD_DO_DIGICAM_CONTROL = 203
                        _root.sendVehicleMavCmd(2000, 0, 0, 1, 0, 0, 0, 0);
                        _root.sendVehicleMavCmd(203, 0, 0, 0, 0, 1, 0, 0);
                    }
                }
            }

            // Dual Record Button (Drone SD + Skydroid Local Storage)
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 54; height: 54
                radius: 27
                color: "#263238"
                border.color: _root.isRecording ? "#FF1744" : "white"
                border.width: 3

                Rectangle {
                    anchors.centerIn: parent
                    width: _root.isRecording ? 20 : 32
                    height: _root.isRecording ? 20 : 32
                    radius: _root.isRecording ? 4 : 16
                    color: "#FF1744"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: _root.toggleDualRecording()
                }
            }

            // Thermal LUT Palette Button
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: 6
                color: "#263238"
                border.color: "#FF9100"

                Text {
                    anchors.centerIn: parent
                    text: "IR LUT"
                    color: "#FF9100"
                    font.bold: true
                    font.pixelSize: 11
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        _root.thermalPaletteIndex = (_root.thermalPaletteIndex + 1) % 4;
                    }
                }
            }

            // Gimbal Recenter (0° Pitch/Yaw)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: 6
                color: "#263238"

                Text {
                    anchors.centerIn: parent
                    text: "⌖ 0°"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 12
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        // MAV_CMD_DO_GIMBAL_MANAGER_PITCHYAW = 1000 (Pitch: 0, Yaw: 0)
                        _root.sendVehicleMavCmd(1000, 0, 0, 0, 0, 0, 0, 0);
                    }
                }
            }

            // Gimbal Look Straight Down (-90° Nadir)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: 6
                color: "#263238"

                Text {
                    anchors.centerIn: parent
                    text: "↓ -90°"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 12
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        // MAV_CMD_DO_GIMBAL_MANAGER_PITCHYAW = 1000 (Pitch: -90, Yaw: 0)
                        _root.sendVehicleMavCmd(1000, -90, 0, 0, 0, 0, 0, 0);
                    }
                }
            }

            // SIYI ZT6 Gimbal Mode Switch (Follow / FPV / Lock)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 6
                color: "#1C262B"

                Text {
                    anchors.centerIn: parent
                    text: {
                        var modes = ["FOLLOW", "FPV", "LOCK"];
                        return modes[_root.gimbalModeIndex];
                    }
                    color: "#80D8FF"
                    font.bold: true
                    font.pixelSize: 10
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        _root.gimbalModeIndex = (_root.gimbalModeIndex + 1) % 3;
                    }
                }
            }
        }
    }

    // =========================================================================
    // 4. BOTTOM-LEFT DJI PILOT 2 FLIGHT TELEMETRY & RTH BAR
    // =========================================================================
    Rectangle {
        id: bottomTelemetryCard
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 14
        width: 440
        height: 68
        radius: 8
        color: "#CC10141D"
        border.color: "#37474F"
        z: 10

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 20

            // Altitude (H)
            Column {
                Text { text: "H (ALT)"; color: "#90A4AE"; font.pixelSize: 10; font.bold: true }
                Text {
                    text: (_activeVehicle ? _activeVehicle.altitudeRelative.valueString : "0.0") + " m"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 18
                }
            }

            // Distance to Home (D)
            Column {
                Text { text: "D (HOME)"; color: "#90A4AE"; font.pixelSize: 10; font.bold: true }
                Text {
                    text: (_activeVehicle ? _activeVehicle.distanceToHome.valueString : "0.0") + " m"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 18
                }
            }

            // Horizontal Speed (HS)
            Column {
                Text { text: "HS (SPD)"; color: "#90A4AE"; font.pixelSize: 10; font.bold: true }
                Text {
                    text: (_activeVehicle ? _activeVehicle.groundSpeed.valueString : "0.0") + " m/s"
                    color: "#00E5FF"
                    font.bold: true
                    font.pixelSize: 18
                }
            }

            // Vertical Speed (VS)
            Column {
                Text { text: "VS (CLIMB)"; color: "#90A4AE"; font.pixelSize: 10; font.bold: true }
                Text {
                    text: (_activeVehicle ? _activeVehicle.climbRate.valueString : "0.0") + " m/s"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 18
                }
            }

            Item { Layout.fillWidth: true }

            // One-Tap DJI Style RTH Button
            Rectangle {
                Layout.preferredWidth: 74
                Layout.preferredHeight: 44
                radius: 6
                color: "#E65100"
                border.color: "#FFB74D"

                Text {
                    anchors.centerIn: parent
                    text: "🏠 RTH"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 13
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (_activeVehicle) {
                            _activeVehicle.guidedModeRTL(false);
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 5. DJI PILOT 2 SETTINGS DRAWER (ONLY COMPASS, RTL HEIGHT, GEOFENCE + ADMIN)
    // =========================================================================
    Rectangle {
        id: djiSettingsDrawer
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 390
        visible: _root.settingsDrawerOpen
        color: "#F2121722"
        border.color: "#263238"
        z: 50

        Flickable {
            anchors.fill: parent
            anchors.margins: 18
            contentHeight: settingsCol.height
            clip: true

            ColumnLayout {
                id: settingsCol
                width: parent.width
                spacing: 18

                Text {
                    text: "Aircraft & Payload Settings"
                    color: "#00E5FF"
                    font.bold: true
                    font.pixelSize: 18
                }

                // -------------------------------------------------------------
                // ALLOWED SETTING 1: COMPASS CALIBRATION
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    height: 92
                    radius: 6
                    color: "#1B2230"
                    border.color: "#2D3A4F"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12

                        Column {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: "1. Compass Calibration"; color: "white"; font.bold: true; font.pixelSize: 14 }
                            Text { text: "Calibrate onboard magnetometer"; color: "#90A4AE"; font.pixelSize: 11 }
                        }

                        Button {
                            text: "Calibrate"
                            onClicked: {
                                // MAV_CMD_DO_START_MAG_CAL = 42424
                                _root.sendVehicleMavCmd(42424, 0, 1, 1, 0, 0, 0, 0);
                            }
                        }
                    }
                }

                // -------------------------------------------------------------
                // ALLOWED SETTING 2: RETURN-TO-HOME (RTL) ALTITUDE
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    height: 110
                    radius: 6
                    color: "#1B2230"
                    border.color: "#2D3A4F"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "2. Return-to-Home (RTL) Altitude"; color: "white"; font.bold: true; font.pixelSize: 14 }
                            Item { Layout.fillWidth: true }
                            Text { id: rtlValLabel; text: Math.round(rtlSlider.value) + " m"; color: "#00E5FF"; font.bold: true; font.pixelSize: 14 }
                        }

                        Slider {
                            id: rtlSlider
                            Layout.fillWidth: true
                            from: 15
                            to: 120
                            stepSize: 5
                            value: 50
                            onMoved: {
                                if (_activeVehicle && _activeVehicle.parameterManager) {
                                    // ArduPilot RTL_ALT is in cm; PX4 RTL_RETURN_ALT is in meters
                                    if (_activeVehicle.parameterManager.parameterExists(-1, "RTL_ALT")) {
                                        _activeVehicle.parameterManager.getParameter(-1, "RTL_ALT").rawValue = value * 100;
                                    } else if (_activeVehicle.parameterManager.parameterExists(-1, "RTL_RETURN_ALT")) {
                                        _activeVehicle.parameterManager.getParameter(-1, "RTL_RETURN_ALT").rawValue = value;
                                    }
                                }
                            }
                        }
                    }
                }

                // -------------------------------------------------------------
                // ALLOWED SETTING 3: GEOFENCE (MAX ALTITUDE & RADIUS)
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    height: 165
                    radius: 6
                    color: "#1B2230"
                    border.color: "#2D3A4F"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "3. Geofence Protection"; color: "white"; font.bold: true; font.pixelSize: 14 }
                            Item { Layout.fillWidth: true }
                            Switch {
                                id: fenceSwitch
                                checked: true
                                onToggled: {
                                    if (_activeVehicle && _activeVehicle.parameterManager) {
                                        if (_activeVehicle.parameterManager.parameterExists(-1, "FENCE_ENABLE")) {
                                            _activeVehicle.parameterManager.getParameter(-1, "FENCE_ENABLE").rawValue = checked ? 1 : 0;
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Max Altitude: " + Math.round(fenceAltSlider.value) + " m"; color: "#B0BEC5"; font.pixelSize: 12 }
                            Slider {
                                id: fenceAltSlider
                                Layout.fillWidth: true
                                from: 20; to: 500; stepSize: 10; value: 120
                                onMoved: {
                                    if (_activeVehicle && _activeVehicle.parameterManager &&
                                        _activeVehicle.parameterManager.parameterExists(-1, "FENCE_ALT_MAX")) {
                                        _activeVehicle.parameterManager.getParameter(-1, "FENCE_ALT_MAX").rawValue = value;
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Max Radius: " + Math.round(fenceRadSlider.value) + " m"; color: "#B0BEC5"; font.pixelSize: 12 }
                            Slider {
                                id: fenceRadSlider
                                Layout.fillWidth: true
                                from: 50; to: 2000; stepSize: 50; value: 500
                                onMoved: {
                                    if (_activeVehicle && _activeVehicle.parameterManager &&
                                        _activeVehicle.parameterManager.parameterExists(-1, "FENCE_RADIUS")) {
                                        _activeVehicle.parameterManager.getParameter(-1, "FENCE_RADIUS").rawValue = value;
                                    }
                                }
                            }
                        }
                    }
                }

                // -------------------------------------------------------------
                // SIYI ZT6 RTSP STREAM URL CONFIGURATION
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    height: 140
                    radius: 6
                    color: "#1B2230"
                    border.color: "#2D3A4F"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6

                        Text { text: "SIYI ZT6 RTSP Streams"; color: "white"; font.bold: true; font.pixelSize: 13 }

                        TextField {
                            Layout.fillWidth: true
                            text: _root.rgbRtspUrl
                            placeholderText: "RGB RTSP URL"
                            onEditingFinished: { _root.rgbRtspUrl = text; rgbPlayer.stop(); rgbPlayer.play(); }
                        }

                        TextField {
                            Layout.fillWidth: true
                            text: _root.irRtspUrl
                            placeholderText: "Thermal IR RTSP URL"
                            onEditingFinished: { _root.irRtspUrl = text; irPlayer.stop(); irPlayer.play(); }
                        }
                    }
                }

                // -------------------------------------------------------------
                // PASSWORD-PROTECTED ADMIN UNLOCK (FULL PARAMETERS)
                // -------------------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    height: 130
                    radius: 6
                    color: "#1B2230"
                    border.color: _root.isAdminUnlocked ? "#00E676" : "#FF5252"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        Text {
                            text: _root.isAdminUnlocked ? "🔓 Admin Mode Unlocked" : "🔒 Full Parameters Locked"
                            color: _root.isAdminUnlocked ? "#00E676" : "#FF5252"
                            font.bold: true
                            font.pixelSize: 14
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: !_root.isAdminUnlocked

                            TextField {
                                id: adminPassInput
                                Layout.fillWidth: true
                                echoMode: TextInput.Password
                                placeholderText: "Enter Admin Password"
                            }

                            Button {
                                text: "Unlock"
                                onClicked: {
                                    if (adminPassInput.text === "admin123") {
                                        _root.isAdminUnlocked = true;
                                        adminPassInput.text = "";
                                    } else {
                                        adminPassInput.text = "";
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: _root.isAdminUnlocked

                            Button {
                                text: "Open Full QGC Setup"
                                onClicked: mainWindow.showToolSelectDialog()
                            }

                            Button {
                                text: "Lock"
                                onClicked: _root.isAdminUnlocked = false
                            }
                        }
                    }
                }
            }
        }
    }
}