# SillyTavern Corruption Guard - Cross-Platform Edition

A cross-platform monitoring system that protects SillyTavern vector databases from corruption through automated backup and recovery mechanisms.

## Platform Support

- ✅ **Windows** (PowerShell 5.1 or PowerShell 7+)
- ✅ **Linux** (PowerShell 7+)
- ✅ **macOS** (PowerShell 7+)

## Prerequisites

### Windows
- PowerShell 5.1 (built-in) or PowerShell 7+
- SillyTavern with `start.bat`

### Linux/macOS
- PowerShell 7+ (install from https://aka.ms/powershell)
- SillyTavern with `start.sh` (make sure it's executable: `chmod +x start.sh`)

## Installation

### Installing PowerShell 7+ on Linux

**Ubuntu/Debian:**
```bash
# Download the Microsoft repository GPG keys
wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb

# Register the Microsoft repository GPG keys
sudo dpkg -i packages-microsoft-prod.deb

# Update the list of packages
sudo apt-get update

# Install PowerShell
sudo apt-get install -y powershell
```

**Other distributions:** See https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux

### Verify Installation
```bash
pwsh --version
```

## Configuration

The application automatically detects your platform and uses appropriate defaults:

### Windows Default Paths
- Executable: `C:\SillyTavern\start.bat`
- Vectors: `C:\SillyTavern\data\default-user\vectors`

### Linux/macOS Default Paths
- Executable: `~/SillyTavern/start.sh`
- Vectors: `~/SillyTavern/data/default-user/vectors`

### Custom Configuration

Create a platform-specific config file:

**Windows:** `config/settings.json`
```json
{
    "sillyTavern": {
        "executablePath": "D:\\path\\to\\SillyTavern\\start.bat",
        "processName": "node"
    },
    "monitoring": {
        "vectorsRootPath": "D:\\path\\to\\vectors",
        "backupIntervalSeconds": 60,
        "corruptionThresholdMB": 1,
        "corruptionDropRatio": 0.333
    },
    "logging": {
        "level": "Info"
    }
}
```

**Linux/macOS:** `config/settings.json`
```json
{
    "sillyTavern": {
        "executablePath": "/home/user/SillyTavern/start.sh",
        "processName": "node"
    },
    "monitoring": {
        "vectorsRootPath": "/home/user/SillyTavern/data/default-user/vectors",
        "backupIntervalSeconds": 60,
        "corruptionThresholdMB": 1,
        "corruptionDropRatio": 0.333
    },
    "logging": {
        "level": "Info"
    }
}
```

## Usage

### Windows

**PowerShell 5.1 or 7+:**
```powershell
.\ST_VM_Main.ps1
```

Or with custom config:
```powershell
.\ST_VM_Main.ps1 -ConfigFilePath "path\to\custom-config.json"
```

### Linux/macOS

**PowerShell 7+:**
```bash
pwsh ./ST_VM_Main.ps1
```

Or use the launcher:
```bash
chmod +x start.sh
./start.sh
```

With custom config:
```bash
pwsh ./ST_VM_Main.ps1 -ConfigFilePath "/path/to/custom-config.json"
```

### Run as Background Service

**Linux (systemd):**

Create `/etc/systemd/system/sillytavern-guard.service`:
```ini
[Unit]
Description=SillyTavern Corruption Guard
After=network.target

[Service]
Type=simple
User=youruser
WorkingDirectory=/path/to/corruption-guard
ExecStart=/usr/bin/pwsh -File /path/to/corruption-guard/ST_VM_Main.ps1
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable sillytavern-guard
sudo systemctl start sillytavern-guard
sudo systemctl status sillytavern-guard
```

**Windows (Task Scheduler):**

Run as a scheduled task on startup - see documentation in `docs/` folder.

## Architecture Changes

### Cross-Platform Compatibility

The application now includes a **PlatformHelper** module (`Common/PlatformHelper.ps1`) that provides:

1. **Platform Detection**
   - Automatic detection of Windows, Linux, and macOS
   - PowerShell version compatibility (5.1 and 7+)

2. **Path Handling**
   - Cross-platform path construction using `Join-Path`
   - Automatic path separator conversion

3. **Process Management**
   - Graceful process termination (SIGTERM on Linux, CloseMainWindow on Windows)
   - Cross-platform process enumeration

4. **Synchronization Primitives**
   - Windows: Native `System.Threading.Mutex`
   - Linux/macOS: File-based locking mechanism
   - Prevents multiple instances from running simultaneously

5. **File Permissions**
   - Automatic executable permission setting on Linux/macOS
   - No-op on Windows

### Key Changes from Windows-Only Version

- ✅ Replaced hardcoded backslashes with `Join-Path`
- ✅ Platform-specific executable extensions (`.bat` vs `.sh`)
- ✅ Cross-platform mutex implementation
- ✅ Graceful process termination
- ✅ Platform-aware default paths
- ✅ File permission handling

## Features

- **Real-time Monitoring**: Watches vector database files for corruption
- **Automated Backups**: Periodic backups with lazy evaluation
- **Corruption Detection**: Identifies corrupted files by size anomalies
- **Automatic Recovery**: Restores from backups and restarts SillyTavern
- **Event-Driven Architecture**: Efficient resource usage
- **Cross-Platform**: Same codebase works on Windows, Linux, and macOS
- **Singleton Guard**: Prevents multiple instances

## Monitoring Logic

The guard detects corruption when:
- File size drops below threshold (default: 1 MB)
- File size drops by more than ratio (default: 33.3%)
- Compared to previous known-good backup

## Troubleshooting

### PowerShell Version Issues

Check your PowerShell version:
```powershell
$PSVersionTable.PSVersion
```

On Linux, always use `pwsh` (PowerShell 7+), not `powershell` (which doesn't exist).

### Permission Denied on Linux

Make sure scripts are executable:
```bash
chmod +x start.sh
chmod +x /path/to/SillyTavern/start.sh
```

### Mutex/Lock Issues

If you see "Another instance is running" but it's not:

**Windows:**
```powershell
# Restart PowerShell session
```

**Linux:**
```bash
# Remove stale lock files
rm -f /tmp/ps_locks/SillyTavernCorruptionGuard.lock
```

### Path Issues

Always use forward slashes in config on Linux, backslashes on Windows, or let the system use defaults.

## Development

### Testing Platform Detection

```powershell
Import-Module ./Common/PlatformHelper.ps1
Get-PlatformInfo
```

### Running Tests

```powershell
# Test mutex system
$mutex = New-CrossPlatformMutex -Name "TestMutex"
Enter-CrossPlatformMutex -MutexObject $mutex
Exit-CrossPlatformMutex -MutexObject $mutex
Dispose-CrossPlatformMutex -MutexObject $mutex
```

## License

See original project for license information.

## Credits

Cross-platform port: Adds Linux and macOS support while maintaining Windows compatibility.
