$script:LoggerPath = Join-Path $PSScriptRoot "Common\Logger.ps1"
$script:ConfigPath = Join-Path $PSScriptRoot "Config.ps1"
$script:ProcessManagerPath = Join-Path $PSScriptRoot "ProcessManager.ps1"
$script:BackupManagerPath = Join-Path $PSScriptRoot "BackupManager.ps1"

Import-Module $script:LoggerPath -Force
Import-Module $script:ConfigPath -Force
Import-Module $script:ProcessManagerPath -Force
Import-Module $script:BackupManagerPath -Force

$script:RecoveryAttempts = @{}

function Test-CorruptionCondition {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceFile
    )
    
    try {
        $backupFile = "$SourceFile.bak"
        
        if (-not (Test-Path $SourceFile)) {
            Write-LogDebug "Source file not found: $SourceFile"
            return $false
        }
        
        if (-not (Test-Path $backupFile)) {
            Write-LogDebug "Backup file not found: $backupFile"
            return $false
        }
        
        $sourceSize = (Get-Item $SourceFile).Length
        $backupSize = (Get-Item $backupFile).Length
        
        $thresholdMB = Get-ConfigurationValue -Key "CorruptionThresholdMB"
        $dropRatio = Get-ConfigurationValue -Key "CorruptionDropRatio"
        
        $condition1 = $backupSize -gt ($thresholdMB * 1MB)
        $condition2 = $sourceSize -lt ($backupSize * $dropRatio)
        
        $isCorrupted = $condition1 -and $condition2
        
        if ($isCorrupted) {
            Write-LogWarning "Corruption detected: $SourceFile (backup: $backupSize bytes, source: $sourceSize bytes)"
        }
        
        return $isCorrupted
        
    } catch {
        Write-LogError "Failed to test corruption condition: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-RecoveryProcess {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CorruptedFile
    )
    
    try {
        $recoveryConfig = Get-ConfigurationValue -Key "RecoveryConfig"
        $maxAttempts = $recoveryConfig.MaxRecoveryAttempts
        
        if (-not $script:RecoveryAttempts.ContainsKey($CorruptedFile)) {
            $script:RecoveryAttempts[$CorruptedFile] = 0
        }
        
        $script:RecoveryAttempts[$CorruptedFile]++
        $attemptNumber = $script:RecoveryAttempts[$CorruptedFile]
        
        if ($attemptNumber -gt $maxAttempts) {
            Write-LogError "Maximum recovery attempts ($maxAttempts) exceeded for: $CorruptedFile"
            return $false
        }
        
        Write-LogWarning "Starting recovery process for: $CorruptedFile (Attempt $attemptNumber/$maxAttempts)"
        
        Write-LogInfo "Step 1: Terminating SillyTavern..."
        $stopped = Stop-SillyTavern -TimeoutSeconds $recoveryConfig.ProcessWaitTimeoutSeconds
        
        if (-not $stopped) {
            Write-LogWarning "Force stopping SillyTavern..."
            $process = Get-SillyTavernProcess
            if ($null -ne $process) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
        }
        
        Write-LogInfo "Step 2: Restoring from backup..."
        $restored = Restore-FromBackup -CorruptedFile $CorruptedFile
        
        if (-not $restored) {
            Write-LogError "Failed to restore file from backup"
            return $false
        }
        
        Start-Sleep -Seconds 2
        
        Write-LogInfo "Step 3: Restarting SillyTavern..."
        $process = Start-SillyTavern
        
        if ($null -eq $process) {
            Write-LogError "Failed to restart SillyTavern"
            return $false
        }
        
        Start-Sleep -Seconds 3
        
        Write-LogInfo "Step 4: Verifying recovery..."
        $verified = Verify-Recovery -FilePath $CorruptedFile
        
        if ($verified) {
            Write-LogSuccess "Recovery completed successfully for: $CorruptedFile"
            $script:RecoveryAttempts[$CorruptedFile] = 0
            return $true
        } else {
            Write-LogWarning "Recovery verification failed for: $CorruptedFile"
            return $false
        }
        
    } catch {
        Write-LogError "Recovery process failed: $($_.Exception.Message)"
        return $false
    }
}

function Restore-FromBackup {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CorruptedFile
    )
    
    try {
        $backupFile = "$CorruptedFile.bak"
        
        if (-not (Test-Path $backupFile)) {
            Write-LogError "Backup file not found: $backupFile"
            return $false
        }
        
        if (-not (Test-JsonValidity -FilePath $backupFile)) {
            Write-LogError "Backup file has invalid JSON: $backupFile"
            return $false
        }
        
        Copy-Item -Path $backupFile -Destination $CorruptedFile -Force -ErrorAction Stop
        
        Write-LogSuccess "File restored from backup: $CorruptedFile"
        return $true
        
    } catch {
        Write-LogError "Failed to restore from backup: $($_.Exception.Message)"
        return $false
    }
}

function Verify-Recovery {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            Write-LogError "Recovered file not found: $FilePath"
            return $false
        }
        
        if (-not (Test-JsonValidity -FilePath $FilePath)) {
            Write-LogError "Recovered file has invalid JSON: $FilePath"
            return $false
        }
        
        $fileSize = (Get-Item $FilePath).Length
        $backupSize = (Get-Item "$FilePath.bak").Length
        
        if ($fileSize -ne $backupSize) {
            Write-LogWarning "Recovered file size differs from backup (file: $fileSize, backup: $backupSize)"
        }
        
        $thresholdMB = Get-ConfigurationValue -Key "CorruptionThresholdMB"
        if ($fileSize -gt ($thresholdMB * 1MB)) {
            Write-LogSuccess "Recovery verified: file size is acceptable ($fileSize bytes)"
            return $true
        } else {
            Write-LogWarning "Recovery verification: file size is below threshold ($fileSize bytes)"
            return $true
        }
        
    } catch {
        Write-LogError "Failed to verify recovery: $($_.Exception.Message)"
        return $false
    }
}

function Reset-RecoveryAttempts {
    param(
        [Parameter(Mandatory=$false)]
        [string]$FilePath
    )
    
    if ([string]::IsNullOrEmpty($FilePath)) {
        $script:RecoveryAttempts = @{}
        Write-LogInfo "All recovery attempt counters reset"
    } elseif ($script:RecoveryAttempts.ContainsKey($FilePath)) {
        $script:RecoveryAttempts[$FilePath] = 0
        Write-LogInfo "Recovery attempt counter reset for: $FilePath"
    }
}

function Get-RecoveryAttempts {
    param(
        [Parameter(Mandatory=$false)]
        [string]$FilePath
    )
    
    if ([string]::IsNullOrEmpty($FilePath)) {
        return $script:RecoveryAttempts
    }
    
    if ($script:RecoveryAttempts.ContainsKey($FilePath)) {
        return $script:RecoveryAttempts[$FilePath]
    }
    
    return 0
}
