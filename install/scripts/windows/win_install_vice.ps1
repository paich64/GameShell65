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

# Load required assemblies for URL handling
Add-Type -AssemblyName System.Web

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
            $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\vice"
            Write-ColoredOutput "Using installation-based temporary directory: $tempDir" "Cyan" "INFO" "Get-TempDirectory"
        }
        else {
            # User provided temp directory
            $tempDir = Join-Path $UserTempDir "GameShell65_temp_Install\vice"
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
                    $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\vice"
                }
            }
        }
        
        # Ensure the temp directory path is not too long to avoid path issues
        if ($tempDir.Length -gt 100) {
            Write-ColoredOutput "Warning: Temporary directory path is long ($($tempDir.Length) chars). This may cause issues with some files." "Yellow" "WARNING" "Get-TempDirectory"
            Write-ColoredOutput "Consider using a shorter path like 'C:\Temp\VS65'" "Yellow" "WARNING" "Get-TempDirectory"
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

# Function to download a file with standard HTTP handling
function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath,
        [int]$MaxRetries = 3
    )
    
    Write-FunctionLog -FunctionName "Download-File" -Action "ENTER" -Details "URL: $Url, OutputPath: $OutputPath"
    
    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            Write-Log -Message "Download attempt $($retryCount + 1) of $MaxRetries" -Level "DEBUG" -Component "Download-File"
            
            # Remove existing file if it exists
            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -Force
                Write-Log -Message "Removed existing file: $OutputPath" -Level "DEBUG" -Component "Download-File"
            }
            
            Write-ColoredOutput "Downloading from: $Url" "Cyan" "INFO" "Download-File"
            Write-ColoredOutput "Destination: $OutputPath" "Cyan" "INFO" "Download-File"
            
            # Standard download with proper headers
            $progressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            
            try {
                $downloadStartTime = Get-Date
                Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -TimeoutSec 120 -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                $downloadEndTime = Get-Date
                $downloadDuration = ($downloadEndTime - $downloadStartTime).TotalSeconds
            }
            finally {
                $ProgressPreference = $progressPreference
            }
            
            # Verify file was downloaded and has content
            if (Test-Path $OutputPath) {
                $fileSize = (Get-Item $OutputPath).Length
                Write-ColoredOutput "File downloaded, size: $fileSize bytes" "Cyan" "INFO" "Download-File"
                Write-Log -Message "Download completed - Size: $fileSize bytes, Duration: $([math]::Round($downloadDuration, 2)) seconds" -Level "SUCCESS" -Component "Download-File"
                
                # For 7z files, expect at least 1MB for a valid VICE distribution
                $expectedMinSize = if ($OutputPath.EndsWith(".7z")) { 1MB } else { 1KB }
                
                if ($fileSize -gt $expectedMinSize) {
                    # Additional check for 7z files - verify it's actually a 7z archive
                    if ($OutputPath.EndsWith(".7z")) {
                        try {
                            Write-Log -Message "Verifying 7z file signature" -Level "DEBUG" -Component "Download-File"
                            $fileBytes = [System.IO.File]::ReadAllBytes($OutputPath)
                            # Check 7z file signature (7z header: '7z¼¯')
                            if ($fileBytes.Length -ge 6 -and $fileBytes[0] -eq 0x37 -and $fileBytes[1] -eq 0x7A -and $fileBytes[2] -eq 0xBC -and $fileBytes[3] -eq 0xAF -and $fileBytes[4] -eq 0x27 -and $fileBytes[5] -eq 0x1C) {
                                Write-ColoredOutput "Download completed successfully - Valid 7z file" "Green" "SUCCESS" "Download-File"
                                Write-Log -Message "7z file signature verification successful" -Level "SUCCESS" -Component "Download-File"
                                Write-FunctionLog -FunctionName "Download-File" -Action "EXIT" -Details "Success"
                                return
                            }
                            else {
                                # Check if it's an HTML file
                                $maxBytes = [Math]::Min(100, $fileBytes.Length - 1)
                                $firstBytes = [System.Text.Encoding]::ASCII.GetString($fileBytes[0..$maxBytes])
                                if ($firstBytes -match "<!DOCTYPE html>|<html") {
                                    $errorMsg = "Downloaded HTML page instead of 7z file - Download failed"
                                    Write-Log $errorMsg -Level "ERROR" -Component "Download-File"
                                    throw $errorMsg
                                }
                                else {
                                    $errorMsg = "Downloaded file is not a valid 7z archive (no 7z signature)"
                                    Write-Log $errorMsg -Level "ERROR" -Component "Download-File"
                                    throw $errorMsg
                                }
                            }
                        }
                        catch {
                            if ($_.Exception.Message -match "HTML page") {
                                throw $_.Exception.Message
                            }
                            else {
                                $errorMsg = "Cannot verify 7z file integrity: $($_.Exception.Message)"
                                Write-Log $errorMsg -Level "ERROR" -Component "Download-File"
                                throw $errorMsg
                            }
                        }
                    }
                    else {
                        Write-ColoredOutput "Download completed successfully" "Green" "SUCCESS" "Download-File"
                        Write-Log -Message "Non-7z file download completed successfully" -Level "SUCCESS" -Component "Download-File"
                        Write-FunctionLog -FunctionName "Download-File" -Action "EXIT" -Details "Success"
                        return
                    }
                }
                else {
                    $errorMsg = "Downloaded file is too small ($fileSize bytes, expected at least $expectedMinSize bytes)"
                    Write-Log $errorMsg -Level "ERROR" -Component "Download-File"
                    throw $errorMsg
                }
            }
            else {
                $errorMsg = "Download failed - file not created"
                Write-Log $errorMsg -Level "ERROR" -Component "Download-File"
                throw $errorMsg
            }
        }
        catch {
            $retryCount++
            Write-ColoredOutput "Download attempt $retryCount failed: $($_.Exception.Message)" "Yellow" "WARNING" "Download-File"
            Write-Log "Download attempt $retryCount failed: $($_.Exception.Message)" -Level "WARNING" -Component "Download-File"
            
            if ($retryCount -lt $MaxRetries) {
                Write-ColoredOutput "Retrying download in 3 seconds..." "Yellow" "WARNING" "Download-File"
                Write-Log "Retrying download in 3 seconds..." -Level "INFO" -Component "Download-File"
                Start-Sleep -Seconds 3
            }
            else {
                $finalError = "Download error after $MaxRetries attempts: $($_.Exception.Message)"
                Write-ColoredOutput $finalError "Red" "ERROR" "Download-File"
                Write-Log $finalError -Level "ERROR" -Component "Download-File"
                Write-FunctionLog -FunctionName "Download-File" -Action "ERROR" -Details $_.Exception.Message
                throw
            }
        }
    }
}

