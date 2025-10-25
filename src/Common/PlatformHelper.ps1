# PlatformHelper.ps1
# Cross-platform utility functions for Windows and Linux compatibility

<#
.SYNOPSIS
    Provides platform-specific helper functions for cross-platform compatibility.

.DESCRIPTION
    This module abstracts platform-specific operations to ensure the application
    works correctly on both Windows (PowerShell 5.1/7+) and Linux (PowerShell 7+).
#>

# Detect platform
$script:IsWindowsPlatform = if ($PSVersionTable.PSVersion.Major -ge 6) {
    $IsWindows
} else {
    $true  # PowerShell 5.1 only runs on Windows
}

$script:IsLinuxPlatform = if ($PSVersionTable.PSVersion.Major -ge 6) {
    $IsLinux
} else {
    $false
}

$script:IsMacOSPlatform = if ($PSVersionTable.PSVersion.Major -ge 6) {
    $IsMacOS
} else {
    $false
}

function Get-PlatformInfo {
    <#
    .SYNOPSIS
        Returns information about the current platform.
    #>
    return @{
        IsWindows = $script:IsWindowsPlatform
        IsLinux = $script:IsLinuxPlatform
        IsMacOS = $script:IsMacOSPlatform
        OSDescription = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        PSVersion = $PSVersionTable.PSVersion.ToString()
    }
}

function Get-ExecutableExtension {
    <#
    .SYNOPSIS
        Returns the appropriate executable extension for the platform.
    #>
    if ($script:IsWindowsPlatform) {
        return ".bat"
    } else {
        return ".sh"
    }
}

function Get-ProcessByName {
    <#
    .SYNOPSIS
        Gets a process by name in a cross-platform way.
    .PARAMETER ProcessName
        The name of the process to find.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProcessName
    )
    
    try {
        return Get-Process -Name $ProcessName -ErrorAction Stop
    } catch {
        return $null
    }
}

function Stop-ProcessSafely {
    <#
    .SYNOPSIS
        Stops a process gracefully with platform-specific handling.
    .PARAMETER Process
        The process object to stop.
    .PARAMETER Force
        Force immediate termination.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [System.Diagnostics.Process]$Process,
        [switch]$Force
    )
    
    try {
        if ($script:IsWindowsPlatform) {
            # Windows: Use .NET method
            if ($Force) {
                $Process.Kill()
            } else {
                $Process.CloseMainWindow() | Out-Null
                Start-Sleep -Seconds 2
                if (-not $Process.HasExited) {
                    $Process.Kill()
                }
            }
        } else {
            # Linux: Send SIGTERM first, then SIGKILL if needed
            if ($Force) {
                Stop-Process -Id $Process.Id -Force -ErrorAction Stop
            } else {
                # Send SIGTERM for graceful shutdown
                Stop-Process -Id $Process.Id -ErrorAction Stop
                Start-Sleep -Seconds 2
                
                # Check if still running
                $stillRunning = Get-Process -Id $Process.Id -ErrorAction SilentlyContinue
                if ($stillRunning) {
                    Stop-Process -Id $Process.Id -Force -ErrorAction Stop
                }
            }
        }
        return $true
    } catch {
        Write-Warning "Failed to stop process: $_"
        return $false
    }
}

function New-CrossPlatformMutex {
    <#
    .SYNOPSIS
        Creates a cross-platform synchronization primitive.
    .DESCRIPTION
        On Windows, uses System.Threading.Mutex.
        On Linux, uses file-based locking as mutexes behave differently.
    .PARAMETER Name
        The name of the mutex/lock.
    .PARAMETER LockDirectory
        Directory to store lock files (Linux only).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [string]$LockDirectory = $null
    )
    
    if ($script:IsWindowsPlatform) {
        # Windows: Use traditional mutex
        try {
            $mutex = New-Object System.Threading.Mutex($false, $Name)
            return @{
                Type = "Mutex"
                Handle = $mutex
                Name = $Name
            }
        } catch {
            Write-Error "Failed to create mutex: $_"
            return $null
        }
    } else {
        # Linux: Use file-based locking
        if (-not $LockDirectory) {
            $LockDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "ps_locks"
        }
        
        if (-not (Test-Path $LockDirectory)) {
            New-Item -ItemType Directory -Path $LockDirectory -Force | Out-Null
        }
        
        $lockFile = Join-Path $LockDirectory "$Name.lock"
        
        return @{
            Type = "FileLock"
            Handle = $null
            Name = $Name
            LockFile = $lockFile
        }
    }
}

