# Building from Source

## Prerequisites

- **Xcode 26+**
- **[mise](https://mise.jdx.dev/)** — tool version manager (installs Tuist)

## Build

```bash
git clone https://github.com/vapor-pawelw/magent.git
cd magent

# Generate the Xcode project
mise x -- tuist generate --no-open

# Build via Xcode
open Magent.xcworkspace
# Or build from command line:
xcodebuild build -workspace Magent.xcworkspace -scheme Magent -configuration Release
```

## Rebuild + Relaunch (Debug)

Use the helper script for local iteration. It always:
- kills running `Magent` processes first (single-instance safe)
- rebuilds the app
- relaunches the newly built Debug app

```bash
./scripts/rebuild-and-relaunch.sh
```

Optional overrides:

```bash
MAGENT_SCHEME=Magent MAGENT_CONFIGURATION=Debug MAGENT_APP_NAME=Magent ./scripts/rebuild-and-relaunch.sh
```

## First Run

1. Launch mAgent
2. Add your repositories in Settings
3. Choose your default agent (Claude, Codex, or custom)
4. Create your first thread
