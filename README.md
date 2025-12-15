# Clipy

Clipy is a modern, privacy-focused clipboard manager for macOS, built with **Swift** and **SwiftUI**. It seamlessly integrates with your workflow, providing a beautiful and intelligent way to manage your clipboard history.

![License](https://img.shields.io/badge/License-MIT-blue)

## Features

### 🧠 Smart Clipboard History
Clipy automatically recognizes and categorizes your copied content:
- **Text**: Standard text snippets.
- **Colors**: Detects hex codes (e.g., `#FF5733`) and shows a preview.
- **Links**: Identifies URLs for quick access.
- **Code**: Highlights code snippets.
- **Email**: Recognizes email addresses.

### 🛡️ Privacy Controls
Your clipboard data is yours. Clipy provides robust privacy settings:
- **Blocked Apps**: Prevent Clipy from recording content copied from specific applications (e.g., Password Managers).
- **Blocked Websites**: Automatically ignore content copied from specific domains.

### ⚡ Fast & Efficient
- **Instant Search**: Quickly find anything in your history by text, type, or source application.
- **Keyboard Navigation**: Navigate your history without lifting your fingers from the keyboard.
- **Metadata**: View detailed information like source application, active URL, creation date, and size.

### 🎨 Modern Design
Features the **Lumina** design language with an **Obsidian** dark theme, offering a sleek, translucent interface that feels at home on macOS.

---

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
