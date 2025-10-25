$script:LoggerPath = Join-Path $PSScriptRoot "Common" "Logger.ps1"
$script:PlatformHelperPath = Join-Path $PSScriptRoot "Common" "PlatformHelper.ps1"
$script:ConfigPath = Join-Path $PSScriptRoot "Config.ps1"

Import-Module $script:LoggerPath -Force
Import-Module $script:PlatformHelperPath -Force
Import-Module $script:ConfigPath -Force

$script:BackupTimer = $null
$script:BackupInProgress = $false

function Invoke-BackupProcess {
    if ($script:BackupInProgress) {
        Write-LogDebug "Backup already in progress, skipping..."
        return
    }
    
    $script:BackupInProgress = $true
    
    try {
        Write-LogInfo "Starting backup process..."
        
        $vectorsPath = Get-ConfigurationValue -Key "VectorsRootPath"
        $backupConfig = Get-ConfigurationValue -Key "BackupConfig"
        
        $indexFiles = Get-ChildItem -Path $vectorsPath -Filter "index.json" -Recurse -File -ErrorAction SilentlyContinue
        
        if ($indexFiles.Count -eq 0) {
            Write-LogWarning "No index.json files found in $vectorsPath"
            return
        }
        
        $backedUp = 0
        $skipped = 0
        $failed = 0
        
        foreach ($file in $indexFiles) {
            $result = Invoke-LazyBackupEvaluation -SourceFile $file.FullName
            
            switch ($result) {
                "Created" { $backedUp++; break }
                "Updated" { $backedUp++; break }
                "Skipped" { $skipped++; break }
                "Failed"  { $failed++; break }
            }
        }
        
        Write-LogSuccess "Backup process completed: $backedUp backed up, $skipped skipped, $failed failed"
        
    } catch {
        Write-LogError "Backup process failed: $($_.Exception.Message)"
    } finally {
        $script:BackupInProgress = $false
    }
}

function Invoke-LazyBackupEvaluation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceFile
    )
    
    try {
        $backupFile = "$SourceFile.bak"
        
        if (-not (Test-Path $SourceFile)) {
            Write-LogWarning "Source file not found: $SourceFile"
            return "Failed"
        }
        
        $sourceSize = (Get-Item $SourceFile).Length
        
        if (-not (Test-Path $backupFile)) {
            if (Test-JsonValidity -FilePath $SourceFile) {
                Copy-FileWithVerification -SourcePath $SourceFile -DestinationPath $backupFile
                Write-LogInfo "Created backup for: $SourceFile"
                return "Created"
            } else {
                Write-LogWarning "Source file has invalid JSON, backup not created: $SourceFile"
                return "Failed"
            }
        }
        
        $backupSize = (Get-Item $backupFile).Length
        
        if ($sourceSize -le $backupSize) {
            Write-LogDebug "Backup skipped (source <= backup): $SourceFile"
            return "Skipped"
        }
        
        if (Test-JsonValidity -FilePath $SourceFile) {
            Copy-FileWithVerification -SourcePath $SourceFile -DestinationPath $backupFile
            Write-LogInfo "Updated backup for: $SourceFile (size: $backupSize -> $sourceSize)"
            return "Updated"
        } else {
            Write-LogWarning "Source file larger but invalid JSON, backup preserved: $SourceFile"
            return "Failed"
        }
        
    } catch {
        Write-LogError "Lazy backup evaluation failed for $SourceFile : $($_.Exception.Message)"
        return "Failed"
    }
}

function Test-JsonValidity {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            return $false
        }
        
        $content = Get-Content $FilePath -Raw -ErrorAction Stop
        
        if ([string]::IsNullOrWhiteSpace($content)) {
            return $false
        }
        
        $null = $content | ConvertFrom-Json -ErrorAction Stop
        
        return $true
        
    } catch {
        Write-LogDebug "JSON validation failed for $FilePath : $($_.Exception.Message)"
        return $false
    }
}

function Copy-FileWithVerification {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath
    )
    
    try {
        $backupConfig = Get-ConfigurationValue -Key "BackupConfig"
        $maxRetries = $backupConfig.MaxRetries
        $retryDelay = $backupConfig.RetryDelaySeconds
        
        for ($i = 0; $i -lt $maxRetries; $i++) {
            try {
                Copy-Item -Path $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
                
                $sourceSize = (Get-Item $SourcePath).Length
                $destSize = (Get-Item $DestinationPath).Length
                
                if ($sourceSize -eq $destSize) {
                    return $true
                }
                
                Write-LogWarning "File size mismatch after copy, retrying... (Attempt $($i + 1)/$maxRetries)"
                
            } catch {
                Write-LogWarning "Copy failed, retrying... (Attempt $($i + 1)/$maxRetries): $($_.Exception.Message)"
            }
            
            if ($i -lt ($maxRetries - 1)) {
                Start-Sleep -Seconds $retryDelay
            }
        }
        
        Write-LogError "Failed to copy file after $maxRetries attempts"
        return $false
        
    } catch {
        Write-LogError "Copy with verification failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-BackupStatus {
    try {
        $vectorsPath = Get-ConfigurationValue -Key "VectorsRootPath"
        $indexFiles = Get-ChildItem -Path $vectorsPath -Filter "index.json" -Recurse -File -ErrorAction SilentlyContinue
        
        $status = @{
            TotalFiles = $indexFiles.Count
            BackedUp = 0
            NotBackedUp = 0
            Files = @()
        }
        
        foreach ($file in $indexFiles) {
            $backupFile = "$($file.FullName).bak"
            $hasBackup = Test-Path $backupFile
            
            if ($hasBackup) {
                $status.BackedUp++
            } else {
                $status.NotBackedUp++
            }
            
            $status.Files += @{
                Path = $file.FullName
                Size = $file.Length
                HasBackup = $hasBackup
                BackupSize = if ($hasBackup) { (Get-Item $backupFile).Length } else { 0 }
            }
        }
        
        return $status
        
    } catch {
        Write-LogError "Failed to get backup status: $($_.Exception.Message)"
        return $null
    }
}

function Start-BackupTimer {
    try {
        $intervalSeconds = Get-ConfigurationValue -Key "BackupIntervalSeconds"
        
        $script:BackupTimer = New-Object System.Timers.Timer
        $script:BackupTimer.Interval = $intervalSeconds * 1000
        $script:BackupTimer.AutoReset = $true
        
        Register-ObjectEvent -InputObject $script:BackupTimer -EventName "Elapsed" -Action {
            Invoke-BackupProcess
        } -SourceIdentifier "BackupTimer" | Out-Null
        
        $script:BackupTimer.Start()
        
        Write-LogSuccess "Backup timer started (interval: $intervalSeconds seconds)"
        return $true
        
    } catch {
        Write-LogError "Failed to start backup timer: $($_.Exception.Message)"
        return $false
    }
}

function Stop-BackupTimer {
    try {
        if ($null -ne $script:BackupTimer) {
            $script:BackupTimer.Stop()
            $script:BackupTimer.Dispose()
            $script:BackupTimer = $null
        }
        
        Unregister-Event -SourceIdentifier "BackupTimer" -ErrorAction SilentlyContinue
        
        Write-LogInfo "Backup timer stopped"
        return $true
        
    } catch {
        Write-LogError "Failed to stop backup timer: $($_.Exception.Message)"
        return $false
    }
}
