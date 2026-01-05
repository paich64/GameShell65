#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory=$false)]
    [string]$InstallationPath = "",
    
    [Parameter(Mandatory=$false)]
    [string]$TempDirectory = ""
)

# Configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Initialize paths based on parameters - will be set after parameter logic
$LogDirectory = ""
$LogFile = ""

$Global:LogStartTime = Get-Date

# Function to detect main tree root (Arborescence_Principale)
function Get-MainTreeRoot {
    Write-Host "Detecting main tree root..." -ForegroundColor Yellow
    
    try {
        # Script is located in: Arborescence_Principale\install\scripts\windows
        $scriptPath = $PSScriptRoot
        
        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
        }
        
        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            throw "Unable to determine script location"
        }
        
        # Go up 3 levels: windows -> scripts -> install -> Arborescence_Principale
        $installDir = Split-Path $scriptPath -Parent  # scripts
        $installDir = Split-Path $installDir -Parent  # install
        $mainTreeRoot = Split-Path $installDir -Parent  # Arborescence_Principale
        
        Write-Host "Main tree root detected: $mainTreeRoot" -ForegroundColor Green
        return $mainTreeRoot
    }
    catch {
        Write-Host "Error detecting main tree root: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Function to write to log file
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",  # INFO, SUCCESS, WARNING, ERROR, DEBUG
        [string]$Component = "MAIN"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"
    
    try {
        Add-Content -Path $Script:LogFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        # If logging fails, continue execution but note it
        Write-Host "LOG ERROR: Could not write to log file" -ForegroundColor Red
    }
}

# Function to write colored messages (now with logging)
function Write-ColoredOutput {
    param(
        [string]$Message,
        [string]$Color = "White",
        [string]$LogLevel = "INFO",
        [string]$Component = "MAIN"
    )
    
    Write-Host $Message -ForegroundColor $Color
    
    # Map colors to log levels if not explicitly provided
    if ($LogLevel -eq "INFO") {
        switch ($Color) {
            "Green" { $LogLevel = "SUCCESS" }
            "Yellow" { $LogLevel = "WARNING" }
            "Red" { $LogLevel = "ERROR" }
            "Cyan" { $LogLevel = "INFO" }
            "Magenta" { $LogLevel = "INFO" }
            "Gray" { $LogLevel = "DEBUG" }
            default { $LogLevel = "INFO" }
        }
    }
    
    Write-Log -Message $Message -Level $LogLevel -Component $Component
}

# Function to log function entry/exit
function Write-FunctionLog {
    param(
        [string]$FunctionName,
        [string]$Action,  # ENTER, EXIT, ERROR
        [string]$Details = ""
    )
    
    $message = "$Action $FunctionName"
    if ($Details) {
        $message += " - $Details"
    }
    
    Write-Log -Message $message -Level "DEBUG" -Component $FunctionName
}

