# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SillyTavern Corruption Guard is a **cross-platform** PowerShell-based monitoring system that protects SillyTavern vector database files (index.json) from corruption. It uses file system monitoring to detect when vector index files shrink unexpectedly (indicating corruption), then automatically stops SillyTavern, restores from backup, and restarts the process.

**Platform Support:**
- ✅ Windows (PowerShell 5.1 or 7+)
- ✅ Linux (PowerShell 7+)
- ✅ macOS (PowerShell 7+)

For detailed setup instructions, see [README.md](README.md).

## Architecture

The system uses a **modular PowerShell architecture** with six main components:

### Module Structure

```
ST_VM_Main.ps1           # Entry point and orchestration
Config.ps1               # Configuration management and validation
FileMonitor.ps1          # FileSystemWatcher for index.json files
BackupManager.ps1        # Lazy backup evaluation and creation
RecoveryManager.ps1      # Corruption detection and recovery workflow
ProcessManager.ps1       # SillyTavern process control
Common/Logger.ps1        # Centralized logging with color coding
Common/PlatformHelper.ps1 # Cross-platform compatibility layer (NEW)
```

### Key Architectural Patterns

**Event-Driven Communication**: Modules communicate through PowerShell's `Register-ObjectEvent` system. The FileMonitor raises events that are queued in `$script:FileChangeEvents` (a `ConcurrentQueue`) and consumed by the main loop.

**Lazy Backup Evaluation**: BackupManager only creates/updates backups when:
1. No backup exists AND source JSON is valid, OR
2. Source file is larger than backup AND source JSON is valid

This prevents corrupted files from overwriting good backups.

**Corruption Detection Algorithm**:
- Condition 1: Backup file > CorruptionThresholdMB (default: 1MB)
- Condition 2: Source file < (Backup file × CorruptionDropRatio) (default: 0.333)
- If BOTH true → Corruption detected

**Singleton Pattern**: Uses a named mutex (`SillyTavernCorruptionGuard`) to ensure only one instance runs at a time.

## Running the Application

### Windows
```powershell
# Run with default configuration (config/settings.json)
.\ST_VM_Main.ps1

# Run with custom configuration file
.\ST_VM_Main.ps1 -ConfigFilePath path\to\custom-config.json
```

### Linux/macOS
```bash
# Install PowerShell 7+ first (see README.md for instructions)
pwsh ./ST_VM_Main.ps1

# Or use the launcher
chmod +x start.sh
./start.sh

# With custom configuration
pwsh ./ST_VM_Main.ps1 -ConfigFilePath /path/to/custom-config.json
```

The main script will:
1. Initialize configuration and acquire singleton mutex
2. Start SillyTavern process
3. Begin monitoring vector files
4. Start periodic backup timer (default: every 60 seconds)
5. Enter main event loop

Press Ctrl+C to stop gracefully.

## Configuration

Configuration is managed through `config/settings.json`:

```json
{
  "sillyTavern": {
    "executablePath": "path\\to\\SillyTavern\\start.bat",
    "processName": "node"  // Process name to monitor
  },
  "monitoring": {
    "vectorsRootPath": "path\\to\\vectors",
    "backupIntervalSeconds": 60,
    "corruptionThresholdMB": 1,
    "corruptionDropRatio": 0.333  // 33.3% drop triggers recovery
  },
  "logging": {
    "level": "Info",
    "includeTimestamp": true
  }
}
```

If no config file exists, the system falls back to hardcoded defaults in Config.ps1:48-75.

## Key Module Functions

### FileMonitor.ps1
- `Start-FileMonitoring()` - Creates FileSystemWatcher for recursive index.json monitoring
- `Get-FileChangeEvent()` - Dequeues events from the concurrent queue
- Event handlers register events via `-MessageData` parameter to pass the queue reference (FileMonitor.ps1:68-70)

### BackupManager.ps1
- `Invoke-BackupProcess()` - Main backup workflow, runs on timer
- `Invoke-LazyBackupEvaluation($SourceFile)` - Implements the lazy backup logic
- `Test-JsonValidity($FilePath)` - Validates JSON structure before backup
- `Copy-FileWithVerification($SourcePath, $DestinationPath)` - Copies with retry logic and size verification

