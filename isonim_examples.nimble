# Package
version       = "0.1.0"
author        = "Metacraft Labs"
description   = "Canonical home for IsoNim layered demo applications - shared Layer 3 ViewModels and Layer 2 view templates with per-platform Layer 1 leaves and Layer 4 composition roots"
license       = "MIT"
# No `srcDir` — demo modules live under `<demo>/core/`, `<demo>/<platform>/`
# (e.g. `task_app/core/vm.nim`). Renderer repos consume them via path-based
# deps configured in this repo's `config.nims`.

# Dependencies
requires "nim >= 2.0.0"
