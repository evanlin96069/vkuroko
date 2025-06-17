# vkuroko

[![Actions Status](https://github.com/evanlin96069/vkuroko/actions/workflows/CI.yml/badge.svg)](https://github.com/evanlin96069/vkuroko/actions?query=branch%3Amaster)

A Source Engine plugin that integrates [Kuroko](https://github.com/kuroko-lang/kuroko/) (a dialect of Python).

More bindings and TAS support are still being developed.

## Supported Games
- Portal (3420)
- Portal (4104)
- Portal (5135)
- Portal (latest) [Load via addons]
- Half-Life 2 (5135)
- Half-Life 2 (latest) [Load via addons]

## Build
Linux and Windows support.

Use [zig 0.14.1](https://ziglang.org/download/#release-0.14.1)

The currently running platform is the default build target:

```sh
zig build
```

Building for a specific platform other than the currently running platform:

```sh
# Windows
zig build -Dtarget=windows
# Linux
zig build -Dtarget=linux
```

If cross-compiling from Linux to Windows and vice versa, you must have the correct compilers.
