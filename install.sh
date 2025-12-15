#!/bin/bash

# Clipy Installer Script

set -e

REPO="kowshikRoy/clipy"
APP_NAME="Clipy.app"
INSTALL_DIR="/Applications"
TMP_DIR=$(mktemp -d)

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Started installing Clipy..."

# Function to cleanup temporary files
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# 1. Find the latest release URL
echo "Fetching latest release information..."
RELEASE_JSON=$(curl -s https://api.github.com/repos/$REPO/releases/latest)

# Check if we got a valid response
if echo "$RELEASE_JSON" | grep -q "Not Found" || [ -z "$RELEASE_JSON" ]; then
    echo "Release 'latest' not found. Trying 'nightly' tag..."
    RELEASE_JSON=$(curl -s https://api.github.com/repos/$REPO/releases/tags/nightly)
fi

# Check if we still have no valid release
if echo "$RELEASE_JSON" | grep -q "Not Found" || [ -z "$RELEASE_JSON" ]; then
    echo -e "${RED}Error: No release found for $REPO.${NC}"
    echo "Please check https://github.com/$REPO/releases for manual installation."
    exit 1
fi

# Extract download URL for the zip file
# We look for "browser_download_url" and ensure it ends with .zip
# Use grep -o to handle both minified and pretty-printed JSON
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*"' | grep ".zip" | head -n 1 | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "${RED}Error: Could not find a .zip asset in the latest release.${NC}"
    exit 1
fi

echo "Downloading latest version from $DOWNLOAD_URL..."
curl -L --progress-bar -o "$TMP_DIR/Clipy.zip" "$DOWNLOAD_URL"

# 2. Unzip
echo "Extracting..."
unzip -q "$TMP_DIR/Clipy.zip" -d "$TMP_DIR"

# Check if the app exists in the extracted files
if [ ! -d "$TMP_DIR/$APP_NAME" ]; then
    # Sometimes the zip contains a folder which contains the app, or the structure is different
    # We search for Clipy.app inside the temp dir
    FOUND_APP=$(find "$TMP_DIR" -name "$APP_NAME" -type d | head -n 1)
    if [ -z "$FOUND_APP" ]; then
        echo -e "${RED}Error: $APP_NAME not found in the downloaded archive.${NC}"
        exit 1
    fi
    # If found in a subdirectory, move it up to TMP_DIR root for consistency
    if [ "$FOUND_APP" != "$TMP_DIR/$APP_NAME" ]; then
        mv "$FOUND_APP" "$TMP_DIR/$APP_NAME"
    fi
fi

# 3. Install
echo "Installing to $INSTALL_DIR..."

# Remove existing installation if present
if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
    echo "Removing existing Clipy installation..."
    rm -rf "$INSTALL_DIR/$APP_NAME"
fi

# Move the app
mv "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/"

# 4. Remove quarantine attribute
echo "Fixing permissions (removing quarantine attribute)..."
xattr -cr "$INSTALL_DIR/$APP_NAME"

echo -e "${GREEN}Success! Clipy has been installed to $INSTALL_DIR/$APP_NAME.${NC}"
echo "You can now launch it from your Applications folder or via Spotlight."