### RecoveryManager.ps1
- `Test-CorruptionCondition($SourceFile)` - Evaluates corruption detection algorithm
- `Invoke-RecoveryProcess($CorruptedFile)` - 4-step recovery workflow:
  1. Stop SillyTavern
  2. Restore from backup
  3. Restart SillyTavern
  4. Verify recovery
- Tracks recovery attempts per file (max 3 attempts by default)

### ProcessManager.ps1
- `Start-SillyTavern()` - Launches start.bat/.sh and finds the node process
- `Stop-SillyTavern($TimeoutSeconds)` - Gracefully terminates with timeout (uses SIGTERM on Linux)
- `Restart-SillyTavern()` - Stop + Start with force fallback
- `Test-ProcessHealth()` - Checks if process is still running

### PlatformHelper.ps1 (NEW)
- `Get-PlatformInfo()` - Returns current platform details
- `New-CrossPlatformMutex($Name)` - Creates mutex (Windows) or file-based lock (Linux/macOS)
- `Enter-CrossPlatformMutex()` / `Exit-CrossPlatformMutex()` - Lock acquisition and release
- `Stop-ProcessSafely($Process)` - Platform-aware process termination
- `Get-ExecutableExtension()` - Returns .bat (Windows) or .sh (Linux/macOS)
- `Get-DefaultSillyTavernPath()` - Platform-specific default paths
- `Set-ExecutablePermission()` - Sets +x on Linux/macOS (no-op on Windows)

## Important Implementation Details

### Event Scope Issue (Fixed in commit 27c3600)
The FileSystemWatcher event handlers run in a different scope and cannot access script-level variables directly. The fix passes `$script:FileChangeEvents` queue via the `-MessageData` parameter and accesses it through `$Event.MessageData` in the handlers (FileMonitor.ps1:42, 53, 65).

### Main Event Loop
The main loop in ST_VM_Main.ps1:88-104:
- Dequeues file change events every 500ms
- Calls `Handle-FileChangeEvent` which checks for corruption
- Every 5 seconds, performs process health check
- Runs until `$script:Running` is set to false (Ctrl+C handler)

### Module Dependencies
All modules import Logger.ps1 and Config.ps1. Main imports all modules. Use `Import-Module -Force` to ensure latest version is loaded.

### Backup File Naming
Backups are created as `{original-filename}.bak` in the same directory as the source file.

## Development Guidelines

### Working with Configuration
Always use `Get-ConfigurationValue -Key "KeyName"` to access config values from modules. Never access `$script:SillyTavernConfig` directly from outside Config.ps1.

### Adding New Modules
1. Import Logger.ps1 and Config.ps1 at the top
2. Use script-scoped variables (`$script:`) for module state
3. Export only public functions
4. Log all significant actions with appropriate levels (Info, Warning, Error, Success, Debug)

### Error Handling
All modules use try/catch blocks and log errors via `Write-LogError`. Functions return `$true/$false` for success/failure, or `$null` on critical failures.

### Testing Changes
Since this monitors live SillyTavern data, test with:
1. A test vectors directory (modify config)
2. Create test index.json files
3. Verify corruption detection by manually shrinking a file
4. Check that Ctrl+C cleanup works properly

## Troubleshooting

**"Another instance is already running"**: The singleton mutex is held. Either stop the other instance or check if a hung PowerShell process needs to be killed.

**Events not firing**: Check that `Register-ObjectEvent` subscriptions are active with `Get-EventSubscriber`. The FileMonitor uses SourceIdentifiers: `FileChanged`, `FileCreated`, `FileRenamed`.

**Backup timer not running**: Verify with `Get-EventSubscriber -SourceIdentifier "BackupTimer"`. Check that `Start-BackupTimer()` returned `$true`.

**Process not found**: The system looks for processes matching `processName` from config. If SillyTavern uses a different process name, update the config.
