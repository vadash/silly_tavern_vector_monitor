$script:LoggerPath = Join-Path $PSScriptRoot "Common" "Logger.ps1"
$script:PlatformHelperPath = Join-Path $PSScriptRoot "Common" "PlatformHelper.ps1"
$script:ConfigPath = Join-Path $PSScriptRoot "Config.ps1"

Import-Module $script:LoggerPath -Force
Import-Module $script:PlatformHelperPath -Force
Import-Module $script:ConfigPath -Force

$script:SillyTavernProcess = $null

function Start-SillyTavern {
    Write-LogInfo "Starting SillyTavern..."
    
    try {
        $executablePath = Get-ConfigurationValue -Key "SillyTavernExecutablePath"
        $processName = Get-ConfigurationValue -Key "SillyTavernProcessName"
        
        if (-not (Test-Path $executablePath)) {
            Write-LogError "SillyTavern executable not found at: $executablePath"
            return $null
        }
        
        $existingProcess = Get-SillyTavernProcess
        if ($null -ne $existingProcess) {
            Write-LogWarning "SillyTavern is already running (PID: $($existingProcess.Id))"
            $script:SillyTavernProcess = $existingProcess
            return $existingProcess
        }
        
        $workingDirectory = Split-Path $executablePath -Parent
        
        # Ensure executable has proper permissions on Linux
        Set-ExecutablePermission -Path $executablePath
        
        $process = Start-Process -FilePath $executablePath -WorkingDirectory $workingDirectory -PassThru
        
        Start-Sleep -Seconds 3
        
        $script:SillyTavernProcess = Get-Process -Name $processName -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($null -ne $script:SillyTavernProcess) {
            Write-LogSuccess "SillyTavern started successfully (PID: $($script:SillyTavernProcess.Id))"
            return $script:SillyTavernProcess
        } else {
            Write-LogWarning "SillyTavern process started but could not be verified"
            return $process
        }
        
    } catch {
        Write-LogError "Failed to start SillyTavern: $($_.Exception.Message)"
        return $null
    }
}

function Stop-SillyTavern {
    param(
        [Parameter(Mandatory=$false)]
        [int]$TimeoutSeconds = 30
    )
    
    Write-LogInfo "Stopping SillyTavern..."
    
    try {
        $process = Get-SillyTavernProcess
        
        if ($null -eq $process) {
            Write-LogWarning "SillyTavern process not found"
            return $true
        }
        
        Write-LogInfo "Terminating SillyTavern process (PID: $($process.Id))..."
        
        # Use cross-platform process stopping
        $stopped = Stop-ProcessSafely -Process $process
        
        if (-not $stopped) {
            Write-LogWarning "Graceful stop failed, forcing termination..."
            $stopped = Stop-ProcessSafely -Process $process -Force
        }
        
        $waited = $process.WaitForExit($TimeoutSeconds * 1000)
        
        if ($waited) {
            Write-LogSuccess "SillyTavern stopped successfully"
            $script:SillyTavernProcess = $null
            return $true
        } else {
            Write-LogWarning "SillyTavern did not stop within timeout period"
            return $false
        }
        
    } catch {
        Write-LogError "Failed to stop SillyTavern: $($_.Exception.Message)"
        return $false
    }
}

function Get-SillyTavernProcess {
    try {
        $processName = Get-ConfigurationValue -Key "SillyTavernProcessName"
        
        $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
        
        if ($null -eq $processes -or $processes.Count -eq 0) {
            return $null
        }
        
        if ($processes -is [array]) {
            return $processes[0]
        }
        
        return $processes
        
    } catch {
        Write-LogDebug "Error getting SillyTavern process: $($_.Exception.Message)"
        return $null
    }
}

function Restart-SillyTavern {
    Write-LogInfo "Restarting SillyTavern..."
    
    try {
        $stopped = Stop-SillyTavern
        
        if (-not $stopped) {
            Write-LogWarning "Force stopping SillyTavern..."
            $process = Get-SillyTavernProcess
            if ($null -ne $process) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
        }
        
        Start-Sleep -Seconds 2
        
        $process = Start-SillyTavern
        
        if ($null -ne $process) {
            Write-LogSuccess "SillyTavern restarted successfully"
            return $true
        } else {
            Write-LogError "Failed to restart SillyTavern"
            return $false
        }
        
    } catch {
        Write-LogError "Failed to restart SillyTavern: $($_.Exception.Message)"
        return $false
    }
}

function Test-ProcessHealth {
    $process = Get-SillyTavernProcess
    
    if ($null -eq $process) {
        return $false
    }
    
    try {
        if ($process.HasExited) {
            return $false
        }
        return $true
    } catch {
        return $false
    }
}
