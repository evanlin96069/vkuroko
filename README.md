# vkuroko

[![Actions Status](https://github.com/evanlin96069/vkuroko/actions/workflows/CI.yml/badge.svg)](https://github.com/evanlin96069/vkuroko/actions?query=branch%3Amaster)

A Source Engine plugin that integrates [Kuroko](https://github.com/kuroko-lang/kuroko/) (a dialect of Python).

More bindings and TAS support are still being developed.

## Supported Games

### Windows
- Portal (3420)
- Portal (4104)
- Portal (5135)
- Portal (latest)*
- Half-Life 2 (5135)
- Half-Life 2 (latest)*

### Linux
- Portal (latest)*
- Half-Life 2 (latest)*

\* Due to https://github.com/ValveSoftware/Source-1-Games/issues/3632, plugin has to load via `addons` on latest version of the game.

## Build

Use [zig 0.15.1](https://ziglang.org/download/#release-0.15.1)

The currently running platform is the default build target:

```sh
zig build
```

Building for a specific platform:

```sh
# Windows
zig build -Dtarget=windows
# Linux
zig build -Dtarget=linux
```

