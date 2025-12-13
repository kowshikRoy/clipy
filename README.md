# Clipy

Clipy is a macOS application built with Swift and SwiftUI.

## Features

- **Clipboard History**: Keep track of your copied items.
- **Snippets**: Manage and reuse common text snippets.
- **macOS Native**: Built using standard macOS technologies for a seamless experience.

## Installation

### From Releases
You can download the latest version from the [Releases](https://github.com/kowshikRoy/clipy/releases) page.

1. Download `Clipy.app.zip`.
2. Unzip the file.
3. Drag `Clipy.app` to your Applications folder.

> [!NOTE]
> **"App is damaged and can't be opened" Error**
> Since this app is not signed with a paid Apple Developer ID, macOS may block it. To fix this:
> 1. Open Terminal.
> 2. Run the following command:
>    ```bash
>    xattr -cr /Applications/Clipy.app
>    ```
> 3. You should now be able to open the app.

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