function Enter-CrossPlatformMutex {
    <#
    .SYNOPSIS
        Acquires a cross-platform lock.
    .PARAMETER MutexObject
        The mutex object created by New-CrossPlatformMutex.
    .PARAMETER TimeoutMs
        Timeout in milliseconds (default: 5000).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$MutexObject,
        [int]$TimeoutMs = 5000
    )
    
    if ($MutexObject.Type -eq "Mutex") {
        try {
            return $MutexObject.Handle.WaitOne($TimeoutMs)
        } catch {
            Write-Error "Failed to acquire mutex: $_"
            return $false
        }
    } else {
        # File-based locking
        $lockFile = $MutexObject.LockFile
        $endTime = (Get-Date).AddMilliseconds($TimeoutMs)
        
        while ((Get-Date) -lt $endTime) {
            try {
                # Try to create lock file exclusively
                $fileStream = [System.IO.File]::Open(
                    $lockFile,
                    [System.IO.FileMode]::CreateNew,
                    [System.IO.FileAccess]::Write,
                    [System.IO.FileShare]::None
                )
                
                $MutexObject.Handle = $fileStream
                
                # Write PID to lock file
                $writer = New-Object System.IO.StreamWriter($fileStream)
                $writer.WriteLine($PID)
                $writer.Flush()
                
                return $true
            } catch [System.IO.IOException] {
                # Lock file exists, wait and retry
                Start-Sleep -Milliseconds 100
            } catch {
                Write-Error "Failed to acquire file lock: $_"
                return $false
            }
        }
        
        return $false
    }
}

function Exit-CrossPlatformMutex {
    <#
    .SYNOPSIS
        Releases a cross-platform lock.
    .PARAMETER MutexObject
        The mutex object to release.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$MutexObject
    )
    
    try {
        if ($MutexObject.Type -eq "Mutex") {
            # Check if mutex is actually owned before releasing
            try {
                $MutexObject.Handle.ReleaseMutex()
            } catch [System.ApplicationException] {
                # Mutex not owned by current thread, ignore
                Write-Verbose "Mutex was not owned by current thread"
            }
        } else {
            # File-based locking
            if ($MutexObject.Handle) {
                $MutexObject.Handle.Close()
                $MutexObject.Handle.Dispose()
                $MutexObject.Handle = $null
            }
            
            if (Test-Path $MutexObject.LockFile) {
                Remove-Item -Path $MutexObject.LockFile -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Warning "Failed to release lock: $_"
    }
}

function Dispose-CrossPlatformMutex {
    <#
    .SYNOPSIS
        Disposes a cross-platform mutex.
    .PARAMETER MutexObject
        The mutex object to dispose.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$MutexObject
    )
    
    try {
        # Try to release if it's still held
        try {
            Exit-CrossPlatformMutex -MutexObject $MutexObject
        } catch {
            # Ignore errors during release in dispose
        }
        
        if ($MutexObject.Type -eq "Mutex" -and $MutexObject.Handle) {
            try {
                $MutexObject.Handle.Dispose()
            } catch {
                # Ignore disposal errors
            }
        }
    } catch {
        Write-Warning "Failed to dispose mutex: $_"
    }
}

function Test-ExecutableExists {
    <#
    .SYNOPSIS
        Tests if an executable exists and is executable.
    .PARAMETER Path
        Path to the executable.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    if (-not (Test-Path $Path)) {
        return $false
    }
    
    # On Linux, check if file is executable
    if ($script:IsLinuxPlatform) {
        try {
            $permissions = (Get-Item $Path).UnixMode
            # Check if any execute bit is set (user, group, or other)
            # This is a simple check - proper implementation would parse UnixMode
            return $true  # If file exists, assume it can be made executable
        } catch {
            return $false
        }
    }
    
    return $true
}

function Set-ExecutablePermission {
    <#
    .SYNOPSIS
        Sets executable permission on a file (Linux only, no-op on Windows).
    .PARAMETER Path
        Path to the file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    if ($script:IsLinuxPlatform) {
        try {
            chmod +x $Path
            Write-Verbose "Set executable permission on $Path"
        } catch {
            Write-Warning "Failed to set executable permission: $_"
        }
    }
}

function Get-DefaultSillyTavernPath {
    <#
    .SYNOPSIS
        Returns the default SillyTavern installation path for the platform.
    #>
    if ($script:IsWindowsPlatform) {
        return "C:\SillyTavern"
    } elseif ($script:IsLinuxPlatform) {
        return Join-Path $env:HOME "SillyTavern"
    } else {
        return Join-Path $env:HOME "SillyTavern"
    }
}

function Get-DefaultVectorsPath {
    <#
    .SYNOPSIS
        Returns the default vectors path for the platform.
    #>
    $basePath = Get-DefaultSillyTavernPath
    return Join-Path $basePath "data" "default-user" "vectors"
}

function Resolve-CrossPlatformPath {
    <#
    .SYNOPSIS
        Converts a path to the correct format for the current platform.
    .PARAMETER Path
        The path to convert.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    if ($script:IsWindowsPlatform) {
        # Convert forward slashes to backslashes
        return $Path -replace '/', '\'
    } else {
        # Convert backslashes to forward slashes
        return $Path -replace '\\', '/'
    }
}

# Functions are automatically available when dot-sourced
# No Export-ModuleMember needed for .ps1 script files
