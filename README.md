# Vaporwave Background

An [Omarchy](https://omarchy.org) shell plugin that replaces the built-in
desktop background service with one that layers a bit of motion on top of
your wallpaper:

- a slow pulsing horizon glow that shifts hue between the current theme's
  accent color and a fixed neon cyan
- two soft neon scanlines crossing the screen in opposite directions
- an optional Matrix-style digital rain (falling katakana and digits),
  transparent between glyphs so the wallpaper stays visible underneath

It's a fork of Omarchy's first-party `omarchy.background` service — wallpaper
switching, theme transitions, and double-click-to-open-selector all still
work exactly as before. This just adds the animated layers on top.

Built as the companion piece to the [Vaporwave theme](https://github.com/xadacka/omarchy-vaporwave-theme),
but it works with any theme — the glow follows whatever `accent` color is
currently active.

## Install

```bash
omarchy plugin add https://github.com/xadacka/omarchy-vaporwave-background.git --enable
omarchy restart shell
```

A full shell restart (not just a plugin rescan) is needed the first time —
Quickshell "service"-kind plugins like this one don't hot-reload on save the
way bar widgets do.

## Toggle the Matrix rain

On by default. Turn it off (keeping the glow and scanlines) or back on
without editing any files:

```bash
omarchy-shell background setMatrix false
omarchy-shell background setMatrix true
```

The setting is saved on this plugin's entry in `~/.config/omarchy/shell.json`
and survives restarts.

## Uninstall

```bash
omarchy plugin remove io.github.xadacka.vaporwave-background --yes
omarchy restart shell
```

Omarchy automatically falls back to the stock `omarchy.background` service.

## License

MIT — see `LICENSE`.
