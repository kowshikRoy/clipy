# Clipy

Clipy is a macOS application built with Swift and SwiftUI.

## Features

- **Clipboard History**: Keep track of your copied items.
- **Snippets**: Manage and reuse common text snippets.
- **macOS Native**: Built using standard macOS technologies for a seamless experience.

## Installation

### One-Line Install Command (Recommended)
You can install Clipy with a single command. Open your Terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/kowshikRoy/clipy/main/install.sh | bash
```

This will automatically:
- Download the latest release.
- Install it to your `/Applications` folder.
- Fix the "App is damaged" error (by removing quarantine attributes).

### Manual Installation
If you prefer to install manually:
1. Download the latest `Clipy.app.zip` from the [Releases](https://github.com/kowshikRoy/clipy/releases) page.
2. Unzip the file.
3. Drag `Clipy.app` to your `/Applications` folder.
4. If you see an "App is damaged" error, run:
   ```bash
   xattr -cr /Applications/Clipy.app
   ```

### From Source
1. Clone the repository:
   ```bash
   git clone https://github.com/kowshikRoy/clipy.git
   ```
2. Open `Clipy.xcodeproj` in Xcode.
3. Build and Run (Cmd+R).

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