# Function to get the latest version of VICE from GitHub releases
function Get-LatestViceVersion {
    Write-FunctionLog -FunctionName "Get-LatestViceVersion" -Action "ENTER"
    
    Write-ColoredOutput "Searching for the latest version of VICE from GitHub..." "Yellow" "INFO" "Get-LatestViceVersion"
    
    try {
        # Query VICE GitHub releases API
        $apiUrl = "https://api.github.com/repos/VICE-Team/svn-mirror/releases"
        Write-ColoredOutput "Querying VICE GitHub releases: $apiUrl" "Cyan" "INFO" "Get-LatestViceVersion"
        Write-Log -Message "Querying GitHub API: $apiUrl" -Level "INFO" -Component "Get-LatestViceVersion"
        
        $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 30 -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        
        if (-not $response -or $response.Count -eq 0) {
            $errorMsg = "Empty response from VICE GitHub releases API"
            Write-Log $errorMsg -Level "ERROR" -Component "Get-LatestViceVersion"
            throw $errorMsg
        }
        
        Write-ColoredOutput "Found $($response.Count) releases from GitHub API" "Cyan" "INFO" "Get-LatestViceVersion"
        Write-Log -Message "GitHub API returned $($response.Count) releases" -Level "INFO" -Component "Get-LatestViceVersion"
        
        # Find all GTK3VICE win64 7z files
        $gtk3Releases = @()
        
        foreach ($release in $response) {
            Write-Log -Message "Processing release: $($release.name) ($($release.tag_name))" -Level "DEBUG" -Component "Get-LatestViceVersion"
            if ($release.assets) {
                foreach ($asset in $release.assets) {
                    if ($asset.name -match "^GTK3VICE-(\d+\.\d+(?:\.\d+)?)-win64-r(\d+)\.7z$") {
                        $version = $matches[1]
                        $revision = [int]$matches[2]
                        
                        $gtk3Releases += @{
                            Version = $version
                            Revision = $revision
                            FileName = $asset.name
                            DownloadUrl = $asset.browser_download_url
                            Size = $asset.size
                            ReleaseDate = $release.published_at
                            ReleaseName = $release.name
                        }
                        
                        Write-ColoredOutput "Found: $($asset.name) (r$revision)" "Gray" "DEBUG" "Get-LatestViceVersion"
                        Write-Log -Message "Found GTK3VICE release: $($asset.name) (r$revision, $($asset.size) bytes)" -Level "DEBUG" -Component "Get-LatestViceVersion"
                    }
                }
            }
        }
        
        if ($gtk3Releases.Count -eq 0) {
            $errorMsg = "No GTK3VICE win64 7z files found in GitHub releases"
            Write-Log $errorMsg -Level "ERROR" -Component "Get-LatestViceVersion"
            throw $errorMsg
        }
        
        Write-ColoredOutput "Total GTK3VICE win64 7z files found: $($gtk3Releases.Count)" "Cyan" "INFO" "Get-LatestViceVersion"
        Write-Log -Message "Total GTK3VICE releases found: $($gtk3Releases.Count)" -Level "INFO" -Component "Get-LatestViceVersion"
        
        # Sort by version first, then by revision (both descending)
        $sortedReleases = $gtk3Releases | Sort-Object @{
            Expression = {
                $versionParts = $_.Version.Split('.')
                $major = [int]$versionParts[0]
                $minor = [int]$versionParts[1]
                $patch = if ($versionParts.Length -gt 2) { [int]$versionParts[2] } else { 0 }
                $major * 10000 + $minor * 100 + $patch
            }
            Descending = $true
        }, @{
            Expression = {$_.Revision}
            Descending = $true
        }
        
        $latestRelease = $sortedReleases[0]
        
        Write-ColoredOutput "Latest VICE GTK3 version: $($latestRelease.Version) r$($latestRelease.Revision)" "Green" "SUCCESS" "Get-LatestViceVersion"
        Write-ColoredOutput "File: $($latestRelease.FileName)" "Green" "SUCCESS" "Get-LatestViceVersion"
        Write-ColoredOutput "Size: $([math]::Round($latestRelease.Size / 1MB, 2)) MB" "Green" "SUCCESS" "Get-LatestViceVersion"
        Write-ColoredOutput "Release date: $($latestRelease.ReleaseDate)" "Green" "SUCCESS" "Get-LatestViceVersion"
        
        Write-Log -Message "Latest version selected: $($latestRelease.Version) r$($latestRelease.Revision)" -Level "SUCCESS" -Component "Get-LatestViceVersion"
        Write-Log -Message "Latest release details: File=$($latestRelease.FileName), Size=$($latestRelease.Size), URL=$($latestRelease.DownloadUrl)" -Level "INFO" -Component "Get-LatestViceVersion"
        
        # Display debug info for top 3 versions found
        Write-ColoredOutput "Debug: Top 3 versions found:" "Gray" "DEBUG" "Get-LatestViceVersion"
        for ($i = 0; $i -lt [Math]::Min(3, $sortedReleases.Count); $i++) {
            $debugRelease = $sortedReleases[$i]
            Write-ColoredOutput "  $($i+1). $($debugRelease.Version) r$($debugRelease.Revision) - $($debugRelease.FileName)" "Gray" "DEBUG" "Get-LatestViceVersion"
            Write-Log -Message "Top release $($i+1): $($debugRelease.Version) r$($debugRelease.Revision) - $($debugRelease.FileName)" -Level "DEBUG" -Component "Get-LatestViceVersion"
        }
        
        Write-FunctionLog -FunctionName "Get-LatestViceVersion" -Action "EXIT" -Details "Success: $($latestRelease.Version) r$($latestRelease.Revision)"
        return $latestRelease
    }
    catch {
        Write-ColoredOutput "ERROR: Unable to retrieve VICE version from GitHub releases" "Red" "ERROR" "Get-LatestViceVersion"
        Write-ColoredOutput "Details: $($_.Exception.Message)" "Red" "ERROR" "Get-LatestViceVersion"
        Write-ColoredOutput "Using known stable version 3.9 r45744" "Yellow" "WARNING" "Get-LatestViceVersion"
        
        Write-Log -Message "GitHub API failed: $($_.Exception.Message)" -Level "ERROR" -Component "Get-LatestViceVersion"
        Write-Log -Message "Falling back to known stable version" -Level "WARNING" -Component "Get-LatestViceVersion"
        
        # Fallback to known working version
        $fallbackRelease = @{
            Version = "3.9"
            Revision = 45744
            FileName = "GTK3VICE-3.9-win64-r45744.7z"
            DownloadUrl = "https://github.com/VICE-Team/svn-mirror/releases/download/r45744/GTK3VICE-3.9-win64-r45744.7z"
            Size = 24536752
            ReleaseDate = "2025-08-27T09:22:43Z"
            ReleaseName = "r45744 snapshot"
        }
        
        Write-Log -Message "Using fallback release: $($fallbackRelease.Version) r$($fallbackRelease.Revision)" -Level "INFO" -Component "Get-LatestViceVersion"
        Write-FunctionLog -FunctionName "Get-LatestViceVersion" -Action "EXIT" -Details "Fallback used"
        return $fallbackRelease
    }
}

