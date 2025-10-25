#!/usr/bin/env bash
# Cross-platform launcher for SillyTavern Corruption Guard (Linux/macOS)
# Requires PowerShell 7+

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if pwsh is installed
if ! command -v pwsh &> /dev/null; then
    echo "Error: PowerShell 7+ (pwsh) is not installed."
    echo ""
    echo "Install PowerShell 7+ from: https://aka.ms/powershell"
    echo ""
    echo "Ubuntu/Debian:"
    echo "  wget -q https://packages.microsoft.com/config/ubuntu/\$(lsb_release -rs)/packages-microsoft-prod.deb"
    echo "  sudo dpkg -i packages-microsoft-prod.deb"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y powershell"
    echo ""
    echo "macOS:"
    echo "  brew install powershell/tap/powershell"
    exit 1
fi

# Run the main script with all arguments passed through
pwsh -File "$SCRIPT_DIR/src/ST_VM_Main.ps1" "$@"