# Function to create required directories
function New-InstallDirectory {
    param([string]$Path)
    
    Write-FunctionLog -FunctionName "New-InstallDirectory" -Action "ENTER" -Details "Path: $Path"
    
    try {
        if (-not (Test-Path $Path)) {
            Write-ColoredOutput "Creating directory: $Path" "Yellow" "INFO" "New-InstallDirectory"
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Log -Message "Directory created successfully: $Path" -Level "SUCCESS" -Component "New-InstallDirectory"
        } else {
            Write-Log -Message "Directory already exists: $Path" -Level "INFO" -Component "New-InstallDirectory"
        }
        Write-FunctionLog -FunctionName "New-InstallDirectory" -Action "EXIT" -Details "Success"
    }
    catch {
        Write-Log -Message "Failed to create directory: $Path - Error: $($_.Exception.Message)" -Level "ERROR" -Component "New-InstallDirectory"
        Write-FunctionLog -FunctionName "New-InstallDirectory" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to get and validate temporary directory
function Get-TempDirectory {
    param(
        [string]$UserTempDir,
        [string]$BaseInstallPath
    )
    
    Write-FunctionLog -FunctionName "Get-TempDirectory" -Action "ENTER" -Details "UserTempDir: $UserTempDir, BaseInstallPath: $BaseInstallPath"
    
    try {
        if ([string]::IsNullOrWhiteSpace($UserTempDir)) {
            # No TempDirectory parameter: use BaseInstallPath
            $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\m65tools"
            Write-ColoredOutput "Using installation-based temporary directory: $tempDir" "Cyan" "INFO" "Get-TempDirectory"
        }
        else {
            # User provided temp directory
            $tempDir = Join-Path $UserTempDir "GameShell65_temp_Install\m65tools"
            Write-ColoredOutput "Using custom temporary directory: $tempDir" "Cyan" "INFO" "Get-TempDirectory"
            
            # Validate that parent directory exists or can be created
            $parentDir = Split-Path $tempDir -Parent
            if ($parentDir -and -not (Test-Path $parentDir)) {
                try {
                    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                    Write-ColoredOutput "Created parent directory: $parentDir" "Yellow" "SUCCESS" "Get-TempDirectory"
                }
                catch {
                    Write-ColoredOutput "Warning: Cannot create parent directory: $parentDir" "Yellow" "WARNING" "Get-TempDirectory"
                    Write-ColoredOutput "Falling back to installation-based temporary directory" "Yellow" "WARNING" "Get-TempDirectory"
                    $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\m65tools"
                }
            }
        }
        
        # Ensure the temp directory path is not too long to avoid path issues
        if ($tempDir.Length -gt 100) {
            Write-ColoredOutput "Warning: Temporary directory path is long ($($tempDir.Length) chars). This may cause issues with some files." "Yellow" "WARNING" "Get-TempDirectory"
            Write-ColoredOutput "Consider using a shorter path like 'C:\Temp\M65'" "Yellow" "WARNING" "Get-TempDirectory"
        }
        
        Write-Log -Message "Temporary directory determined: $tempDir" -Level "SUCCESS" -Component "Get-TempDirectory"
        Write-FunctionLog -FunctionName "Get-TempDirectory" -Action "EXIT" -Details "TempDir: $tempDir"
        return $tempDir
    }
    catch {
        Write-Log -Message "Error determining temporary directory: $($_.Exception.Message)" -Level "ERROR" -Component "Get-TempDirectory"
        Write-FunctionLog -FunctionName "Get-TempDirectory" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to download a file with progress
function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    Write-FunctionLog -FunctionName "Download-File" -Action "ENTER" -Details "URL: $Url, OutputPath: $OutputPath"
    
    Write-ColoredOutput "Downloading from: $Url" "Cyan" "INFO" "Download-File"
    Write-ColoredOutput "Destination: $OutputPath" "Cyan" "INFO" "Download-File"
    
    try {
        $downloadStartTime = Get-Date
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
        $downloadEndTime = Get-Date
        $downloadDuration = ($downloadEndTime - $downloadStartTime).TotalSeconds
        
        # Verify download
        if (Test-Path $OutputPath) {
            $fileSize = (Get-Item $OutputPath).Length
            Write-ColoredOutput "Download completed successfully" "Green" "SUCCESS" "Download-File"
            Write-Log -Message "Download completed - Size: $fileSize bytes, Duration: $([math]::Round($downloadDuration, 2)) seconds" -Level "SUCCESS" -Component "Download-File"
            Write-FunctionLog -FunctionName "Download-File" -Action "EXIT" -Details "Success"
        } else {
            throw "Downloaded file not found after completion"
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $errorMsg = "Download error: $errorMessage"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Download-File"
        Write-Log $errorMsg -Level "ERROR" -Component "Download-File"
        Write-FunctionLog -FunctionName "Download-File" -Action "ERROR" -Details $errorMessage
        throw
    }
}

# Function to get MEGA65 Tools from Jenkins CI
function Get-Mega65ToolsFromJenkins {
    Write-FunctionLog -FunctionName "Get-Mega65ToolsFromJenkins" -Action "ENTER"
    
    Write-ColoredOutput "Checking MEGA65 Jenkins CI for latest development build..." "Yellow" "INFO" "Get-Mega65ToolsFromJenkins"
    
    try {
        # Jenkins URLs
        $jenkinsBaseUrl = "https://builder.mega65.org/job/mega65-tools/job/development"
        $jenkinsApiUrl = "$jenkinsBaseUrl/lastSuccessfulBuild/api/json"
        
        Write-ColoredOutput "Querying Jenkins API: $jenkinsApiUrl" "Cyan" "INFO" "Get-Mega65ToolsFromJenkins"
        Write-Log -Message "Querying Jenkins API: $jenkinsApiUrl" -Level "INFO" -Component "Get-Mega65ToolsFromJenkins"
        
        # Get the latest successful build info
        $buildInfo = Invoke-RestMethod -Uri $jenkinsApiUrl -UseBasicParsing -TimeoutSec 30
        
        if (-not $buildInfo -or -not $buildInfo.number) {
            $errorMsg = "Invalid response from Jenkins API"
            Write-Log $errorMsg -Level "ERROR" -Component "Get-Mega65ToolsFromJenkins"
            throw $errorMsg
        }
        
        $buildNumber = $buildInfo.number
        $buildUrl = $buildInfo.url
        $timestamp = [DateTimeOffset]::FromUnixTimeMilliseconds($buildInfo.timestamp).ToString("yyyy-MM-dd HH:mm:ss")
        
        Write-ColoredOutput "Latest successful build: #$buildNumber" "Green" "SUCCESS" "Get-Mega65ToolsFromJenkins"
        Write-ColoredOutput "Build timestamp: $timestamp" "Green" "SUCCESS" "Get-Mega65ToolsFromJenkins"
        Write-ColoredOutput "Build URL: $buildUrl" "Cyan" "INFO" "Get-Mega65ToolsFromJenkins"
        
        Write-Log -Message "Latest build found: #$buildNumber, timestamp: $timestamp" -Level "SUCCESS" -Component "Get-Mega65ToolsFromJenkins"
        
        # Look for artifacts
        $artifacts = $buildInfo.artifacts
        if (-not $artifacts -or $artifacts.Count -eq 0) {
            $errorMsg = "No artifacts found in the latest build"
            Write-Log $errorMsg -Level "ERROR" -Component "Get-Mega65ToolsFromJenkins"
            throw $errorMsg
        }
        
        Write-ColoredOutput "Found $($artifacts.Count) artifacts in build" "Cyan" "INFO" "Get-Mega65ToolsFromJenkins"
        Write-ColoredOutput "Available artifacts:" "Yellow" "INFO" "Get-Mega65ToolsFromJenkins"
        Write-Log -Message "Found $($artifacts.Count) artifacts in build" -Level "INFO" -Component "Get-Mega65ToolsFromJenkins"
        
        foreach ($artifact in $artifacts) {
            Write-ColoredOutput "  - $($artifact.fileName) (path: $($artifact.relativePath))" "Yellow" "DEBUG" "Get-Mega65ToolsFromJenkins"
            Write-Log -Message "Artifact: $($artifact.fileName), path: $($artifact.relativePath)" -Level "DEBUG" -Component "Get-Mega65ToolsFromJenkins"
        }
        
        # Find Windows 7z artifact with more specific filtering
        $windowsArtifact = $artifacts | Where-Object {
            # Look for patterns that specifically indicate Windows builds
            ($_.fileName -like "*windows*.7z") -or
            ($_.fileName -like "*win64*.7z") -or
            ($_.fileName -like "*win32*.7z") -or
            ($_.fileName -like "*mingw64*.7z") -or
            ($_.relativePath -like "*windows*" -and $_.fileName -like "*.7z") -or
            ($_.relativePath -like "*win*" -and $_.fileName -like "*.7z")
        } | Where-Object {
            # Explicitly exclude Linux patterns
            $_.fileName -notlike "*linux*" -and 
            $_.fileName -notlike "*ubuntu*" -and
            $_.relativePath -notlike "*linux*" -and
            $_.relativePath -notlike "*ubuntu*"
        } | Select-Object -First 1
        
        if (-not $windowsArtifact) {
            # Try alternative search - look for any 7z that doesn't explicitly mention linux
            Write-ColoredOutput "No explicitly Windows-named artifact found, trying broader search..." "Yellow" "WARNING" "Get-Mega65ToolsFromJenkins"
            Write-Log -Message "No explicitly Windows-named artifact found, trying broader search" -Level "WARNING" -Component "Get-Mega65ToolsFromJenkins"
            
            $windowsArtifact = $artifacts | Where-Object {
                $_.fileName -like "*.7z" -and
                $_.fileName -notlike "*linux*" -and
                $_.fileName -notlike "*ubuntu*" -and
                $_.fileName -notlike "*macos*" -and
                $_.fileName -notlike "*darwin*"
            } | Sort-Object fileName | Select-Object -First 1
        }
        
        if (-not $windowsArtifact) {
            # Last resort - look for any 7z file and let user know
            Write-ColoredOutput "No clearly identified Windows artifact, checking all 7z files..." "Yellow" "WARNING" "Get-Mega65ToolsFromJenkins"
            Write-Log -Message "No clearly identified Windows artifact, checking all 7z files" -Level "WARNING" -Component "Get-Mega65ToolsFromJenkins"
            
            $possibleArtifacts = $artifacts | Where-Object { $_.fileName -like "*.7z" }
            
            if ($possibleArtifacts.Count -gt 0) {
                Write-ColoredOutput "Found $($possibleArtifacts.Count) 7z file(s):" "Yellow" "INFO" "Get-Mega65ToolsFromJenkins"
                Write-Log -Message "Found $($possibleArtifacts.Count) 7z file(s)" -Level "INFO" -Component "Get-Mega65ToolsFromJenkins"
                
                for ($i = 0; $i -lt $possibleArtifacts.Count; $i++) {
                    Write-ColoredOutput "  [$i] $($possibleArtifacts[$i].fileName)" "Yellow" "DEBUG" "Get-Mega65ToolsFromJenkins"
                    Write-Log -Message "  7z artifact [$i]: $($possibleArtifacts[$i].fileName)" -Level "DEBUG" -Component "Get-Mega65ToolsFromJenkins"
                }
                
                # Try to pick the most likely Windows one
                $windowsArtifact = $possibleArtifacts | Where-Object {
                    # Prefer files with generic names (likely cross-platform or Windows)
                    $_.fileName -like "*tools*" -or 
                    $_.fileName -like "*m65*" -or
                    $_.fileName -notlike "*linux*"
                } | Select-Object -First 1
                
                if (-not $windowsArtifact) {
                    $windowsArtifact = $possibleArtifacts[0]
                }
                
                Write-ColoredOutput "Selected artifact: $($windowsArtifact.fileName)" "Yellow" "WARNING" "Get-Mega65ToolsFromJenkins"
                Write-ColoredOutput "WARNING: Could not definitively identify Windows artifact. Proceeding with best guess." "Yellow" "WARNING" "Get-Mega65ToolsFromJenkins"
                Write-Log -Message "Selected artifact: $($windowsArtifact.fileName) (best guess)" -Level "WARNING" -Component "Get-Mega65ToolsFromJenkins"
            } else {
                $errorMsg = "No 7z artifacts found in build"
                Write-Log $errorMsg -Level "ERROR" -Component "Get-Mega65ToolsFromJenkins"
                throw $errorMsg
            }
        }
        
        $fileName = $windowsArtifact.fileName
        $downloadUrl = "$buildUrl/artifact/$($windowsArtifact.relativePath)"
        
        Write-ColoredOutput "Selected Windows artifact: $fileName" "Green" "SUCCESS" "Get-Mega65ToolsFromJenkins"
        Write-ColoredOutput "Relative path: $($windowsArtifact.relativePath)" "Green" "SUCCESS" "Get-Mega65ToolsFromJenkins"
        Write-ColoredOutput "Download URL: $downloadUrl" "Green" "SUCCESS" "Get-Mega65ToolsFromJenkins"
        
        Write-Log -Message "Selected Windows artifact: $fileName" -Level "SUCCESS" -Component "Get-Mega65ToolsFromJenkins"
        Write-Log -Message "Download URL: $downloadUrl" -Level "INFO" -Component "Get-Mega65ToolsFromJenkins"
        
        # Validate the download URL
        try {
            $testResponse = Invoke-WebRequest -Uri $downloadUrl -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            if ($testResponse.StatusCode -eq 200) {
                Write-ColoredOutput "Download URL validated successfully" "Green" "SUCCESS" "Get-Mega65ToolsFromJenkins"
                Write-Log -Message "Download URL validated successfully (status: 200)" -Level "SUCCESS" -Component "Get-Mega65ToolsFromJenkins"
                
                $contentLength = $testResponse.Headers['Content-Length']
                if ($contentLength) {
                    $sizeMB = [math]::Round($contentLength / 1MB, 2)
                    Write-ColoredOutput "File size: $sizeMB MB" "Green" "SUCCESS" "Get-Mega65ToolsFromJenkins"
                    Write-Log -Message "File size: $sizeMB MB" -Level "INFO" -Component "Get-Mega65ToolsFromJenkins"
                }
            } else {
                throw "Download URL returned status code: $($testResponse.StatusCode)"
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-ColoredOutput "Warning: Could not validate download URL: $errorMessage" "Yellow" "WARNING" "Get-Mega65ToolsFromJenkins"
            Write-ColoredOutput "Proceeding anyway..." "Yellow" "WARNING" "Get-Mega65ToolsFromJenkins"
            Write-Log -Message "Could not validate download URL: $errorMessage" -Level "WARNING" -Component "Get-Mega65ToolsFromJenkins"
        }
        
        # Extract version/commit info if available
        $version = "dev-build-$buildNumber"
        $commitHash = ""
        
        try {
            if ($buildInfo.changeSet -and $buildInfo.changeSet.items -and $buildInfo.changeSet.items.Count -gt 0) {
                $latestCommit = $buildInfo.changeSet.items[0]
                if ($latestCommit.commitId) {
                    $commitHash = $latestCommit.commitId.Substring(0, [Math]::Min(7, $latestCommit.commitId.Length))
                    $version = "dev-$buildNumber-$commitHash"
                    Write-ColoredOutput "Latest commit: $commitHash" "Green" "SUCCESS" "Get-Mega65ToolsFromJenkins"
                    Write-Log -Message "Latest commit: $commitHash" -Level "INFO" -Component "Get-Mega65ToolsFromJenkins"
                }
                if ($latestCommit.msg) {
                    Write-ColoredOutput "Commit message: $($latestCommit.msg)" "Gray" "DEBUG" "Get-Mega65ToolsFromJenkins"
                    Write-Log -Message "Commit message: $($latestCommit.msg)" -Level "DEBUG" -Component "Get-Mega65ToolsFromJenkins"
                }
            }
        }
        catch {
            Write-ColoredOutput "Could not extract commit information" "Yellow" "WARNING" "Get-Mega65ToolsFromJenkins"
            Write-Log -Message "Could not extract commit information" -Level "WARNING" -Component "Get-Mega65ToolsFromJenkins"
        }
        
        $result = @{
            DownloadUrl = $downloadUrl
            FileName = $fileName
            BuildType = "development"
            Version = $version
            BuildNumber = $buildNumber
            CommitHash = $commitHash
            BuildTimestamp = $timestamp
            BuildUrl = $buildUrl
            RelativePath = $windowsArtifact.relativePath
        }
        
        Write-Log -Message "Jenkins query completed successfully - Version: $version" -Level "SUCCESS" -Component "Get-Mega65ToolsFromJenkins"
        Write-FunctionLog -FunctionName "Get-Mega65ToolsFromJenkins" -Action "EXIT" -Details "Success: $version"
        return $result
    }
    catch {
        $errorMessage = $_.Exception.Message
        $errorMsg = "ERROR: Unable to retrieve MEGA65 Tools from Jenkins CI - $errorMessage"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Get-Mega65ToolsFromJenkins"
        Write-ColoredOutput "Details: $errorMessage" "Red" "ERROR" "Get-Mega65ToolsFromJenkins"
        Write-ColoredOutput "Check your internet connection and Jenkins availability" "Red" "ERROR" "Get-Mega65ToolsFromJenkins"
        Write-Log $errorMsg -Level "ERROR" -Component "Get-Mega65ToolsFromJenkins"
        Write-FunctionLog -FunctionName "Get-Mega65ToolsFromJenkins" -Action "ERROR" -Details $errorMessage
        throw "Failed to retrieve MEGA65 Tools from Jenkins: $errorMessage"
    }
}

# Function to safely copy files handling long paths
function Copy-Mega65ToolsFiles {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )
    
    Write-FunctionLog -FunctionName "Copy-Mega65ToolsFiles" -Action "ENTER" -Details "Source: $SourcePath, Destination: $DestinationPath"
    
    Write-ColoredOutput "Copying MEGA65 Tools from: $SourcePath" "Yellow" "INFO" "Copy-Mega65ToolsFiles"
    Write-ColoredOutput "To: $DestinationPath" "Yellow" "INFO" "Copy-Mega65ToolsFiles"
    Write-Log -Message "Starting file copy from $SourcePath to $DestinationPath" -Level "INFO" -Component "Copy-Mega65ToolsFiles"
    
    try {
        # Try standard copy first
        Write-Log -Message "Attempting standard PowerShell copy" -Level "DEBUG" -Component "Copy-Mega65ToolsFiles"
        Copy-Item -Path "$SourcePath\*" -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
        Write-ColoredOutput "Standard copy completed successfully" "Green" "SUCCESS" "Copy-Mega65ToolsFiles"
        Write-Log -Message "Standard copy completed successfully" -Level "SUCCESS" -Component "Copy-Mega65ToolsFiles"
        Write-FunctionLog -FunctionName "Copy-Mega65ToolsFiles" -Action "EXIT" -Details "Standard copy success"
    }
    catch [System.IO.PathTooLongException] {
        Write-ColoredOutput "Long path detected, using robocopy for file transfer..." "Yellow" "WARNING" "Copy-Mega65ToolsFiles"
        Write-Log -Message "Long path detected, switching to robocopy" -Level "WARNING" -Component "Copy-Mega65ToolsFiles"
        
        # Use robocopy for long path support
        Write-Log -Message "Executing robocopy with parameters: /E /R:1 /W:1 /NP /NDL /NJH /NJS" -Level "DEBUG" -Component "Copy-Mega65ToolsFiles"
        $robocopyResult = robocopy "$SourcePath" "$DestinationPath" /E /R:1 /W:1 /NP /NDL /NJH /NJS
        
        # Check robocopy exit code (0-7 are success codes)
        Write-Log -Message "Robocopy completed with exit code: $LASTEXITCODE" -Level "INFO" -Component "Copy-Mega65ToolsFiles"
        if ($LASTEXITCODE -le 7) {
            Write-ColoredOutput "Robocopy transfer completed successfully" "Green" "SUCCESS" "Copy-Mega65ToolsFiles"
            Write-Log -Message "Robocopy transfer completed successfully" -Level "SUCCESS" -Component "Copy-Mega65ToolsFiles"
        } else {
            $warningMsg = "Some files may not have been copied (robocopy exit code: $LASTEXITCODE)"
            Write-ColoredOutput "Warning: $warningMsg" "Yellow" "WARNING" "Copy-Mega65ToolsFiles"
            Write-Log $warningMsg -Level "WARNING" -Component "Copy-Mega65ToolsFiles"
        }
        Write-FunctionLog -FunctionName "Copy-Mega65ToolsFiles" -Action "EXIT" -Details "Robocopy method used"
    }
    catch {
        $errorMessage = $_.Exception.Message
        $errorMsg = "Error during file copy: $errorMessage"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Copy-Mega65ToolsFiles"
        Write-Log $errorMsg -Level "ERROR" -Component "Copy-Mega65ToolsFiles"
        Write-FunctionLog -FunctionName "Copy-Mega65ToolsFiles" -Action "ERROR" -Details $errorMessage
        throw
    }
}

# Function to install MEGA65 Tools with configurable temp directory
function Install-Mega65Tools {
    param(
        [string]$BaseInstallPath,
        [string]$TempDir
    )
    
    Write-FunctionLog -FunctionName "Install-Mega65Tools" -Action "ENTER" -Details "BaseInstallPath: $BaseInstallPath, TempDir: $TempDir"
    
    Write-ColoredOutput "`n=== MEGA65 Tools Installation ===" "Magenta" "INFO" "Install-Mega65Tools"
    Write-Log -Message "Starting MEGA65 Tools installation process" -Level "INFO" -Component "Install-Mega65Tools"
    Write-Log -Message "Base installation path: $BaseInstallPath" -Level "INFO" -Component "Install-Mega65Tools"
    Write-Log -Message "Temporary directory: $TempDir" -Level "INFO" -Component "Install-Mega65Tools"
    
    try {
        # Get latest version information from Jenkins
        Write-Log -Message "Getting latest MEGA65 Tools version information from Jenkins" -Level "INFO" -Component "Install-Mega65Tools"
        $toolsInfo = Get-Mega65ToolsFromJenkins
        $version = $toolsInfo.Version
        $fileName = $toolsInfo.FileName
        $downloadUrl = $toolsInfo.DownloadUrl
        $buildNumber = $toolsInfo.BuildNumber
        $buildTimestamp = $toolsInfo.BuildTimestamp
        
        Write-ColoredOutput "Installing MEGA65 Tools $version" "Cyan" "INFO" "Install-Mega65Tools"
        Write-ColoredOutput "Build: #$buildNumber ($buildTimestamp)" "Cyan" "INFO" "Install-Mega65Tools"
        Write-ColoredOutput "File: $fileName" "Cyan" "INFO" "Install-Mega65Tools"
        
        Write-Log -Message "Selected MEGA65 Tools version: $version" -Level "INFO" -Component "Install-Mega65Tools"
        Write-Log -Message "Build: #$buildNumber, File: $fileName" -Level "INFO" -Component "Install-Mega65Tools"
        
        # Configure paths - Install to PCTOOLS\m65tools subdirectory
        $pctoolsPath = Join-Path $BaseInstallPath "PCTOOLS"
        $toolsInstallPath = Join-Path $pctoolsPath "m65tools"
        $toolsArchivePath = Join-Path $TempDir $fileName
        $toolsExtractPath = Join-Path $TempDir "extract"
        
        Write-Log -Message "Installation paths configured:" -Level "DEBUG" -Component "Install-Mega65Tools"
        Write-Log -Message "  PCTOOLS path: $pctoolsPath" -Level "DEBUG" -Component "Install-Mega65Tools"
        Write-Log -Message "  Install path: $toolsInstallPath" -Level "DEBUG" -Component "Install-Mega65Tools"
        Write-Log -Message "  Archive path: $toolsArchivePath" -Level "DEBUG" -Component "Install-Mega65Tools"
        Write-Log -Message "  Extract path: $toolsExtractPath" -Level "DEBUG" -Component "Install-Mega65Tools"
        
        # Create directories
        Write-Log -Message "Creating required directories" -Level "INFO" -Component "Install-Mega65Tools"
        New-InstallDirectory $pctoolsPath
        New-InstallDirectory $toolsInstallPath
        New-InstallDirectory $TempDir
        New-InstallDirectory $toolsExtractPath
        
        # Download
        Write-Log -Message "Starting MEGA65 Tools download" -Level "INFO" -Component "Install-Mega65Tools"
        Download-File $downloadUrl $toolsArchivePath
        
        # Extract 7z archive
        Write-ColoredOutput "Extracting MEGA65 Tools..." "Yellow" "INFO" "Install-Mega65Tools"
        Write-Log -Message "Starting archive extraction" -Level "INFO" -Component "Install-Mega65Tools"
        
        try {
            # Try using 7z if available, otherwise use Expand-Archive
            $sevenZipPath = Get-Command "7z.exe" -ErrorAction SilentlyContinue
            if ($sevenZipPath) {
                Write-ColoredOutput "Using 7-Zip for extraction..." "Cyan" "INFO" "Install-Mega65Tools"
                Write-Log -Message "Using 7-Zip for extraction: $($sevenZipPath.Source)" -Level "INFO" -Component "Install-Mega65Tools"
                
                & "7z.exe" x "$toolsArchivePath" "-o$toolsExtractPath" -y | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-ColoredOutput "7-Zip extraction completed" "Green" "SUCCESS" "Install-Mega65Tools"
                    Write-Log -Message "7-Zip extraction completed successfully" -Level "SUCCESS" -Component "Install-Mega65Tools"
                } else {
                    $errorMsg = "7-Zip extraction failed with exit code: $LASTEXITCODE"
                    Write-Log $errorMsg -Level "ERROR" -Component "Install-Mega65Tools"
                    throw $errorMsg
                }
            }
            else {
                Write-ColoredOutput "7-Zip not found, trying PowerShell Expand-Archive..." "Yellow" "WARNING" "Install-Mega65Tools"
                Write-Log -Message "7-Zip not found, using PowerShell Expand-Archive" -Level "WARNING" -Component "Install-Mega65Tools"
                
                Expand-Archive -Path $toolsArchivePath -DestinationPath $toolsExtractPath -Force -ErrorAction Stop
                Write-ColoredOutput "PowerShell extraction completed" "Green" "SUCCESS" "Install-Mega65Tools"
                Write-Log -Message "PowerShell extraction completed successfully" -Level "SUCCESS" -Component "Install-Mega65Tools"
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            $errorMsg = "Extraction error: $errorMessage"
            Write-ColoredOutput $errorMsg "Red" "ERROR" "Install-Mega65Tools"
            Write-ColoredOutput "Note: MEGA65 Tools uses 7z format. Consider installing 7-Zip for better compatibility." "Yellow" "WARNING" "Install-Mega65Tools"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-Mega65Tools"
            Write-Log -Message "Note: MEGA65 Tools uses 7z format. Consider installing 7-Zip for better compatibility." -Level "WARNING" -Component "Install-Mega65Tools"
            throw
        }
        
        # Find extracted content (might be in a subfolder)
        $extractedItems = Get-ChildItem -Path $toolsExtractPath -ErrorAction SilentlyContinue
        if ($extractedItems.Count -eq 0) {
            $errorMsg = "No files found after extraction. Archive may be corrupted or extraction failed."
            Write-Log $errorMsg -Level "ERROR" -Component "Install-Mega65Tools"
            throw $errorMsg
        }
        
        Write-ColoredOutput "Found $($extractedItems.Count) items in extracted archive" "Cyan" "INFO" "Install-Mega65Tools"
        Write-Log -Message "Archive contents: $($extractedItems.Count) items found" -Level "INFO" -Component "Install-Mega65Tools"
        
        # If there's a single directory, use it as source, otherwise use the extract path directly
        if ($extractedItems.Count -eq 1 -and $extractedItems[0].PSIsContainer) {
            $sourceToolsPath = $extractedItems[0].FullName
            Write-ColoredOutput "Found extracted folder: $($extractedItems[0].Name)" "Green" "SUCCESS" "Install-Mega65Tools"
            Write-Log -Message "Using extracted folder: $($extractedItems[0].Name)" -Level "INFO" -Component "Install-Mega65Tools"
        } else {
            $sourceToolsPath = $toolsExtractPath
            Write-ColoredOutput "Using extraction directory directly" "Green" "SUCCESS" "Install-Mega65Tools"
            Write-Log -Message "Using extraction directory directly" -Level "INFO" -Component "Install-Mega65Tools"
        }
        
        # Copy files with long path handling
        Write-ColoredOutput "Installing to: $toolsInstallPath" "Yellow" "INFO" "Install-Mega65Tools"
        Write-Log -Message "Starting file installation to: $toolsInstallPath" -Level "INFO" -Component "Install-Mega65Tools"
        Copy-Mega65ToolsFiles $sourceToolsPath $toolsInstallPath
        
        # Verify essential files and discover additional tools
        Write-Log -Message "Verifying essential MEGA65 tools and discovering additional tools" -Level "INFO" -Component "Install-Mega65Tools"
        
        # Essential tools list
        $essentialFiles = @("m65.exe", "mega65_ftp.exe", "etherload.exe")
        $foundEssential = @()
        $missingEssential = @()
        
        # Check essential tools
        foreach ($file in $essentialFiles) {
            $filePath = Join-Path $toolsInstallPath $file
            if (Test-Path $filePath) {
                $foundEssential += $file
                Write-Log -Message "Found essential tool: $file" -Level "DEBUG" -Component "Install-Mega65Tools"
            } else {
                $missingEssential += $file
                Write-Log -Message "Missing essential tool: $file" -Level "WARNING" -Component "Install-Mega65Tools"
            }
        }
        
        # Discover all tools
        $allToolFiles = Get-ChildItem -Path $toolsInstallPath -Filter "*.exe" -ErrorAction SilentlyContinue
        $allTools = $allToolFiles | ForEach-Object { $_.Name }
        
        # Find additional/bonus tools
        $bonusTools = $allTools | Where-Object { $_ -notin $essentialFiles }
        
        # Validate installation
        if ($allTools.Count -eq 0) {
            $errorMsg = "No executables found in installation directory. Installation may have failed."
            Write-Log $errorMsg -Level "ERROR" -Component "Install-Mega65Tools"
            throw $errorMsg
        }
        
        Write-ColoredOutput "Installation files copied successfully" "Green" "SUCCESS" "Install-Mega65Tools"
        Write-Log -Message "Installation files copied - Total tools: $($allTools.Count), Essential: $($foundEssential.Count)/$($essentialFiles.Count), Bonus: $($bonusTools.Count)" -Level "SUCCESS" -Component "Install-Mega65Tools"
        
        # Configure environment variables
        Write-ColoredOutput "Configuring environment variables..." "Yellow" "INFO" "Install-Mega65Tools"
        Write-Log -Message "Starting environment variable configuration" -Level "INFO" -Component "Install-Mega65Tools"
        
        # Add tools directory to system PATH
        try {
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            if ($currentPath -notlike "*$toolsInstallPath*") {
                $newPath = "$currentPath;$toolsInstallPath"
                [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
                Write-ColoredOutput "MEGA65 Tools added to system PATH: $toolsInstallPath" "Green" "SUCCESS" "Install-Mega65Tools"
                Write-Log -Message "MEGA65 Tools added to system PATH: $toolsInstallPath" -Level "SUCCESS" -Component "Install-Mega65Tools"
            } else {
                Write-ColoredOutput "MEGA65 Tools already present in system PATH" "Yellow" "WARNING" "Install-Mega65Tools"
                Write-Log -Message "MEGA65 Tools already present in system PATH" -Level "WARNING" -Component "Install-Mega65Tools"
            }
            
            # Update PATH for current session (with verification to avoid duplicates)
            if ($env:PATH -notlike "*$toolsInstallPath*") {
                $env:PATH += ";$toolsInstallPath"
                Write-Log -Message "Current session PATH updated" -Level "DEBUG" -Component "Install-Mega65Tools"
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            $errorMsg = "Failed to update system PATH: $errorMessage"
            Write-ColoredOutput "Warning: $errorMsg" "Yellow" "WARNING" "Install-Mega65Tools"
            Write-Log $errorMsg -Level "WARNING" -Component "Install-Mega65Tools"
        }
        
        # Cleanup temporary files
        Write-ColoredOutput "Cleaning up temporary files..." "Yellow" "INFO" "Install-Mega65Tools"
        Write-Log -Message "Starting temporary file cleanup" -Level "INFO" -Component "Install-Mega65Tools"
        try {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColoredOutput "Cleanup completed" "Green" "SUCCESS" "Install-Mega65Tools"
            Write-Log -Message "Temporary file cleanup completed successfully" -Level "SUCCESS" -Component "Install-Mega65Tools"
        }
        catch {
            $errorMessage = $_.Exception.Message
            $warningMsg = "Some temporary files may remain in $TempDir : $errorMessage"
            Write-ColoredOutput "Warning: $warningMsg" "Yellow" "WARNING" "Install-Mega65Tools"
            Write-Log $warningMsg -Level "WARNING" -Component "Install-Mega65Tools"
        }
        
        Write-Log -Message "MEGA65 Tools installation completed successfully!" -Level "SUCCESS" -Component "Install-Mega65Tools"
        Write-FunctionLog -FunctionName "Install-Mega65Tools" -Action "EXIT" -Details "Installation process completed"
        
        # Return installation details for main summary
        return @{
            Version = $version
            BuildNumber = $buildNumber
            BuildTimestamp = $buildTimestamp
            InstallPath = $toolsInstallPath
            FoundEssential = $foundEssential
            MissingEssential = $missingEssential
            BonusTools = $bonusTools
        }
        
    }
    catch {
        $errorMessage = $_.Exception.Message
        $errorMsg = "Error during MEGA65 Tools installation: $errorMessage"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Install-Mega65Tools"
        Write-Log $errorMsg -Level "ERROR" -Component "Install-Mega65Tools"
        Write-FunctionLog -FunctionName "Install-Mega65Tools" -Action "ERROR" -Details $errorMessage
        throw
    }
}

# Determine installation path and log directory BEFORE Main execution
if ([string]::IsNullOrWhiteSpace($InstallationPath)) {
    # Case 1 or Case 4: No installation path provided
    $mainTreeRoot = Get-MainTreeRoot
    $resolvedInstallPath = Join-Path $mainTreeRoot "install"
    $LogDirectory = Join-Path $resolvedInstallPath "GameShell65_Log_Install"
} else {
    # Case 2 or Case 3: Installation path provided
    $resolvedInstallPath = $InstallationPath.TrimEnd('\', '/')
    $LogDirectory = Join-Path $resolvedInstallPath "GameShell65_Log_Install"
}

# Set log file path
$LogFile = Join-Path $LogDirectory "win_install_m65tools.log"

# Create log directory if it doesn't exist
try {
    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
        Write-Host "Created log directory: $LogDirectory" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Warning: Could not create log directory: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Falling back to current directory for log file" -ForegroundColor Yellow
    # Fallback to current directory if creation fails
    $LogFile = Join-Path (Get-Location) "win_install_m65tools.log"
}

# Initialize log file
try {
    # Create or clear the log file
    $logHeader = @"
================================================================================
GameShell65 - MEGA65 Tools Installation Log
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Script Path: $($MyInvocation.MyCommand.Path)
Installation Path: $resolvedInstallPath
Temp Directory: $TempDirectory
PowerShell Version: $($PSVersionTable.PSVersion)
OS Version: $([System.Environment]::OSVersion.VersionString)
User: $([System.Environment]::UserName)
Computer: $([System.Environment]::MachineName)
================================================================================

"@
    $logHeader | Out-File -FilePath $LogFile -Encoding UTF8 -Force
    Write-Log -Message "Log file initialized" -Level "INFO" -Component "INIT"
}
catch {
    Write-Host "Warning: Could not initialize log file: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Main script
try {
    Write-ColoredOutput "=== GameShell65 - MEGA65 Tools Installer ===" "Magenta" "INFO" "MAIN"
    Write-ColoredOutput "Base installation directory: $resolvedInstallPath" "Cyan" "INFO" "MAIN"
    Write-Log -Message "Script execution started" -Level "INFO" -Component "MAIN"
    Write-Log -Message "Parameters - InstallationPath: $resolvedInstallPath, TempDirectory: $TempDirectory" -Level "INFO" -Component "MAIN"
    
    # Get and validate temporary directory
    $tempDir = Get-TempDirectory -UserTempDir $TempDirectory -BaseInstallPath $resolvedInstallPath
    
    # Check if script is running as administrator
    Write-Log -Message "Checking administrator privileges" -Level "INFO" -Component "MAIN"
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-ColoredOutput "ERROR: This script must be run as administrator!" "Red" "ERROR" "MAIN"
        Write-Log -Message "FATAL: Script not running as administrator" -Level "ERROR" -Component "MAIN"
        exit 1
    }
    Write-Log -Message "Administrator privileges confirmed" -Level "SUCCESS" -Component "MAIN"
    
    # Check internet connection
    Write-ColoredOutput "Checking internet connection..." "Yellow" "INFO" "MAIN"
    Write-Log -Message "Testing internet connectivity" -Level "INFO" -Component "MAIN"
    try {
        $null = Invoke-WebRequest -Uri "https://builder.mega65.org" -Method Head -UseBasicParsing -TimeoutSec 10
        Write-ColoredOutput "Internet connection confirmed" "Green" "SUCCESS" "MAIN"
        Write-Log -Message "Internet connectivity confirmed" -Level "SUCCESS" -Component "MAIN"
    }
    catch {
        Write-ColoredOutput "ERROR: Internet connection required to download software" "Red" "ERROR" "MAIN"
        Write-ColoredOutput "Details: $($_.Exception.Message)" "Red" "ERROR" "MAIN"
        Write-Log -Message "FATAL: Internet connection failed - $($_.Exception.Message)" -Level "ERROR" -Component "MAIN"
        exit 1
    }
    
    # Create base directory
    New-InstallDirectory $resolvedInstallPath
    
    # Install MEGA65 Tools with custom temp directory
    $installResult = Install-Mega65Tools $resolvedInstallPath $tempDir
    
    # Display installation summary
    Write-ColoredOutput "`n=== Installation completed successfully! ===" "Green" "SUCCESS" "MAIN"
    Write-ColoredOutput "`nVersion: $($installResult.Version)" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "Build: #$($installResult.BuildNumber) ($($installResult.BuildTimestamp))" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "Installation directory: $($installResult.InstallPath)" "Cyan" "INFO" "MAIN"
    
    # Display essential tools
    if ($installResult.FoundEssential.Count -gt 0) {
        $totalEssential = $installResult.FoundEssential.Count + $installResult.MissingEssential.Count
        Write-ColoredOutput "`nEssential tools found ($($installResult.FoundEssential.Count)/$totalEssential):" "Green" "SUCCESS" "MAIN"
        foreach ($tool in $installResult.FoundEssential) {
            Write-ColoredOutput "  $([char]0x2713) $tool" "Green" "SUCCESS" "MAIN"
        }
    }
    
    # Display missing essential tools
    if ($installResult.MissingEssential.Count -gt 0) {
        Write-ColoredOutput "`nMissing essential tools:" "Yellow" "WARNING" "MAIN"
        foreach ($tool in $installResult.MissingEssential) {
            Write-ColoredOutput "  $([char]0x2717) $tool" "Yellow" "WARNING" "MAIN"
        }
    }
    
    # Display bonus tools
    if ($installResult.BonusTools.Count -gt 0) {
        Write-ColoredOutput "`nAdditional tools found ($($installResult.BonusTools.Count)):" "Cyan" "INFO" "MAIN"
        foreach ($tool in $installResult.BonusTools) {
            Write-ColoredOutput "  + $tool" "Cyan" "INFO" "MAIN"
        }
    }
    
    Write-ColoredOutput "`nIMPORTANT: Restart your session or open a new command window to use the new tools." "Yellow" "INFO" "MAIN"
    Write-ColoredOutput "You can verify the installation by running: m65 --help" "Gray" "INFO" "MAIN"
    
    $scriptEndTime = Get-Date
    $totalDuration = ($scriptEndTime - $Global:LogStartTime).TotalSeconds
    Write-Log -Message "Script completed successfully in $([math]::Round($totalDuration, 2)) seconds" -Level "SUCCESS" -Component "MAIN"
    Write-Log -Message "Log file location: $LogFile" -Level "INFO" -Component "MAIN"
    
}
catch {
    Write-ColoredOutput "`nFATAL ERROR: $($_.Exception.Message)" "Red" "ERROR" "MAIN"
    Write-ColoredOutput "Installation failed." "Red" "ERROR" "MAIN"
    Write-Log -Message "FATAL ERROR: $($_.Exception.Message)" -Level "ERROR" -Component "MAIN"
    Write-Log -Message "Full exception: $($_.Exception | Out-String)" -Level "ERROR" -Component "MAIN"
    
    # Cleanup on failure
    try {
        $tempDir = Get-TempDirectory -UserTempDir $TempDirectory -BaseInstallPath $resolvedInstallPath
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log -Message "Emergency cleanup completed" -Level "INFO" -Component "MAIN"
        }
    }
    catch {
        Write-Log -Message "Emergency cleanup failed: $($_.Exception.Message)" -Level "WARNING" -Component "MAIN"
    }
    
    $scriptEndTime = Get-Date
    $totalDuration = ($scriptEndTime - $Global:LogStartTime).TotalSeconds
    Write-Log -Message "Script failed after $([math]::Round($totalDuration, 2)) seconds" -Level "ERROR" -Component "MAIN"
    
    exit 1
}
finally {
    # Final log entry
    Write-Log -Message "Script execution ended" -Level "INFO" -Component "MAIN"
    Write-Log -Message "================================================================================`n" -Level "INFO" -Component "MAIN"
}