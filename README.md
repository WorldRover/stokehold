# stokehold

Steampunk-maritime macOS menubar app showing how hard your machine is running under an AI agent fleet.

## Overview

`stokehold` is the complement to a fleet status dashboard: it doesn't show what your agents are *doing*, it shows what they're *costing your machine* — CPU, RAM, and load average, rendered as brass steam-pressure gauges. Running `claude` / `codex` / `gemini` processes are personified as "the black gang" stoking the boilers below deck.

## Getting started

```bash
swift run
```

Requires macOS 13+ and Xcode command line tools (Swift 6 toolchain).

## Usage

Click the menubar item for the full gauge panel. The glance figure updates live; the popover shows CPU/RAM/load gauges plus a black-gang status line.

## License

[MIT](LICENSE) — Copyright (c) 2026 Dan Ziegler
