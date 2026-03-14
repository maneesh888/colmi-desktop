# Contributing to Colmi Desktop

Thanks for your interest in contributing! 🎉

## Getting Started

1. Fork the repo
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/colmi-desktop.git`
3. Create a branch: `git checkout -b feature/your-feature`
4. Make your changes
5. Test: `cd macos/ColmiSync && swift test`
6. Commit: `git commit -m "feat: your feature"`
7. Push: `git push origin feature/your-feature`
8. Open a Pull Request

## Development Setup

### Requirements
- macOS 13+
- Xcode 15+ or Swift 5.9+
- A Colmi ring (for testing BLE features)

### Build

```bash
cd macos/ColmiSync
swift build
```

### Run

```bash
swift run
```

### Test

```bash
swift test
```

## Code Style

- Swift standard conventions
- Use `// MARK: -` for section headers
- Document public APIs with `///` comments
- Keep functions focused and small

## Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — New feature
- `fix:` — Bug fix
- `docs:` — Documentation
- `refactor:` — Code refactoring
- `test:` — Tests
- `chore:` — Maintenance

Examples:
```
feat: add sleep data parsing
fix: correct HR byte offset in protocol
docs: update README with installation steps
```

## Project Structure

```
colmi-desktop/
├── macos/ColmiSync/          # macOS app
│   ├── Sources/
│   │   ├── ColmiSyncApp.swift    # App entry point
│   │   ├── Views/                # SwiftUI views
│   │   ├── BLE/                  # Bluetooth manager
│   │   ├── Protocol/             # Ring protocol
│   │   └── Storage/              # Data persistence
│   └── Tests/                # Unit tests
├── docs/                     # Documentation
└── shared/                   # Shared resources
```

## Adding Ring Commands

1. Find the command in [tahnok's Python client](https://github.com/tahnok/colmi_r02_client)
2. Add the command to `ColmiProtocol.swift`
3. Add parser if needed
4. Expose via `BLEManager`
5. Add UI in `MenuBarView`
6. Write tests

## Questions?

Open an issue or join the [Gadgetbridge Discord](https://discord.gg/K4wvDqDZvn).

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
