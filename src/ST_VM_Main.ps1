$script:LoggerPath = Join-Path $PSScriptRoot "Common" "Logger.ps1"
$script:PlatformHelperPath = Join-Path $PSScriptRoot "Common" "PlatformHelper.ps1"
$script:ConfigPath = Join-Path $PSScriptRoot "Config.ps1"
$script:ProcessManagerPath = Join-Path $PSScriptRoot "ProcessManager.ps1"
$script:FileMonitorPath = Join-Path $PSScriptRoot "FileMonitor.ps1"
$script:BackupManagerPath = Join-Path $PSScriptRoot "BackupManager.ps1"
$script:RecoveryManagerPath = Join-Path $PSScriptRoot "RecoveryManager.ps1"

Import-Module $script:LoggerPath -Force
Import-Module $script:PlatformHelperPath -Force
Import-Module $script:ConfigPath -Force
Import-Module $script:ProcessManagerPath -Force
Import-Module $script:FileMonitorPath -Force
Import-Module $script:BackupManagerPath -Force
Import-Module $script:RecoveryManagerPath -Force

$script:Running = $false
$script:LastEventCheckTime = Get-Date

function Start-MainExecution {
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigFilePath
    )
    
    try {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  SillyTavern Corruption Guard" -ForegroundColor Cyan
        Write-Host "  Modular Architecture v1.0" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        
        Write-LogInfo "Phase 1: Initialization"
        
        if ([string]::IsNullOrEmpty($ConfigFilePath)) {
            $config = Initialize-Configuration
        } else {
            $config = Initialize-Configuration -ConfigFilePath $ConfigFilePath
        }
        
        if ($null -eq $config) {
            Write-LogError "Configuration initialization failed"
            return $false
        }
        
        $prereqsOk = Test-Prerequisites
        if (-not $prereqsOk) {
            Write-LogError "Prerequisites check failed"
            return $false
        }
        
        $mutexAcquired = Initialize-SingletonMutex
        if (-not $mutexAcquired) {
            Write-LogError "Failed to acquire singleton mutex - another instance may be running"
            return $false
        }
        
        Write-LogInfo "Phase 2: Component Setup"
        
        $process = Start-SillyTavern
        if ($null -eq $process) {
            Write-LogWarning "SillyTavern could not be started, but continuing monitoring..."
        }
        
        $monitoringStarted = Start-FileMonitoring
        if (-not $monitoringStarted) {
            Write-LogError "Failed to start file monitoring"
            Cleanup-Resources
            return $false
        }
        
        Invoke-BackupProcess
        
        $timerStarted = Start-BackupTimer
        if (-not $timerStarted) {
            Write-LogWarning "Failed to start backup timer, backups will not run automatically"
        }
        
        Write-LogSuccess "All components initialized successfully"
        Write-Host ""
        Write-LogInfo "Phase 3: Monitoring Active"
        Write-LogInfo "Press Ctrl+C to stop monitoring..."
        Write-Host ""
        
        $script:Running = $true
        $script:LastEventCheckTime = Get-Date
        
        try {
            while ($script:Running) {
                $event = Get-FileChangeEvent
                
                if ($null -ne $event) {
                    Handle-FileChangeEvent -Event $event
                }
                
                if (((Get-Date) - $script:LastEventCheckTime).TotalSeconds -gt 5) {
                    $processHealthy = Test-ProcessHealth
                    if (-not $processHealthy) {
                        Write-LogWarning "SillyTavern process is not running"
                    }
                    $script:LastEventCheckTime = Get-Date
                }
                
                Start-Sleep -Milliseconds 500
            }
        } catch {
            Write-LogError "Error in main loop: $($_.Exception.Message)"
        }
        
        Write-LogInfo "Phase 4: Cleanup"
        Cleanup-Resources
        
        Write-Host ""
        Write-LogSuccess "SillyTavern Corruption Guard stopped successfully"
        Write-Host ""
        
        return $true
        
    } catch {
        Write-LogError "Fatal error in main execution: $($_.Exception.Message)"
        Write-LogError $_.ScriptStackTrace
        Cleanup-Resources
        return $false
    }
}

function Handle-FileChangeEvent {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Event
    )
    
    try {
        $filePath = $Event.FullPath
        $eventType = $Event.EventType
        
        Write-LogDebug "File event: $eventType - $filePath"
        
        if ($eventType -eq "Changed") {
            Start-Sleep -Milliseconds 100
            
            $isCorrupted = Test-CorruptionCondition -SourceFile $filePath
            
            if ($isCorrupted) {
                Write-LogWarning "CORRUPTION DETECTED: $filePath"
                
                $recovered = Invoke-RecoveryProcess -CorruptedFile $filePath
                
                if ($recovered) {
                    Write-LogSuccess "File recovered successfully: $filePath"
                } else {
                    Write-LogError "File recovery failed: $filePath"
                }
            }
        } elseif ($eventType -eq "Created") {
            Write-LogInfo "New file detected: $filePath"
        } elseif ($eventType -eq "Renamed") {
            Write-LogInfo "File renamed: $($Event.OldFullPath) -> $filePath"
        }
        
    } catch {
        Write-LogError "Error handling file change event: $($_.Exception.Message)"
    }
}

function Cleanup-Resources {
    Write-LogInfo "Cleaning up resources..."
    
    try {
        Stop-BackupTimer
        Stop-FileMonitoring
        Release-SingletonMutex
        
        Write-LogSuccess "Resources cleaned up successfully"
        
    } catch {
        Write-LogWarning "Error during cleanup: $($_.Exception.Message)"
    }
}

function Stop-Monitoring {
    Write-LogInfo "Stopping monitoring..."
    $script:Running = $false
}

$script:CtrlCHandler = {
    Write-Host ""
    Write-LogWarning "Ctrl+C detected, stopping gracefully..."
    Stop-Monitoring
}

try {
    [Console]::TreatControlCAsInput = $false
    [Console]::add_CancelKeyPress($script:CtrlCHandler)
} catch {
    Write-LogDebug "Console handler not available in this environment"
}

if ($MyInvocation.InvocationName -ne '.') {
    $configPath = $null
    if ($args.Count -gt 0) {
        $configPath = $args[0]
    }
    
    $result = Start-MainExecution -ConfigFilePath $configPath
    
    if ($result) {
        exit 0
    } else {
        exit 1
    }
}
