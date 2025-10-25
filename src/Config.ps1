$script:LoggerPath = Join-Path $PSScriptRoot "Common" "Logger.ps1"
$script:PlatformHelperPath = Join-Path $PSScriptRoot "Common" "PlatformHelper.ps1"
Import-Module $script:LoggerPath -Force
Import-Module $script:PlatformHelperPath -Force

$script:SillyTavernConfig = $null
$script:ConfigMutex = $null

function Initialize-Configuration {
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigFilePath = (Join-Path (Split-Path $PSScriptRoot -Parent) "config" "settings.json")
    )
    
    Write-LogInfo "Initializing configuration..."
    
    try {
        if (Test-Path $ConfigFilePath) {
            $configJson = Get-Content $ConfigFilePath -Raw | ConvertFrom-Json
            
            $script:SillyTavernConfig = @{
                SillyTavernExecutablePath = $configJson.sillyTavern.executablePath
                SillyTavernProcessName = $configJson.sillyTavern.processName
                VectorsRootPath = $configJson.monitoring.vectorsRootPath
                BackupIntervalSeconds = $configJson.monitoring.backupIntervalSeconds
                CorruptionThresholdMB = $configJson.monitoring.corruptionThresholdMB
                CorruptionDropRatio = $configJson.monitoring.corruptionDropRatio
                
                MutexName = "SillyTavernCorruptionGuard"
                LogLevel = $configJson.logging.level
                
                FileMonitorConfig = @{
                    Filter = "index.json"
                    Events = @("Changed", "Created", "Renamed")
                    BufferSize = 8192
                }
                
                BackupConfig = @{
                    LazyEvaluation = $true
                    MaxRetries = 3
                    RetryDelaySeconds = 5
                }
                
                RecoveryConfig = @{
                    MaxRecoveryAttempts = 3
                    ProcessWaitTimeoutSeconds = 30
                }
            }
        } else {
            # Platform-specific defaults
            $defaultBasePath = Get-DefaultSillyTavernPath
            $execExtension = Get-ExecutableExtension
            
            $script:SillyTavernConfig = @{
                SillyTavernExecutablePath = Join-Path $defaultBasePath "start$execExtension"
                SillyTavernProcessName = "node"
                VectorsRootPath = Get-DefaultVectorsPath
                BackupIntervalSeconds = 60
                CorruptionThresholdMB = 1
                CorruptionDropRatio = 0.333
                
                MutexName = "SillyTavernCorruptionGuard"
                LogLevel = "Info"
                
                FileMonitorConfig = @{
                    Filter = "index.json"
                    Events = @("Changed", "Created", "Renamed")
                    BufferSize = 8192
                }
                
                BackupConfig = @{
                    LazyEvaluation = $true
                    MaxRetries = 3
                    RetryDelaySeconds = 5
                }
                
                RecoveryConfig = @{
                    MaxRecoveryAttempts = 3
                    ProcessWaitTimeoutSeconds = 30
                }
            }
            Write-LogWarning "Configuration file not found at '$ConfigFilePath'. Using default configuration."
        }
        
        if (-not (Test-Configuration)) {
            throw "Configuration validation failed"
        }
        
        Write-LogSuccess "Configuration initialized successfully"
        return $script:SillyTavernConfig
        
    } catch {
        Write-LogError "Failed to initialize configuration: $($_.Exception.Message)"
        throw
    }
}

function Test-Configuration {
    if ($null -eq $script:SillyTavernConfig) {
        Write-LogError "Configuration not initialized"
        return $false
    }
    
    $requiredKeys = @(
        "SillyTavernExecutablePath",
        "SillyTavernProcessName",
        "VectorsRootPath",
        "BackupIntervalSeconds",
        "CorruptionThresholdMB",
        "CorruptionDropRatio"
    )
    
    foreach ($key in $requiredKeys) {
        if (-not $script:SillyTavernConfig.ContainsKey($key)) {
            Write-LogError "Missing required configuration key: $key"
            return $false
        }
    }
    
    return $true
}

function Test-Prerequisites {
    Write-LogInfo "Testing system prerequisites..."
    
    $vectorsPath = $script:SillyTavernConfig.VectorsRootPath
    if (-not (Test-Path $vectorsPath)) {
        Write-LogError "Vectors root path does not exist: $vectorsPath"
        return $false
    }
    
    $executablePath = $script:SillyTavernConfig.SillyTavernExecutablePath
    if (-not (Test-Path $executablePath)) {
        Write-LogWarning "SillyTavern executable not found at: $executablePath"
    }
    
    Write-LogSuccess "Prerequisites validated successfully"
    return $true
}

function Get-ConfigurationValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key
    )
    
    if ($null -eq $script:SillyTavernConfig) {
        Write-LogError "Configuration not initialized"
        return $null
    }
    
    if ($script:SillyTavernConfig.ContainsKey($Key)) {
        return $script:SillyTavernConfig[$Key]
    }
    
    Write-LogWarning "Configuration key not found: $Key"
    return $null
}

function Initialize-SingletonMutex {
    Write-LogInfo "Initializing singleton mutex..."
    
    try {
        $mutexName = $script:SillyTavernConfig.MutexName
        $script:ConfigMutex = New-CrossPlatformMutex -Name $mutexName
        
        if (-not (Enter-CrossPlatformMutex -MutexObject $script:ConfigMutex -TimeoutMs 0)) {
            Write-LogError "Another instance of SillyTavern Corruption Guard is already running"
            return $false
        }
        
        Write-LogSuccess "Singleton mutex acquired successfully"
        return $true
        
    } catch {
        Write-LogError "Failed to initialize mutex: $($_.Exception.Message)"
        return $false
    }
}

function Release-SingletonMutex {
    if ($null -ne $script:ConfigMutex) {
        try {
            Dispose-CrossPlatformMutex -MutexObject $script:ConfigMutex
            Write-LogInfo "Singleton mutex released"
        } catch {
            Write-LogWarning "Failed to release mutex: $($_.Exception.Message)"
        }
    }
}
