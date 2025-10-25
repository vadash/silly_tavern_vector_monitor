$script:LoggerPath = Join-Path $PSScriptRoot "Common" "Logger.ps1"
$script:PlatformHelperPath = Join-Path $PSScriptRoot "Common" "PlatformHelper.ps1"
$script:ConfigPath = Join-Path $PSScriptRoot "Config.ps1"

Import-Module $script:LoggerPath -Force
Import-Module $script:PlatformHelperPath -Force
Import-Module $script:ConfigPath -Force

$script:FileWatcher = $null
$script:MonitoredFiles = @{}
$script:FileChangeEvents = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()

function Start-FileMonitoring {
    Write-LogInfo "Starting file monitoring..."
    
    try {
        $vectorsPath = Get-ConfigurationValue -Key "VectorsRootPath"
        $fileMonitorConfig = Get-ConfigurationValue -Key "FileMonitorConfig"
        
        if (-not (Test-Path $vectorsPath)) {
            Write-LogError "Vectors root path does not exist: $vectorsPath"
            return $false
        }
        
        $script:FileWatcher = New-Object System.IO.FileSystemWatcher
        $script:FileWatcher.Path = $vectorsPath
        $script:FileWatcher.Filter = $fileMonitorConfig.Filter
        $script:FileWatcher.IncludeSubdirectories = $true
        $script:FileWatcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor 
                                           [System.IO.NotifyFilters]::Size -bor 
                                           [System.IO.NotifyFilters]::LastWrite
        $script:FileWatcher.InternalBufferSize = $fileMonitorConfig.BufferSize
        
        $eventQueue = $script:FileChangeEvents
        
        $onChanged = {
            param($sender, $e)
            $eventData = @{
                EventType = "Changed"
                FullPath = $e.FullPath
                ChangeType = $e.ChangeType
                Timestamp = Get-Date
            }
            $Event.MessageData.Enqueue($eventData)
        }
        
        $onCreated = {
            param($sender, $e)
            $eventData = @{
                EventType = "Created"
                FullPath = $e.FullPath
                ChangeType = $e.ChangeType
                Timestamp = Get-Date
            }
            $Event.MessageData.Enqueue($eventData)
        }
        
        $onRenamed = {
            param($sender, $e)
            $eventData = @{
                EventType = "Renamed"
                FullPath = $e.FullPath
                OldFullPath = $e.OldFullPath
                ChangeType = $e.ChangeType
                Timestamp = Get-Date
            }
            $Event.MessageData.Enqueue($eventData)
        }
        
        Register-ObjectEvent -InputObject $script:FileWatcher -EventName "Changed" -Action $onChanged -SourceIdentifier "FileChanged" -MessageData $eventQueue | Out-Null
        Register-ObjectEvent -InputObject $script:FileWatcher -EventName "Created" -Action $onCreated -SourceIdentifier "FileCreated" -MessageData $eventQueue | Out-Null
        Register-ObjectEvent -InputObject $script:FileWatcher -EventName "Renamed" -Action $onRenamed -SourceIdentifier "FileRenamed" -MessageData $eventQueue | Out-Null
        
        $script:FileWatcher.EnableRaisingEvents = $true
        
        Initialize-MonitoredFiles
        
        Write-LogSuccess "File monitoring started successfully"
        return $true
        
    } catch {
        Write-LogError "Failed to start file monitoring: $($_.Exception.Message)"
        return $false
    }
}

function Stop-FileMonitoring {
    Write-LogInfo "Stopping file monitoring..."
    
    try {
        if ($null -ne $script:FileWatcher) {
            $script:FileWatcher.EnableRaisingEvents = $false
            $script:FileWatcher.Dispose()
            $script:FileWatcher = $null
        }
        
        Unregister-Event -SourceIdentifier "FileChanged" -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier "FileCreated" -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier "FileRenamed" -ErrorAction SilentlyContinue
        
        Write-LogSuccess "File monitoring stopped successfully"
        return $true
        
    } catch {
        Write-LogError "Failed to stop file monitoring: $($_.Exception.Message)"
        return $false
    }
}

function Initialize-MonitoredFiles {
    Write-LogInfo "Discovering monitored files..."
    
    try {
        $vectorsPath = Get-ConfigurationValue -Key "VectorsRootPath"
        $fileMonitorConfig = Get-ConfigurationValue -Key "FileMonitorConfig"
        
        $files = Get-ChildItem -Path $vectorsPath -Filter $fileMonitorConfig.Filter -Recurse -File -ErrorAction SilentlyContinue
        
        $script:MonitoredFiles = @{}
        foreach ($file in $files) {
            $script:MonitoredFiles[$file.FullName] = @{
                Path = $file.FullName
                Size = $file.Length
                LastWriteTime = $file.LastWriteTime
                DiscoveredAt = Get-Date
            }
        }
        
        Write-LogSuccess "Discovered $($script:MonitoredFiles.Count) monitored files"
        
    } catch {
        Write-LogError "Failed to discover monitored files: $($_.Exception.Message)"
    }
}

function Get-MonitoredFiles {
    return $script:MonitoredFiles.Values
}

function Get-FileChangeEvent {
    $event = $null
    if ($script:FileChangeEvents.TryDequeue([ref]$event)) {
        return $event
    }
    return $null
}

function Test-FileMonitoringActive {
    if ($null -eq $script:FileWatcher) {
        return $false
    }
    
    return $script:FileWatcher.EnableRaisingEvents
}