# Function to check if a URL exists
function Test-UrlExists {
    param([string]$Url)
    
    Write-Log -Message "Testing URL existence: $Url" -Level "DEBUG" -Component "Test-UrlExists"
    
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $exists = $response.StatusCode -eq 200
        Write-Log -Message "URL test result for $Url : $exists (Status: $($response.StatusCode))" -Level "DEBUG" -Component "Test-UrlExists"
        return $exists
    }
    catch {
        Write-Log -Message "URL test failed for $Url : $($_.Exception.Message)" -Level "DEBUG" -Component "Test-UrlExists"
        return $false
    }
}

# Function to install 7-Zip if not available
function Install-7Zip {
    param([string]$TempDir)
    
    Write-FunctionLog -FunctionName "Install-7Zip" -Action "ENTER" -Details "TempDir: $TempDir"
    
    Write-ColoredOutput "Checking for 7-Zip installation..." "Yellow" "INFO" "Install-7Zip"
    Write-Log -Message "Starting 7-Zip availability check" -Level "INFO" -Component "Install-7Zip"
    
    # Check if 7z.exe is available in PATH
    try {
        $pathResult = Get-Command "7z.exe" -ErrorAction Stop
        Write-ColoredOutput "7-Zip found in PATH" "Green" "SUCCESS" "Install-7Zip"
        Write-Log -Message "7-Zip found in PATH: $($pathResult.Source)" -Level "SUCCESS" -Component "Install-7Zip"
        Write-FunctionLog -FunctionName "Install-7Zip" -Action "EXIT" -Details "Found in PATH"
        return "7z.exe"
    }
    catch {
        Write-Log -Message "7-Zip not found in PATH" -Level "DEBUG" -Component "Install-7Zip"
        # Check common installation paths
        $commonPaths = @(
            "${env:ProgramFiles}\7-Zip\7z.exe",
            "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
            "${env:ProgramW6432}\7-Zip\7z.exe"
        )
        
        foreach ($path in $commonPaths) {
            Write-Log -Message "Checking common path: $path" -Level "DEBUG" -Component "Install-7Zip"
            if (Test-Path $path) {
                Write-ColoredOutput "7-Zip found at: $path" "Green" "SUCCESS" "Install-7Zip"
                Write-Log -Message "7-Zip found at: $path" -Level "SUCCESS" -Component "Install-7Zip"
                Write-FunctionLog -FunctionName "Install-7Zip" -Action "EXIT" -Details "Found at: $path"
                return $path
            }
        }
    }
    
    Write-ColoredOutput "7-Zip not found, downloading and installing..." "Yellow" "WARNING" "Install-7Zip"
    Write-Log -Message "7-Zip not found, proceeding with installation" -Level "WARNING" -Component "Install-7Zip"
    
    try {
        # Download 7-Zip MSI installer
        $sevenZipMsiUrl = "https://www.7-zip.org/a/7z2409-x64.msi"
        $sevenZipMsiPath = Join-Path $TempDir "7z-installer.msi"
        
        Write-ColoredOutput "Downloading 7-Zip installer: $sevenZipMsiUrl" "Cyan" "INFO" "Install-7Zip"
        Write-Log -Message "Downloading 7-Zip from: $sevenZipMsiUrl" -Level "INFO" -Component "Install-7Zip"
        
        Invoke-WebRequest -Uri $sevenZipMsiUrl -OutFile $sevenZipMsiPath -UseBasicParsing -TimeoutSec 60
        Write-Log -Message "7-Zip installer downloaded successfully" -Level "SUCCESS" -Component "Install-7Zip"
        
        # Install 7-Zip silently
        Write-ColoredOutput "Installing 7-Zip..." "Yellow" "INFO" "Install-7Zip"
        Write-Log -Message "Starting 7-Zip installation (silent mode)" -Level "INFO" -Component "Install-7Zip"
        
        $installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$sevenZipMsiPath`" /quiet /norestart" -Wait -PassThru
        Write-Log -Message "7-Zip installation process completed with exit code: $($installProcess.ExitCode)" -Level "INFO" -Component "Install-7Zip"
        
        if ($installProcess.ExitCode -eq 0) {
            Write-ColoredOutput "7-Zip installed successfully" "Green" "SUCCESS" "Install-7Zip"
            Write-Log -Message "7-Zip installation successful" -Level "SUCCESS" -Component "Install-7Zip"
            
            # Check if it's now available
            $sevenZipExe = "${env:ProgramFiles}\7-Zip\7z.exe"
            if (Test-Path $sevenZipExe) {
                Write-Log -Message "7-Zip executable verified at: $sevenZipExe" -Level "SUCCESS" -Component "Install-7Zip"
                Write-FunctionLog -FunctionName "Install-7Zip" -Action "EXIT" -Details "Installation successful"
                return $sevenZipExe
            }
            else {
                Write-Log -Message "7-Zip executable not found after installation at expected location: $sevenZipExe" -Level "WARNING" -Component "Install-7Zip"
            }
        }
        
        $errorMsg = "7-Zip installation failed with exit code: $($installProcess.ExitCode)"
        Write-Log $errorMsg -Level "ERROR" -Component "Install-7Zip"
        throw $errorMsg
    }
    catch {
        $errorMsg = "Unable to install 7-Zip: $($_.Exception.Message)"
        Write-ColoredOutput "ERROR: $errorMsg" "Red" "ERROR" "Install-7Zip"
        Write-Log $errorMsg -Level "ERROR" -Component "Install-7Zip"
        Write-FunctionLog -FunctionName "Install-7Zip" -Action "ERROR" -Details $_.Exception.Message
        throw "7-Zip is required but could not be installed. Please install 7-Zip manually."
    }
}

# Function to safely copy files handling long paths
function Copy-ViceFiles {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )
    
    Write-FunctionLog -FunctionName "Copy-ViceFiles" -Action "ENTER" -Details "Source: $SourcePath, Destination: $DestinationPath"
    
    Write-ColoredOutput "Copying VICE files from: $SourcePath" "Yellow" "INFO" "Copy-ViceFiles"
    Write-ColoredOutput "To: $DestinationPath" "Yellow" "INFO" "Copy-ViceFiles"
    Write-Log -Message "Starting file copy from $SourcePath to $DestinationPath" -Level "INFO" -Component "Copy-ViceFiles"
    
    try {
        # Try standard copy first
        Write-Log -Message "Attempting standard PowerShell copy" -Level "DEBUG" -Component "Copy-ViceFiles"
        Copy-Item -Path "$SourcePath\*" -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
        Write-ColoredOutput "Standard copy completed successfully" "Green" "SUCCESS" "Copy-ViceFiles"
        Write-Log -Message "Standard copy completed successfully" -Level "SUCCESS" -Component "Copy-ViceFiles"
        Write-FunctionLog -FunctionName "Copy-ViceFiles" -Action "EXIT" -Details "Standard copy success"
    }
    catch [System.IO.PathTooLongException] {
        Write-ColoredOutput "Long path detected, using robocopy for file transfer..." "Yellow" "WARNING" "Copy-ViceFiles"
        Write-Log -Message "Long path detected, switching to robocopy" -Level "WARNING" -Component "Copy-ViceFiles"
        
        # Use robocopy for long path support
        Write-Log -Message "Executing robocopy with parameters: /E /R:1 /W:1 /NP /NDL /NJH /NJS" -Level "DEBUG" -Component "Copy-ViceFiles"
        $robocopyResult = robocopy "$SourcePath" "$DestinationPath" /E /R:1 /W:1 /NP /NDL /NJH /NJS
        
        # Check robocopy exit code (0-7 are success codes)
        Write-Log -Message "Robocopy completed with exit code: $LASTEXITCODE" -Level "INFO" -Component "Copy-ViceFiles"
        if ($LASTEXITCODE -le 7) {
            Write-ColoredOutput "Robocopy transfer completed successfully" "Green" "SUCCESS" "Copy-ViceFiles"
            Write-Log -Message "Robocopy transfer completed successfully" -Level "SUCCESS" -Component "Copy-ViceFiles"
        } else {
            $warningMsg = "Some files may not have been copied (robocopy exit code: $LASTEXITCODE)"
            Write-ColoredOutput "Warning: $warningMsg" "Yellow" "WARNING" "Copy-ViceFiles"
            Write-Log $warningMsg -Level "WARNING" -Component "Copy-ViceFiles"
        }
        Write-FunctionLog -FunctionName "Copy-ViceFiles" -Action "EXIT" -Details "Robocopy method used"
    }
    catch {
        $errorMsg = "Error during file copy: $($_.Exception.Message)"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Copy-ViceFiles"
        Write-Log $errorMsg -Level "ERROR" -Component "Copy-ViceFiles"
        Write-FunctionLog -FunctionName "Copy-ViceFiles" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to extract 7z archive files
function Extract-ViceArchive {
    param(
        [string]$ArchivePath,
        [string]$ExtractPath,
        [string]$SevenZipPath
    )
    
    Write-FunctionLog -FunctionName "Extract-ViceArchive" -Action "ENTER" -Details "Archive: $ArchivePath, Extract: $ExtractPath, 7z: $SevenZipPath"
    
    Write-ColoredOutput "Extracting VICE archive: $(Split-Path $ArchivePath -Leaf)" "Yellow" "INFO" "Extract-ViceArchive"
    Write-Log -Message "Starting 7z extraction: $(Split-Path $ArchivePath -Leaf)" -Level "INFO" -Component "Extract-ViceArchive"
    
    try {
        # Verify the 7z file exists
        if (-not (Test-Path $ArchivePath)) {
            $errorMsg = "Archive file not found: $ArchivePath"
            Write-Log $errorMsg -Level "ERROR" -Component "Extract-ViceArchive"
            throw $errorMsg
        }
        
        Write-Log -Message "Archive file verified: $ArchivePath" -Level "DEBUG" -Component "Extract-ViceArchive"
        
        # Create extraction directory
        New-InstallDirectory $ExtractPath
        
        # Extract using 7-Zip
        Write-ColoredOutput "Using 7-Zip: $SevenZipPath" "Cyan" "INFO" "Extract-ViceArchive"
        Write-Log -Message "Using 7-Zip executable: $SevenZipPath" -Level "INFO" -Component "Extract-ViceArchive"
        
        $extractArgs = @("x", "`"$ArchivePath`"", "-o`"$ExtractPath`"", "-y")
        $extractCommand = "`"$SevenZipPath`" $($extractArgs -join ' ')"
        
        Write-ColoredOutput "Executing: $extractCommand" "Gray" "DEBUG" "Extract-ViceArchive"
        Write-Log -Message "Executing 7z command: $extractCommand" -Level "DEBUG" -Component "Extract-ViceArchive"
        
        $extractProcess = Start-Process -FilePath $SevenZipPath -ArgumentList $extractArgs -Wait -PassThru -NoNewWindow
        
        Write-Log -Message "7z extraction process completed with exit code: $($extractProcess.ExitCode)" -Level "INFO" -Component "Extract-ViceArchive"
        
        if ($extractProcess.ExitCode -eq 0) {
            Write-ColoredOutput "7z extraction completed successfully" "Green" "SUCCESS" "Extract-ViceArchive"
            Write-Log -Message "7z extraction completed successfully" -Level "SUCCESS" -Component "Extract-ViceArchive"
            
            # Verify extraction results
            $extractedItems = Get-ChildItem -Path $ExtractPath -ErrorAction SilentlyContinue
            Write-ColoredOutput "Extracted $($extractedItems.Count) items" "Cyan" "INFO" "Extract-ViceArchive"
            Write-Log -Message "Extraction verification: $($extractedItems.Count) items extracted" -Level "INFO" -Component "Extract-ViceArchive"
            
            Write-FunctionLog -FunctionName "Extract-ViceArchive" -Action "EXIT" -Details "Success: $($extractedItems.Count) items"
            return $ExtractPath
        }
        else {
            $errorMsg = "7-Zip extraction failed with exit code: $($extractProcess.ExitCode)"
            Write-Log $errorMsg -Level "ERROR" -Component "Extract-ViceArchive"
            throw $errorMsg
        }
    }
    catch {
        $errorMsg = "7z extraction error: $($_.Exception.Message)"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Extract-ViceArchive"
        Write-Log $errorMsg -Level "ERROR" -Component "Extract-ViceArchive"
        Write-FunctionLog -FunctionName "Extract-ViceArchive" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to install VICE with configurable temp directory
function Install-Vice {
    param(
        [string]$BaseInstallPath,
        [string]$TempDir
    )
    
    Write-FunctionLog -FunctionName "Install-Vice" -Action "ENTER" -Details "BaseInstallPath: $BaseInstallPath, TempDir: $TempDir"
    
    Write-ColoredOutput "`n=== VICE Emulator Installation ===" "Magenta" "INFO" "Install-Vice"
    Write-Log -Message "Starting VICE installation process" -Level "INFO" -Component "Install-Vice"
    Write-Log -Message "Base installation path: $BaseInstallPath" -Level "INFO" -Component "Install-Vice"
    Write-Log -Message "Temporary directory: $TempDir" -Level "INFO" -Component "Install-Vice"
    
    try {
        # Get latest version from GitHub
        Write-Log -Message "Getting latest VICE version information" -Level "INFO" -Component "Install-Vice"
        $viceRelease = Get-LatestViceVersion
        
        Write-ColoredOutput "Installing VICE v$($viceRelease.Version) r$($viceRelease.Revision) from GitHub" "Cyan" "INFO" "Install-Vice"
        Write-Log -Message "Selected VICE version: $($viceRelease.Version) r$($viceRelease.Revision)" -Level "INFO" -Component "Install-Vice"
        
        # Configure paths
        $viceInstallPath = Join-Path $BaseInstallPath "PCTOOLS\vice"
        $vice7zPath = Join-Path $TempDir "vice.7z"
        $viceExtractPath = Join-Path $TempDir "extract"
        
        Write-Log -Message "Installation paths configured:" -Level "DEBUG" -Component "Install-Vice"
        Write-Log -Message "  Install path: $viceInstallPath" -Level "DEBUG" -Component "Install-Vice"
        Write-Log -Message "  Download path: $vice7zPath" -Level "DEBUG" -Component "Install-Vice"
        Write-Log -Message "  Extract path: $viceExtractPath" -Level "DEBUG" -Component "Install-Vice"
        
        # Create directories
        Write-Log -Message "Creating required directories" -Level "INFO" -Component "Install-Vice"
        New-InstallDirectory $viceInstallPath
        New-InstallDirectory $TempDir
        New-InstallDirectory $viceExtractPath
        
        # Install 7-Zip if needed
        Write-Log -Message "Ensuring 7-Zip availability" -Level "INFO" -Component "Install-Vice"
        $sevenZipExe = Install-7Zip $TempDir
        Write-Log -Message "7-Zip executable: $sevenZipExe" -Level "INFO" -Component "Install-Vice"
        
        # Download VICE
        Write-ColoredOutput "Downloading from: $($viceRelease.DownloadUrl)" "Cyan" "INFO" "Install-Vice"
        Write-Log -Message "Starting VICE download from: $($viceRelease.DownloadUrl)" -Level "INFO" -Component "Install-Vice"
        Download-File $viceRelease.DownloadUrl $vice7zPath
        
        # Verify downloaded file
        $fileSize = (Get-Item $vice7zPath).Length
        Write-ColoredOutput "Downloaded file size: $fileSize bytes" "Cyan" "INFO" "Install-Vice"
        Write-Log -Message "Downloaded file verification: $fileSize bytes" -Level "INFO" -Component "Install-Vice"
        
        if ($fileSize -lt 1MB) {
            $errorMsg = "Downloaded file is too small, may be corrupted"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-Vice"
            throw $errorMsg
        }
        
        # Extract with 7-Zip
        Write-Log -Message "Starting archive extraction" -Level "INFO" -Component "Install-Vice"
        $actualExtractPath = Extract-ViceArchive $vice7zPath $viceExtractPath $sevenZipExe
        
        # Find the extracted content
        $extractedItems = Get-ChildItem -Path $actualExtractPath -ErrorAction SilentlyContinue
        Write-ColoredOutput "Found $($extractedItems.Count) items in extracted archive" "Cyan" "INFO" "Install-Vice"
        Write-Log -Message "Archive contents: $($extractedItems.Count) items found" -Level "INFO" -Component "Install-Vice"
        
        # Look for VICE directory structure
        $sourceDirectory = $actualExtractPath
        Write-Log -Message "Initial source directory: $sourceDirectory" -Level "DEBUG" -Component "Install-Vice"
        
        # Check if there's a subdirectory with the VICE content
        $viceSubDir = $extractedItems | Where-Object { $_.PSIsContainer -and ($_.Name -match "vice" -or $_.Name -match "VICE" -or $_.Name -match "GTK3VICE") } | Select-Object -First 1
        if ($viceSubDir) {
            $sourceDirectory = $viceSubDir.FullName
            Write-ColoredOutput "Using VICE subdirectory: $($viceSubDir.Name)" "Cyan" "INFO" "Install-Vice"
            Write-Log -Message "Found VICE subdirectory: $($viceSubDir.Name), using: $sourceDirectory" -Level "INFO" -Component "Install-Vice"
        }
        else {
            Write-Log -Message "No VICE subdirectory found, using root extract directory" -Level "DEBUG" -Component "Install-Vice"
        }
        
        # Copy all files with long path handling
        Write-ColoredOutput "Installing to: $viceInstallPath" "Yellow" "INFO" "Install-Vice"
        Write-Log -Message "Starting file installation to: $viceInstallPath" -Level "INFO" -Component "Install-Vice"
        Copy-ViceFiles $sourceDirectory $viceInstallPath
        
        # Find VICE executables and utilities in the bin directory
        Write-Log -Message "Searching for VICE emulators and utilities in bin directory" -Level "INFO" -Component "Install-Vice"
        
        $viceBinPath = Join-Path $viceInstallPath "bin"
        
        if (-not (Test-Path $viceBinPath)) {
            $errorMsg = "VICE bin directory not found: $viceBinPath"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-Vice"
            throw $errorMsg
        }
        
        Write-Log -Message "VICE bin directory found: $viceBinPath" -Level "SUCCESS" -Component "Install-Vice"
        
        # Search for VICE emulator executables
        $viceEmulators = Get-ChildItem -Path $viceBinPath -Name "*.exe" | Where-Object { 
            $_ -match "^(x64|x128|xvic|xpet|xplus4|xcbm|xscpu64)" 
        }
        
        # Search for VICE utility executables
        $viceUtilities = Get-ChildItem -Path $viceBinPath -Name "*.exe" | Where-Object { 
            $_ -match "^(c1541|cartconv|petcat|vsid)" 
        }
        
        if ($viceEmulators.Count -eq 0) {
            $errorMsg = "VICE emulators not found in bin directory"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-Vice"
            throw $errorMsg
        }
        
        Write-ColoredOutput "Found VICE emulators:" "Green" "SUCCESS" "Install-Vice"
        Write-Log -Message "VICE emulators found: $($viceEmulators.Count)" -Level "SUCCESS" -Component "Install-Vice"
        foreach ($exe in $viceEmulators) {
            $exePath = Join-Path $viceBinPath $exe
            Write-ColoredOutput "  - $exePath" "Cyan" "INFO" "Install-Vice"
            Write-Log -Message "  Emulator: $exePath" -Level "INFO" -Component "Install-Vice"
        }
        
        if ($viceUtilities.Count -gt 0) {
            Write-ColoredOutput "Found VICE utilities:" "Green" "SUCCESS" "Install-Vice"
            Write-Log -Message "VICE utilities found: $($viceUtilities.Count)" -Level "SUCCESS" -Component "Install-Vice"
            foreach ($exe in $viceUtilities) {
                $exePath = Join-Path $viceBinPath $exe
                Write-ColoredOutput "  - $exePath" "Cyan" "INFO" "Install-Vice"
                Write-Log -Message "  Utility: $exePath" -Level "INFO" -Component "Install-Vice"
            }
        } else {
            Write-ColoredOutput "No VICE utilities found (this is optional)" "Yellow" "WARNING" "Install-Vice"
            Write-Log -Message "No VICE utilities found in bin directory" -Level "WARNING" -Component "Install-Vice"
        }
        
        # Combine emulators and utilities for compatibility with the rest of the code
        $viceExecutables = $viceEmulators + $viceUtilities
        
        # Configure environment variables
        Write-ColoredOutput "Configuring environment variables..." "Yellow" "INFO" "Install-Vice"
        Write-Log -Message "Starting environment variable configuration" -Level "INFO" -Component "Install-Vice"
        Write-Log -Message "VICE bin directory: $viceBinPath" -Level "INFO" -Component "Install-Vice"
        
        # Add VICE bin directory to system PATH
        try {
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            if ($currentPath -notlike "*$viceBinPath*") {
                $newPath = "$currentPath;$viceBinPath"
                [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
                Write-ColoredOutput "VICE added to system PATH: $viceBinPath" "Green" "SUCCESS" "Install-Vice"
                Write-Log -Message "VICE added to system PATH: $viceBinPath" -Level "SUCCESS" -Component "Install-Vice"
            } else {
                Write-ColoredOutput "VICE already present in system PATH" "Yellow" "WARNING" "Install-Vice"
                Write-Log -Message "VICE already present in system PATH" -Level "WARNING" -Component "Install-Vice"
            }
            
            # Update PATH for current session (with verification to avoid duplicates)
            if ($env:PATH -notlike "*$viceBinPath*") {
                $env:PATH += ";$viceBinPath"
                Write-Log -Message "PATH updated for current session" -Level "INFO" -Component "Install-Vice"
            }
        }
        catch {
            $errorMsg = "Failed to update system PATH: $($_.Exception.Message)"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-Vice"
            Write-ColoredOutput "Warning: $errorMsg" "Yellow" "WARNING" "Install-Vice"
        }
        
        # Set VICE_HOME environment variable
        try {
            [Environment]::SetEnvironmentVariable("VICE_HOME", $viceInstallPath, "Machine")
            $env:VICE_HOME = $viceInstallPath
            Write-ColoredOutput "VICE_HOME environment variable set: $viceInstallPath" "Green" "SUCCESS" "Install-Vice"
            Write-Log -Message "VICE_HOME environment variable set: $viceInstallPath" -Level "SUCCESS" -Component "Install-Vice"
        }
        catch {
            $errorMsg = "Failed to set VICE_HOME environment variable: $($_.Exception.Message)"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-Vice"
            Write-ColoredOutput "Warning: $errorMsg" "Yellow" "WARNING" "Install-Vice"
        }
        
        # Cleanup temporary files
        Write-ColoredOutput "Cleaning up temporary files..." "Yellow" "INFO" "Install-Vice"
        Write-Log -Message "Starting temporary file cleanup" -Level "INFO" -Component "Install-Vice"
        try {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColoredOutput "Cleanup completed" "Green" "SUCCESS" "Install-Vice"
            Write-Log -Message "Temporary file cleanup completed successfully" -Level "SUCCESS" -Component "Install-Vice"
        }
        catch {
            $warningMsg = "Some temporary files may remain in $TempDir : $($_.Exception.Message)"
            Write-ColoredOutput "Warning: $warningMsg" "Yellow" "WARNING" "Install-Vice"
            Write-Log $warningMsg -Level "WARNING" -Component "Install-Vice"
        }
        
        # Verify installation
        Write-ColoredOutput "Verifying installation..." "Yellow" "INFO" "Install-Vice"
        Write-Log -Message "Starting installation verification" -Level "INFO" -Component "Install-Vice"
        try {
            $x64ExePath = Join-Path $viceBinPath "x64sc.exe"
            if (-not (Test-Path $x64ExePath)) {
                $x64ExePath = Join-Path $viceBinPath "x64.exe"
            }
            
            if (Test-Path $x64ExePath) {
                Write-ColoredOutput "VICE installed successfully!" "Green" "SUCCESS" "Install-Vice"
                Write-ColoredOutput "Installation directory: $viceInstallPath" "Green" "SUCCESS" "Install-Vice"
                Write-ColoredOutput "Main executable: $x64ExePath" "Green" "SUCCESS" "Install-Vice"
                Write-ColoredOutput "Emulators: $($viceEmulators -join ', ')" "Green" "SUCCESS" "Install-Vice"
                if ($viceUtilities.Count -gt 0) {
                    Write-ColoredOutput "Utilities: $($viceUtilities -join ', ')" "Green" "SUCCESS" "Install-Vice"
                }
                Write-ColoredOutput "Version: $($viceRelease.Version) r$($viceRelease.Revision)" "Green" "SUCCESS" "Install-Vice"
                
                Write-Log -Message "VICE installation completed successfully!" -Level "SUCCESS" -Component "Install-Vice"
                Write-Log -Message "Installation verified - Main executable found: $x64ExePath" -Level "SUCCESS" -Component "Install-Vice"
                Write-Log -Message "Final installation summary:" -Level "INFO" -Component "Install-Vice"
                Write-Log -Message "  Version: $($viceRelease.Version) r$($viceRelease.Revision)" -Level "INFO" -Component "Install-Vice"
                Write-Log -Message "  Directory: $viceInstallPath" -Level "INFO" -Component "Install-Vice"
                Write-Log -Message "  Emulators: $($viceEmulators -join ', ')" -Level "INFO" -Component "Install-Vice"
                Write-Log -Message "  Utilities: $($viceUtilities -join ', ')" -Level "INFO" -Component "Install-Vice"
            } else {
                $warningMsg = "Installation completed but C64 emulator not found in expected location."
                Write-ColoredOutput $warningMsg "Yellow" "WARNING" "Install-Vice"
                Write-Log $warningMsg -Level "WARNING" -Component "Install-Vice"
            }
        }
        catch {
            $warningMsg = "Installation completed but verification failed: $($_.Exception.Message)"
            Write-ColoredOutput $warningMsg "Yellow" "WARNING" "Install-Vice"
            Write-ColoredOutput "VICE may still be functional. Try opening a new command prompt." "Yellow" "WARNING" "Install-Vice"
            Write-Log $warningMsg -Level "WARNING" -Component "Install-Vice"
        }
        
        Write-FunctionLog -FunctionName "Install-Vice" -Action "EXIT" -Details "Installation process completed"
        
    }
    catch {
        $errorMsg = "Error during VICE installation: $($_.Exception.Message)"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Install-Vice"
        Write-Log $errorMsg -Level "ERROR" -Component "Install-Vice"
        Write-FunctionLog -FunctionName "Install-Vice" -Action "ERROR" -Details $_.Exception.Message
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
$LogFile = Join-Path $LogDirectory "win_install_vice.log"

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
    $LogFile = Join-Path (Get-Location) "win_install_vice.log"
}

# Initialize log file
try {
    # Create or clear the log file
    $logHeader = @"
================================================================================
GameShell65 - VICE Installation Log
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
    Write-ColoredOutput "=== GameShell65 - VICE Emulator Installer ===" "Magenta" "INFO" "MAIN"
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
    
    # Check internet connection using GitHub API
    Write-ColoredOutput "Checking internet connection..." "Yellow" "INFO" "MAIN"
    Write-Log -Message "Testing internet connectivity" -Level "INFO" -Component "MAIN"
    try {
        $null = Invoke-WebRequest -Uri "https://api.github.com" -Method Head -UseBasicParsing -TimeoutSec 10
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
    Write-Log -Message "Creating base installation directory" -Level "INFO" -Component "MAIN"
    New-InstallDirectory $resolvedInstallPath
    
    # Install VICE with custom temp directory
    Write-Log -Message "Starting VICE installation process" -Level "INFO" -Component "MAIN"
    Install-Vice $resolvedInstallPath $tempDir
    
    Write-ColoredOutput "`n=== Installation completed successfully! ===" "Green" "SUCCESS" "MAIN"
    Write-ColoredOutput "IMPORTANT: Restart your session or open a new command window to use VICE." "Yellow" "INFO" "MAIN"
    Write-ColoredOutput "You can start the C64 emulator by running: x64sc.exe or x64.exe" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "Installation directory: $resolvedInstallPath\PCTOOLS\vice" "Cyan" "INFO" "MAIN"
    
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
        Write-Log -Message "Attempting cleanup after failure" -Level "INFO" -Component "MAIN"
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