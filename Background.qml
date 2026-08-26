import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui

Item {
  id: root

  // Injected by the shell loader for service plugins (see shell.qml
  // ensureService): lets this plugin read/write its own entry in shell.json.
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  // Matrix rain overlay toggle, persisted on this plugin's entry in
  // shell.json as `matrix`. Defaults on; flip with
  // `omarchy-shell background setMatrix false`.
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "io.github.xadacka.vaporwave-background"
  property bool matrixOverride: false
  property bool matrixOverrideSet: false
  readonly property bool configuredMatrix: {
    var cfg = shell ? shell.shellConfig : null
    var list = cfg && Array.isArray(cfg.plugins) ? cfg.plugins : []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (entry && String(entry.id || "") === pluginId && entry.matrix !== undefined) return !!entry.matrix
    }
    return true
  }
  readonly property bool matrixEnabled: matrixOverrideSet ? matrixOverride : configuredMatrix

  function setMatrixEnabled(enabled) {
    var value = !!enabled
    matrixOverride = value
    matrixOverrideSet = true
    if (shell && typeof shell.updateEntryInline === "function") {
      var cfg = shell.shellConfig
      var list = cfg && Array.isArray(cfg.plugins) ? cfg.plugins : []
      var current = { id: pluginId }
      for (var i = 0; i < list.length; i++) {
        if (list[i] && String(list[i].id || "") === pluginId) {
          current = JSON.parse(JSON.stringify(list[i]))
          break
        }
      }
      current.matrix = value
      shell.updateEntryInline(pluginId, current)
    }
  }

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function setBackground(path, instant) {
    transitionBackground("", path, path, instant, false)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return
    currentBackground = finalPath
    backgroundVersion += 1
    revealStartedVersion = -1

    revealAnimation.stop()
    finishingTransition = false

    if (instant || !displayedBackground) {
      oldBackground = ""
      incomingBackground = ""
      displayedBackground = path
      revealProgress = 1
      return
    }

    oldBackground = fromPath || displayedBackground
    incomingBackground = path
    revealProgress = 0
  }

  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = backgroundVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    // Background polling can advance backgroundVersion while a theme switch is
    // pending; the latest theme payload should still apply.
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    Color.loadColors(pendingColorsRaw)
    // Color.loadShell also refreshes Style so the type scale flips with the
    // background reveal instead of waiting for a separate reload path.
    Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
    if (!incomingBackground || revealProgress >= 1) applyPendingTheme()
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    applyPendingTheme()
    revealAnimation.restart()
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
    onExited: root.refreshBackground()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim(), false)
    }
  }

  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.setBackground(path, false)
    }

    function setInstant(path: string): void {
      root.setBackground(path, true)
    }

    function transition(fromPath: string, path: string): void {
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }

    function setMatrix(enabled: bool): void {
      root.setMatrixEnabled(enabled)
    }

    function toggleMatrix(): void {
      root.setMatrixEnabled(!root.matrixEnabled)
    }
  }

  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      if (root.incomingBackground) {
        root.displayedBackground = root.currentBackground || root.incomingBackground
        root.finishingTransition = true
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: refreshBackground()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: "transparent"
      // Keep render updates enabled. The background layer has been observed to
      // lose its committed buffer while parked with updatesEnabled=false,
      // leaving a black desktop until omarchy-shell is restarted. The wallpaper
      // itself is static, so this favors correctness over a small render-loop
      // optimization.
      updatesEnabled: true

      property bool maskReady: false

      function maybeStartReveal() {
        if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
        if (incomingFrame.status !== Image.Ready) return
        Qt.callLater(function() {
          if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
          if (incomingFrame.status !== Image.Ready) return
          root.startReveal(panel)
        })
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Image {
        id: base
        anchors.fill: parent
        source: root.imageUrl(root.displayedBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        onStatusChanged: {
          if (status === Image.Ready && root.finishingTransition) {
            root.incomingBackground = ""
            root.oldBackground = ""
            root.finishingTransition = false
          }
        }
      }

      Image {
        id: oldFrame
        anchors.fill: parent
        source: root.imageUrl(root.oldBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: root.oldBackground !== "" && root.revealProgress < 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Item {
        id: incomingLayer
        anchors.fill: parent
        visible: root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
        layer.enabled: root.incomingBackground !== "" && root.revealProgress < 1
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: revealMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        Image {
          id: incomingFrame
          anchors.fill: parent
          source: root.imageUrl(root.incomingBackground)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          onStatusChanged: panel.maybeStartReveal()
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        readonly property real slant: -0.18
        readonly property real centerTop: width / 2 - slant * height / 2
        readonly property real centerBottom: width / 2 + slant * height / 2
        readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
        readonly property real spread: reach * root.revealProgress

        Shape {
          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "white"
            strokeColor: "transparent"
            startX: revealMask.centerTop - revealMask.spread; startY: 0
            PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
            PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
          }
        }
      }

      // Matrix-style digital rain over the wallpaper. clearRect keeps the
      // canvas transparent between glyphs so the wallpaper stays visible
      // through the gaps, rather than washing out under an accumulating trail.
      Canvas {
        id: matrixCanvas
        anchors.fill: parent
        visible: root.matrixEnabled
        renderStrategy: Canvas.Cooperative
        opacity: 0.6

        readonly property int cellSize: 22
        readonly property int trailLength: 7
        readonly property string glyphs: "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789"
        property var drops: []

        function resetDrops() {
          var cols = Math.ceil(width / cellSize)
          var d = []
          for (var i = 0; i < cols; i++) {
            d.push({
              active: Math.random() < 0.6,
              y: Math.random() * -40,
              speed: 0.35 + Math.random() * 0.7
            })
          }
          drops = d
          if (available) getContext("2d").reset()
        }
        onWidthChanged: resetDrops()
        onHeightChanged: resetDrops()
        onAvailableChanged: if (available) resetDrops()
        onVisibleChanged: if (visible) resetDrops()

        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          if (!visible) return
          ctx.font = "bold " + (cellSize - 5) + "px " + Style.font.family
          var head = Color.foreground
          var accent = Color.accent
          var rows = height / cellSize
          var d = drops
          for (var i = 0; i < d.length; i++) {
            if (!d[i].active) continue
            var x = i * cellSize
            for (var t = 0; t < trailLength; t++) {
              var rowY = d[i].y - t
              if (rowY < 0) continue
              var ch = glyphs.charAt(Math.floor(Math.random() * glyphs.length))
              var fade = 1 - t / trailLength
              if (t === 0) ctx.fillStyle = Qt.rgba(head.r, head.g, head.b, 0.9)
              else ctx.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, fade * 0.55)
              ctx.fillText(ch, x, rowY * cellSize)
            }
            d[i].y += d[i].speed
            if (d[i].y - trailLength > rows) {
              d[i].y = Math.random() * -20
              d[i].speed = 0.35 + Math.random() * 0.7
              d[i].active = Math.random() < 0.6
            }
          }
        }
      }

      Timer {
        interval: 66
        running: matrixCanvas.visible
        repeat: true
        onTriggered: matrixCanvas.requestPaint()
      }

      // Animated glow, layered on top of the wallpaper. The horizon glow
      // breathes and shifts between the theme accent and a fixed neon cyan;
      // two scanlines cross the screen in opposite directions. Reads as
      // quiet neon light on dark/vaporwave-style themes.
      Rectangle {
        id: horizonGlow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: panel.height * 0.5
        opacity: 0.1

        gradient: Gradient {
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop {
            id: glowStop
            position: 1.0
            color: Color.accent

            SequentialAnimation on color {
              loops: Animation.Infinite
              ColorAnimation { to: "#22e4ff"; duration: 6000; easing.type: Easing.InOutSine }
              ColorAnimation { to: Color.accent; duration: 6000; easing.type: Easing.InOutSine }
            }
          }
        }

        SequentialAnimation on opacity {
          loops: Animation.Infinite
          NumberAnimation { from: 0.10; to: 0.36; duration: 3400; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.36; to: 0.10; duration: 3400; easing.type: Easing.InOutSine }
        }
      }

      Rectangle {
        id: scanlineA
        anchors.left: parent.left
        anchors.right: parent.right
        height: 220
        y: -height
        opacity: 0.32
        gradient: Gradient {
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.5; color: Color.accent }
          GradientStop { position: 1.0; color: "transparent" }
        }

        SequentialAnimation on y {
          loops: Animation.Infinite
          NumberAnimation { from: -scanlineA.height; to: panel.height; duration: 9000; easing.type: Easing.InOutSine }
          PauseAnimation { duration: 800 }
        }
      }

      Rectangle {
        id: scanlineB
        anchors.left: parent.left
        anchors.right: parent.right
        height: 170
        y: panel.height
        opacity: 0.26
        gradient: Gradient {
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.5; color: "#22e4ff" }
          GradientStop { position: 1.0; color: "transparent" }
        }

        SequentialAnimation on y {
          loops: Animation.Infinite
          PauseAnimation { duration: 2600 }
          NumberAnimation { from: panel.height; to: -scanlineB.height; duration: 13000; easing.type: Easing.InOutSine }
        }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
          panel.maybeStartReveal()
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }
    }
  }
}
