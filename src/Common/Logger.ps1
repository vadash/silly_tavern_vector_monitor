function Write-LogMessage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Info", "Warning", "Error", "Success", "Debug")]
        [string]$Level = "Info",
        
        [Parameter(Mandatory=$false)]
        [switch]$NoTimestamp
    )
    
    $timestamp = if (-not $NoTimestamp) {
        "[{0:yyyy-MM-dd HH:mm:ss}] " -f (Get-Date)
    } else {
        ""
    }
    
    $colorMap = @{
        "Info"    = "Cyan"
        "Warning" = "Yellow"
        "Error"   = "Red"
        "Success" = "Green"
        "Debug"   = "Gray"
    }
    
    $color = $colorMap[$Level]
    $prefix = "[$Level]"
    
    Write-Host "${timestamp}${prefix} ${Message}" -ForegroundColor $color
}

function Write-LogInfo {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "Info"
}

function Write-LogWarning {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "Warning"
}

function Write-LogError {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "Error"
}

function Write-LogSuccess {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "Success"
}

function Write-LogDebug {
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "Debug"
}
