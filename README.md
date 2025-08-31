# fluid

---

## Overview

- Declarative UI library aimed to support modern UI
  - New solver focus
  - No defaults (Causes friction with stylesheets)
- Focus on correctness, simplicity, & stability
- Mixed-table approach to properties & children. `fluid.create("Frame")({ Name = "hi", child() })`
- Go fast and try things out, we can slow down when we approach 1.0

## Interesting features

This section details the interesting bits where Fluid has an advantage.

- Support for async reactive nodes. `fluid.async`
- Push-pull reactive graph with deferred mode
- `interval` utility to poll values. `fluid.interval` will run at the specified hz
- Exported `UsedAs` type
- `_G.__DEV__` or `fluid.flags.dev_mode` for development mode, which will enhance error messages & print useful information at the cost of performance.

## Prior Art

- **Heavily** based off [Vide](https://github.com/centau/vide/), which is based off [solidjs](https://github.com/solidjs/solid). This project started as a series of W.I.P. pull requests to Vide, which ended up in full (opinionated) rewrites and significant breaking changes.
  - Vide was used as reference for implementing the reactive graph functions (derive, source, )
- Utilizes Alice's [hybrid push-pull reactive graph](https://gist.github.com/alicesaidhi/32f5bd225932a5d0239d0798c3d2e292) (based off Vide's reactive graph)
- Animation, time & color utilities inspired by [Fusion](https://github.com/dphfox/Fusion).
