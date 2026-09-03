// Laptop Power Center combines MIT-licensed work from Omarchy,
// Minokai69/omarchy-laptop-gpu-modes, and patcastle/omarchy-battery-health.
// See THIRD_PARTY_NOTICES.md and LICENSE for provenance and license notices.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false
  property var batteryInfo: ({})
  property var limitInfo: ({ state: "unsupported", policy: "unknown" })
  property var energyInfo: ({
    travel: "disabled",
    quick_dim: "unsupported",
    brightness: "unknown",
    nvidia_power: "unavailable"
  })
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property var gpuModes: []
  property string gpuMode: ""
  property string gpuVendor: ""
  property string gpuClientPath: ""
  property bool gpuAvailable: false
  property string gpuPendingAction: ""
  property string gpuPendingMode: ""
  property string requestedGpuMode: ""
  property bool gpuChangePending: false
  property string gpuError: ""
  property var gpuTelemetry: ({})
  property string limitError: ""
  property string energyError: ""
  property bool cursorActive: false
  property string cursorSection: "profiles"
  readonly property bool limitVisible: limitInfo.state !== "unsupported"
  readonly property string limitDescription: Model.limitDescription(limitInfo.state, limitInfo.policy)
  readonly property string limitCommand: decodeURIComponent(String(Qt.resolvedUrl("bin/omarchy-battery-limit")).replace(/^file:\/\//, ""))
  readonly property string energyCommand: decodeURIComponent(String(Qt.resolvedUrl("bin/omarchy-energy-controls")).replace(/^file:\/\//, ""))
  readonly property bool travelMode: energyInfo.travel === "enabled"
  readonly property bool energyVisible: energyInfo.quick_dim !== "unsupported"
  readonly property bool nvidiaRuntimeVisible: energyInfo.nvidia_power === "active"
    || energyInfo.nvidia_power === "suspended"
  readonly property bool gpuTelemetryVisible: gpuTelemetry.usage !== undefined
    || gpuTelemetry.power !== undefined
  readonly property bool gpuSectionVisible: gpuAvailable || nvidiaRuntimeVisible || gpuTelemetryVisible
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) {
      cursorActive = true
      return
    }

    if (limitVisible && ((cursorSection === "limit" && dy > 0) || (cursorSection === "profiles" && dy < 0))) {
      cursorSection = cursorSection === "limit" ? "profiles" : "limit"
      return
    }

    if (cursorSection === "profiles") selectProfileByDelta(dx !== 0 ? dx : dy)
  }

  function activateCursor() {
    if (!cursorActive) {
      cursorActive = true
      return
    }

    if (cursorSection === "profiles") activateSelectedProfile()
    else setLimit(limitInfo.state === "enabled" ? "disable" : "enable")
  }

  function setLimit(action) {
    if (!action || !limitCommand || limitActionProc.running) return
    limitError = ""
    limitActionProc.command = [limitCommand, action]
    limitActionProc.running = true
  }

  function setEnergy(control, enabled) {
    if (!control || !energyCommand || energyActionProc.running) return
    energyError = ""
    energyActionProc.command = ["/usr/bin/bash", energyCommand, control,
      enabled ? "enable" : "disable"]
    energyActionProc.running = true
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Color.foreground
  }

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    refreshLimit()
    refreshEnergy()
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
    if (!gpuCapabilityProc.running) gpuCapabilityProc.running = true
    refreshGpuTelemetry()
    if (gpuAvailable) {
      if (!gpuPendingActionProc.running) {
        gpuPendingActionProc.command = [gpuClientPath, "-p"]
        gpuPendingActionProc.running = true
      }
      if (!gpuPendingModeProc.running) {
        gpuPendingModeProc.command = [gpuClientPath, "-P"]
        gpuPendingModeProc.running = true
      }
    }
  }

  function refreshLimit() {
    if (batteryPresent && !limitProc.running) limitProc.running = true
  }

  function refreshEnergy() {
    if (batteryPresent && !energyProc.running) energyProc.running = true
  }

  function refreshGpuTelemetry() {
    // nvidia-smi may wake a runtime-suspended GPU on some laptops. Never poll
    // unless sysfs has already told us the discrete GPU is active.
    if (energyInfo.nvidia_power !== "active") {
      gpuTelemetry = ({})
      return
    }
    if (!gpuTelemetryProc.running) gpuTelemetryProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else if (targetName === "limit") {
      limitInfo = next
      if (!cursorActive) cursorSection = next.state !== "unsupported" ? "limit" : "profiles"
    }
    else if (targetName === "energy") {
      energyInfo = next
      refreshGpuTelemetry()
    }
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function updateGpuMode(raw) {
    var value = String(raw || "").trim()
    if (value !== "") gpuMode = value
  }

  function updateGpuCapability(raw) {
    var lines = String(raw || "").trim().split(/\r?\n/)
    var clientPath = (lines.shift() || "").trim()
    var vendor = (lines.shift() || "").trim()
    var value = (lines.shift() || "").replace(/[\[\]]/g, "")
    var current = (lines.shift() || "").trim()
    var next = value.split(",").map(function(item) { return item.trim() }).filter(function(item) { return item !== "" })
    var isNvidia = vendor.toLowerCase().indexOf("nvidia") >= 0

    gpuClientPath = clientPath
    gpuVendor = vendor
    gpuMode = current
    gpuModes = next
    gpuAvailable = isNvidia && next.length > 1
    if (gpuChangePending && requestedGpuMode !== "" && current === requestedGpuMode) {
      gpuChangePending = false
      requestedGpuMode = ""
      gpuError = ""
      gpuApplyWatchdog.stop()
    }
  }

  function updateGpuPendingAction(raw) {
    gpuPendingAction = String(raw || "").trim()
  }

  function updateGpuPendingMode(raw) {
    gpuPendingMode = String(raw || "").trim()
  }

  function updateGpuTelemetry(raw) {
    gpuTelemetry = Model.parseGpuTelemetry(raw)
  }


  function requestGpuMode(mode) {
    if (!gpuAvailable || gpuModes.indexOf(mode) < 0 || mode === gpuMode || gpuChangePending) return
    requestedGpuMode = mode
    gpuModeConfirm.opened = true
  }

  function applyGpuMode() {
    if (!gpuAvailable || !requestedGpuMode || gpuChangePending) return
    gpuChangePending = true
    gpuError = ""
    gpuModeConfirm.opened = false
    gpuConfigProc.command = [gpuClientPath, "-m", requestedGpuMode]
    gpuConfigProc.running = true
    gpuApplyWatchdog.restart()
  }

  function gpuConfigFinished(code) {
    if (code !== 0) {
      gpuChangePending = false
      gpuApplyWatchdog.stop()
      gpuError = "Unable to request this GPU mode"
      return
    }
    // supergfxctl exits successfully when the daemon accepts the request,
    // but the actual switch may wait for logout/reboot. Keep the pending
    // state until a refresh observes the requested mode or the watchdog
    // reports the daemon timeout.
    refresh()
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  IpcHandler {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
    function batteryHealthStatus(): string {
      return JSON.stringify({
        command: root.limitCommand,
        state: root.limitInfo.state || "unknown",
        policy: root.limitInfo.policy || "unknown",
        running: limitProc.running,
        error: root.limitError
      })
    }
    function energyStatus(): string {
      return JSON.stringify({ info: root.energyInfo, running: energyActionProc.running, error: root.energyError })
    }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
      cursorSection = limitVisible ? "limit" : "profiles"
    }
  }

  onBatteryPresentChanged: {
    if (!batteryPresent) close()
    else {
      refreshLimit()
      refreshEnergy()
    }
  }

  Component.onCompleted: {
    refreshLimit()
    refreshEnergy()
  }

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Timer {
    id: gpuApplyWatchdog
    interval: 35000
    repeat: false
    onTriggered: {
      if (!root.gpuChangePending) return
      root.gpuChangePending = false
      root.gpuError = "GPU service timed out; log out or reboot to apply " + root.requestedGpuMode
      root.requestedGpuMode = ""
      root.refresh()
    }
  }

  Process {
    id: limitProc
    command: root.limitCommand ? ["/usr/bin/bash", root.limitCommand, "status", "--shell"] : []
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "limit") }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = text.trim()
        if (message !== "") root.limitError = message
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.limitError === "")
        root.limitError = "Battery protection status check failed (exit " + exitCode + ")"
    }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: energyProc
    command: root.energyCommand ? ["/usr/bin/bash", root.energyCommand, "status", "--shell"] : []
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "energy") }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = text.trim()
        if (message !== "") root.energyError = message
      }
    }
  }

  Process {
    id: systemProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Process {
    id: limitActionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = text.trim()
        if (message !== "") root.limitError = message
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.limitError = ""
      else if (root.limitError === "") root.limitError = "Could not update battery protection"
      root.refresh()
    }
  }

  Process {
    id: energyActionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = text.trim()
        if (message !== "") root.energyError = message
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.energyError = ""
      else if (root.energyError === "") root.energyError = "Could not update energy controls"
      root.refresh()
    }
  }

  Process {
    id: gpuCapabilityProc
    command: ["sh", "-c", "client=$(command -v supergfxctl) || exit 1; vendor=$(\"$client\" -V 2>/dev/null) || exit 1; modes=$(\"$client\" -s 2>/dev/null) || exit 1; current=$(\"$client\" -g 2>/dev/null) || exit 1; printf '%s\\n%s\\n%s\\n%s\\n' \"$client\" \"$vendor\" \"$modes\" \"$current\""]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateGpuCapability(text) }
    onExited: function(code) {
      if (code !== 0) {
        root.gpuAvailable = false
        root.gpuClientPath = ""
        root.gpuVendor = ""
        root.gpuPendingAction = ""
        root.gpuPendingMode = ""
        root.gpuModes = []
      }
    }
  }

  Process {
    id: gpuConfigProc
    onExited: function(code) { root.gpuConfigFinished(code) }
  }

  Process {
    id: gpuPendingActionProc
    onExited: function(code) {
      if (code !== 0) root.gpuPendingAction = ""
    }
  }

  Process {
    id: gpuPendingModeProc
    onExited: function(code) {
      if (code !== 0) root.gpuPendingMode = ""
    }
  }

  Process {
    id: gpuTelemetryProc
    command: ["nvidia-smi", "--query-gpu=utilization.gpu,power.draw", "--format=csv,noheader,nounits"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateGpuTelemetry(text) }
    onExited: function(code) {
      if (code !== 0) root.gpuTelemetry = ({})
    }
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  // Rotate the status phrase while the panel is open and we're in a
  // rotating state (charging or on battery). The text swap is wrapped in a
  // fade so the changeover reads as one organism rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // If we leave a rotating state mid-swap, halt the animation and snap back
  // to full opacity so "FULLY CHARGED" is legible immediately rather than
  // appearing dimmed.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical
      ? Math.round(root.batteryFraction * 100) + "% " + root.batteryIcon()
      : root.batteryIcon()
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
      focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        root.moveCursor(dx, dy)
        if (dy !== 0)
          panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentY + dy * Style.space(56),
            Math.max(0, panelFlick.contentHeight - panelFlick.height)))
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Battery"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            text: root.batteryInfo.percentage || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        // ---------- Battery progress bar ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }

            // Subtle pulse while charging — visible signal that energy is flowing in.
            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Stats ----------
        // Visibility is intentionally only gated by "we've ever loaded data" so
        // the section never collapses mid-transition. fullyCharged is *not* part
        // of the condition: UPower briefly reports FullyCharged on plug-in when
        // the battery sits above the charge-control start threshold, and we
        // refuse to flicker the whole panel for that ~1s window.
        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Battery size"; value: root.batteryInfo.size || "" }
            InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.chargeThresholdActive ? (root.batteryInfo.threshold || "-") : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : (root.discharging ? "Discharging" : "Charging")
              value: root.chargeThresholdActive ? "Holding" : (root.batteryFull ? "-" : (root.batteryInfo.rate || ""))
            }
          }
        }

        // ---------- Battery health ----------
        Column {
          visible: root.limitVisible
          width: parent.width
          spacing: Style.space(10)

          PanelSeparator {
            foreground: root.bar.foreground
          }

          PanelSectionHeader {
            text: "BATTERY HEALTH"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Toggle {
            width: parent.width
            label: "Preserve battery health"
            description: root.limitDescription
            checked: root.limitInfo.state === "enabled"
            enabled: !limitActionProc.running
            hasCursor: root.cursorActive && root.cursorSection === "limit"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.setLimit(root.limitInfo.state === "enabled" ? "disable" : "enable")
            onHovered: function(h) {
              if (h) {
                root.cursorActive = true
                root.cursorSection = "limit"
              }
            }
          }

          Text {
            visible: root.limitError !== ""
            width: parent.width
            text: root.limitError
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------- Power profile picker ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.cursorSection === "profiles" && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.cursorSection = "profiles"
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }

        // ---------- Energy controls ----------
        PanelSeparator {
          visible: root.energyVisible
          foreground: root.bar.foreground
        }

        Column {
          visible: root.energyVisible
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "ENERGY CONTROLS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Toggle {
            width: parent.width
            label: "Travel mode"
            description: "Power-saver, 40% brightness, and 60Hz refresh cap"
            checked: root.travelMode
            enabled: !energyActionProc.running
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.setEnergy("travel", !root.travelMode)
          }

          BorderSurface {
            id: travelControls
            visible: root.energyInfo.quick_dim !== "unsupported"
            width: parent.width - Style.space(12)
            x: Style.space(6)
            implicitHeight: nestedTravelControls.implicitHeight + Style.space(20)
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b,
              root.travelMode ? 0.08 : 0.035)
            borderSpec: Border.flat(Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
              root.bar.foreground.b, root.travelMode ? 0.32 : 0.16), 1)
            radius: Style.cornerRadius

            Behavior on color { ColorAnimation { duration: 160 } }

            Column {
              id: nestedTravelControls
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(7)

              Text {
                width: parent.width
                text: "TRAVEL MODE CONTROLS"
                color: root.bar.foreground
                opacity: 0.55
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.8
              }

              Toggle {
                visible: root.energyInfo.quick_dim !== "unsupported"
                width: parent.width
                label: "Quick dim"
                description: "Set the display to 40%" + (root.energyInfo.brightness !== "unknown"
                  ? " (currently " + root.energyInfo.brightness + "%)" : "")
                checked: root.energyInfo.quick_dim === "enabled"
                enabled: !root.travelMode && !energyActionProc.running
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.setEnergy("quick-dim", root.energyInfo.quick_dim !== "enabled")
              }
            }
          }

          Text {
            visible: root.energyError !== ""
            width: parent.width
            text: root.energyError
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator {
          visible: root.gpuSectionVisible
          foreground: root.bar.foreground
        }

        Column {
          visible: root.gpuSectionVisible
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "DISCRETE GPU"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          InfoPair {
            visible: root.nvidiaRuntimeVisible
            label: "NVIDIA power"
            value: Model.gpuPowerLabel(root.energyInfo.nvidia_power)
          }

          InfoPair {
            visible: root.gpuTelemetry.usage !== undefined
            label: "GPU usage"
            value: root.gpuTelemetry.usage || ""
          }

          InfoPair {
            visible: root.gpuTelemetry.power !== undefined
            label: "Power draw"
            value: root.gpuTelemetry.power || ""
          }

          Text {
            visible: root.gpuAvailable
            width: parent.width
            text: root.gpuChangePending
              ? "Applying " + root.requestedGpuMode + "…"
              : (root.gpuError !== "" ? root.gpuError
                : (root.gpuPendingAction !== "" && root.gpuPendingAction !== "No action required"
                  ? root.gpuPendingAction + (root.gpuPendingMode !== "Unknown" ? " for " + root.gpuPendingMode : "")
                  : (root.gpuMode !== "" ? "Current: " + root.gpuMode : "Detecting…")))
            color: root.bar.foreground
            opacity: 0.65
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Row {
            id: gpuModeRow
            visible: root.gpuAvailable
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.gpuModes.length > 0
              ? (width - spacing * (root.gpuModes.length - 1)) / root.gpuModes.length
              : 0

            Repeater {
              model: root.gpuModes
              Button {
                required property var modelData
                width: gpuModeRow.cellWidth
                iconText: "󰢮"
                iconSize: Style.font.title
                text: String(modelData)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.gpuMode === modelData
                onClicked: root.requestGpuMode(String(modelData))
              }
            }
          }
        }
      }
      }

      ConfirmDialog {
        id: gpuModeConfirm
        anchors.fill: parent
        z: 20
        message: "Apply GPU mode " + root.requestedGpuMode + "?\n\nThe installed GPU service will determine whether a logout or reboot is required. Save your work before applying the change."
        cancelText: "Later"
        confirmText: "Apply"
        background: Color.popups.background
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onCanceled: opened = false
        onConfirmed: root.applyGpuMode()
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
