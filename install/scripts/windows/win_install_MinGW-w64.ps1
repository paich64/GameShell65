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

# Initialize paths - will be set after function definitions
$LogDirectory = ""
$LogFile = ""

$Global:LogStartTime = Get-Date

# Load required assemblies for URL handling
Add-Type -AssemblyName System.Web

# ============================================================================
# FUNCTION DEFINITIONS - All functions defined before use
# ============================================================================

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
        $scriptsDir = Split-Path $scriptPath -Parent      # scripts
        $installDir = Split-Path $scriptsDir -Parent      # install
        $mainTreeRoot = Split-Path $installDir -Parent    # Arborescence_Principale
        
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
            $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\MinGW-w64"
            Write-ColoredOutput "Using installation-based temporary directory: $tempDir" "Cyan" "INFO" "Get-TempDirectory"
        }
        else {
            # User provided temp directory
            $tempDir = Join-Path $UserTempDir "GameShell65_temp_Install\MinGW-w64"
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
                    $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\MinGW-w64"
                }
            }
        }
        
        # Ensure the temp directory path is not too long to avoid path issues
        if ($tempDir.Length -gt 100) {
            Write-ColoredOutput "Warning: Temporary directory path is long ($($tempDir.Length) chars). This may cause issues with some files." "Yellow" "WARNING" "Get-TempDirectory"
            Write-ColoredOutput "Consider using a shorter path like 'C:\Temp\MGW64'" "Yellow" "WARNING" "Get-TempDirectory"
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
    
    Write-ColoredOutput "Downloading from: $Url" "Cyan" "INFO" "Download-File"
    Write-ColoredOutput "Destination: $OutputPath" "Cyan" "INFO" "Download-File"
    
    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            Write-Log -Message "Download attempt $($retryCount + 1) of $MaxRetries" -Level "DEBUG" -Component "Download-File"
            
            # Remove existing file if it exists
            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -Force
                Write-Log -Message "Removed existing file: $OutputPath" -Level "DEBUG" -Component "Download-File"
            }
            
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
                
                # For 7z files without LLVM, expect at least 80MB for a valid MinGW-w64 distribution
                $expectedMinSize = if ($OutputPath.EndsWith(".7z")) { 80MB } else { 1KB }
                
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

# Function to get the latest 5 versions of MinGW-w64 WITHOUT LLVM from GitHub releases
function Get-LatestMinGWVersionsWithoutLLVM {
    param([int]$Count = 5)
    
    Write-FunctionLog -FunctionName "Get-LatestMinGWVersionsWithoutLLVM" -Action "ENTER" -Details "Count: $Count"
    
    Write-ColoredOutput "Searching for the latest $Count MinGW-w64 UCRT POSIX versions WITHOUT LLVM from GitHub..." "Yellow" "INFO" "Get-LatestMinGWVersionsWithoutLLVM"
    
    try {
        # Query winlibs MinGW-w64 GitHub releases API
        $apiUrl = "https://api.github.com/repos/brechtsanders/winlibs_mingw/releases"
        Write-ColoredOutput "Querying winlibs GitHub releases: $apiUrl" "Cyan" "INFO" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-Log -Message "Querying GitHub API: $apiUrl" -Level "INFO" -Component "Get-LatestMinGWVersionsWithoutLLVM"
        
        $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 30 -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        
        if (-not $response -or $response.Count -eq 0) {
            $errorMsg = "Empty response from winlibs GitHub releases API"
            Write-Log $errorMsg -Level "ERROR" -Component "Get-LatestMinGWVersionsWithoutLLVM"
            throw $errorMsg
        }
        
        Write-ColoredOutput "Found $($response.Count) releases from GitHub API" "Cyan" "INFO" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-Log -Message "GitHub API returned $($response.Count) releases" -Level "INFO" -Component "Get-LatestMinGWVersionsWithoutLLVM"
        
        # Find all MinGW-w64 UCRT POSIX x86_64 7z files WITHOUT LLVM
        $mingwReleases = @()
        
        foreach ($release in $response) {
            Write-Log -Message "Processing release: $($release.name) ($($release.tag_name))" -Level "DEBUG" -Component "Get-LatestMinGWVersionsWithoutLLVM"
            
            if ($release.assets) {
                foreach ($asset in $release.assets) {
                    # Look for: winlibs-x86_64-posix-seh-gcc-*-mingw-w64ucrt-*-r*.7z (WITHOUT llvm in filename)
                    # Must NOT include "llvm" in filename
                    if ($asset.name -match "^winlibs-x86_64-posix-seh-gcc-(\d+\.\d+(?:\.\d+)?)-mingw-w64ucrt-(\d+\.\d+(?:\.\d+)?)-r(\d+)\.7z$" -and $asset.name -notmatch "llvm") {
                        $gccVersion = $matches[1]
                        $mingwVersion = $matches[2]
                        $revision = [int]$matches[3]
                        
                        $mingwReleases += @{
                            GccVersion = $gccVersion
                            MinGWVersion = $mingwVersion
                            Revision = $revision
                            FileName = $asset.name
                            DownloadUrl = $asset.browser_download_url
                            Size = $asset.size
                            ReleaseDate = $release.published_at
                            ReleaseName = $release.name
                            SortKey = $gccVersion + "." + $mingwVersion + "." + $revision.ToString("D5")
                        }
                        
                        Write-Log -Message "Found MinGW-w64 UCRT POSIX WITHOUT LLVM release: $($asset.name) (GCC $gccVersion, MinGW $mingwVersion, r$revision, $($asset.size) bytes)" -Level "DEBUG" -Component "Get-LatestMinGWVersionsWithoutLLVM"
                    }
                }
            }
        }
        
        if ($mingwReleases.Count -eq 0) {
            $errorMsg = "No MinGW-w64 UCRT POSIX x86_64 7z files WITHOUT LLVM found in GitHub releases"
            Write-Log $errorMsg -Level "ERROR" -Component "Get-LatestMinGWVersionsWithoutLLVM"
            throw $errorMsg
        }
        
        Write-ColoredOutput "Total MinGW-w64 UCRT POSIX x86_64 7z files WITHOUT LLVM found: $($mingwReleases.Count)" "Cyan" "INFO" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-Log -Message "Total MinGW-w64 releases WITHOUT LLVM found: $($mingwReleases.Count)" -Level "INFO" -Component "Get-LatestMinGWVersionsWithoutLLVM"
        
        # Sort by GCC version first, then by MinGW version, then by revision (all descending)
        $sortedReleases = $mingwReleases | Sort-Object {
            $gccParts = $_.GccVersion.Split('.')
            $gccMajor = [int]$gccParts[0]
            $gccMinor = [int]$gccParts[1]
            $gccPatch = if ($gccParts.Length -gt 2) { [int]$gccParts[2] } else { 0 }
            
            # Create sortable GCC version number: major * 10000 + minor * 100 + patch
            $gccVersionNumber = $gccMajor * 10000 + $gccMinor * 100 + $gccPatch
            return $gccVersionNumber
        }, {
            $mingwParts = $_.MinGWVersion.Split('.')
            $mingwMajor = [int]$mingwParts[0]
            $mingwMinor = [int]$mingwParts[1]
            $mingwPatch = if ($mingwParts.Length -gt 2) { [int]$mingwParts[2] } else { 0 }
            
            # Create sortable MinGW version number
            $mingwVersionNumber = $mingwMajor * 10000 + $mingwMinor * 100 + $mingwPatch
            return $mingwVersionNumber
        }, Revision -Descending
        
        # Get the latest N versions
        $latestReleases = $sortedReleases | Select-Object -First $Count
        
        if ($latestReleases.Count -eq 0) {
            $errorMsg = "No valid MinGW-w64 releases WITHOUT LLVM found after sorting"
            Write-Log $errorMsg -Level "ERROR" -Component "Get-LatestMinGWVersionsWithoutLLVM"
            throw $errorMsg
        }
        
        # Display found versions
        Write-ColoredOutput "`n=== Latest $($latestReleases.Count) MinGW-w64 UCRT POSIX Versions WITHOUT LLVM Found ===" "Magenta" "INFO" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-Log -Message "Displaying latest $($latestReleases.Count) versions WITHOUT LLVM found" -Level "INFO" -Component "Get-LatestMinGWVersionsWithoutLLVM"
        
        for ($i = 0; $i -lt $latestReleases.Count; $i++) {
            $release = $latestReleases[$i]
            $statusText = if ($i -eq 0) { " (SELECTED FOR INSTALLATION)" } else { "" }
            
            Write-ColoredOutput "$($i+1). GCC $($release.GccVersion) + MinGW-w64 $($release.MinGWVersion) UCRT r$($release.Revision)$statusText" $(if ($i -eq 0) { "Green" } else { "Cyan" }) "INFO" "Get-LatestMinGWVersionsWithoutLLVM"
            Write-ColoredOutput "     File: $($release.FileName)" "Gray" "DEBUG" "Get-LatestMinGWVersionsWithoutLLVM"
            Write-ColoredOutput "     Size: $([math]::Round($release.Size / 1MB, 2)) MB" "Gray" "DEBUG" "Get-LatestMinGWVersionsWithoutLLVM"
            Write-ColoredOutput "     Date: $($release.ReleaseDate)" "Gray" "DEBUG" "Get-LatestMinGWVersionsWithoutLLVM"
            Write-ColoredOutput "     URL:  $($release.DownloadUrl)" "Gray" "DEBUG" "Get-LatestMinGWVersionsWithoutLLVM"
            
            Write-Log -Message "Version $($i+1): GCC $($release.GccVersion) + MinGW-w64 $($release.MinGWVersion) r$($release.Revision)$statusText" -Level $(if ($i -eq 0) { "SUCCESS" } else { "INFO" }) -Component "Get-LatestMinGWVersionsWithoutLLVM"
            Write-Log -Message "  File: $($release.FileName), Size: $($release.Size), URL: $($release.DownloadUrl)" -Level "DEBUG" -Component "Get-LatestMinGWVersionsWithoutLLVM"
            
            if ($i -lt $latestReleases.Count - 1) {
                Write-ColoredOutput "" "White" "DEBUG" "Get-LatestMinGWVersionsWithoutLLVM"
            }
        }
        
        $selectedRelease = $latestReleases[0]
        Write-ColoredOutput "`n=== Installation Selection ===" "Magenta" "INFO" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-ColoredOutput "Latest version selected for installation:" "Yellow" "INFO" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-ColoredOutput "GCC $($selectedRelease.GccVersion) + MinGW-w64 $($selectedRelease.MinGWVersion) UCRT r$($selectedRelease.Revision)" "Green" "SUCCESS" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-ColoredOutput "File: $($selectedRelease.FileName)" "Green" "SUCCESS" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-ColoredOutput "Size: $([math]::Round($selectedRelease.Size / 1MB, 2)) MB" "Green" "SUCCESS" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-ColoredOutput "Thread model: POSIX" "Green" "SUCCESS" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-ColoredOutput "Runtime: UCRT" "Green" "SUCCESS" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-ColoredOutput "Architecture: x86_64" "Green" "SUCCESS" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-ColoredOutput "Compilers: GCC only (no LLVM/Clang)" "Green" "SUCCESS" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-ColoredOutput "Includes: GNU tools (GDB, Make, Binutils)" "Green" "SUCCESS" "Get-LatestMinGWVersionsWithoutLLVM"
        
        Write-Log -Message "Final selection: GCC $($selectedRelease.GccVersion) + MinGW-w64 $($selectedRelease.MinGWVersion) r$($selectedRelease.Revision)" -Level "SUCCESS" -Component "Get-LatestMinGWVersionsWithoutLLVM"
        Write-Log -Message "Selected release details: File=$($selectedRelease.FileName), Size=$($selectedRelease.Size), URL=$($selectedRelease.DownloadUrl)" -Level "INFO" -Component "Get-LatestMinGWVersionsWithoutLLVM"
        
        Write-FunctionLog -FunctionName "Get-LatestMinGWVersionsWithoutLLVM" -Action "EXIT" -Details "Success: $($latestReleases.Count) versions found, selected GCC $($selectedRelease.GccVersion)"
        return @{
            SelectedVersion = $selectedRelease
            AllVersions = $latestReleases
        }
    }
    catch {
        Write-ColoredOutput "ERROR: Unable to retrieve MinGW-w64 versions WITHOUT LLVM from GitHub releases" "Red" "ERROR" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-ColoredOutput "Details: $($_.Exception.Message)" "Red" "ERROR" "Get-LatestMinGWVersionsWithoutLLVM"
        Write-ColoredOutput "Using known stable version GCC 15.2.0 without LLVM" "Yellow" "WARNING" "Get-LatestMinGWVersionsWithoutLLVM"
        
        Write-Log -Message "GitHub API failed: $($_.Exception.Message)" -Level "ERROR" -Component "Get-LatestMinGWVersionsWithoutLLVM"
        Write-Log -Message "Falling back to known stable version" -Level "WARNING" -Component "Get-LatestMinGWVersionsWithoutLLVM"
        
        # Fallback to known working version WITHOUT LLVM
        $fallbackRelease = @{
            GccVersion = "15.2.0"
            MinGWVersion = "13.0.0"
            Revision = 1
            FileName = "winlibs-x86_64-posix-seh-gcc-15.2.0-mingw-w64ucrt-13.0.0-r1.7z"
            DownloadUrl = "https://github.com/brechtsanders/winlibs_mingw/releases/download/gcc-15.2.0-mingw-w64ucrt-13.0.0-r1/winlibs-x86_64-posix-seh-gcc-15.2.0-mingw-w64ucrt-13.0.0-r1.7z"
            Size = 125829120
            ReleaseDate = "2025-08-10T12:00:00Z"
            ReleaseName = "GCC 15.2.0 (POSIX threads) + MinGW-w64 13.0.0 UCRT (release 1)"
        }
        
        Write-Log -Message "Using fallback release: GCC $($fallbackRelease.GccVersion) + MinGW-w64 $($fallbackRelease.MinGWVersion) r$($fallbackRelease.Revision)" -Level "INFO" -Component "Get-LatestMinGWVersionsWithoutLLVM"
        Write-FunctionLog -FunctionName "Get-LatestMinGWVersionsWithoutLLVM" -Action "EXIT" -Details "Fallback used"
        return @{
            SelectedVersion = $fallbackRelease
            AllVersions = @($fallbackRelease)
        }
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
function Copy-MinGWFiles {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )
    
    Write-FunctionLog -FunctionName "Copy-MinGWFiles" -Action "ENTER" -Details "Source: $SourcePath, Destination: $DestinationPath"
    
    Write-ColoredOutput "Copying MinGW-w64 files from: $SourcePath" "Yellow" "INFO" "Copy-MinGWFiles"
    Write-ColoredOutput "To: $DestinationPath" "Yellow" "INFO" "Copy-MinGWFiles"
    Write-Log -Message "Starting file copy from $SourcePath to $DestinationPath" -Level "INFO" -Component "Copy-MinGWFiles"
    
    try {
        # Try standard copy first
        Write-Log -Message "Attempting standard PowerShell copy" -Level "DEBUG" -Component "Copy-MinGWFiles"
        Copy-Item -Path "$SourcePath\*" -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
        Write-ColoredOutput "Standard copy completed successfully" "Green" "SUCCESS" "Copy-MinGWFiles"
        Write-Log -Message "Standard copy completed successfully" -Level "SUCCESS" -Component "Copy-MinGWFiles"
        Write-FunctionLog -FunctionName "Copy-MinGWFiles" -Action "EXIT" -Details "Standard copy success"
    }
    catch [System.IO.PathTooLongException] {
        Write-ColoredOutput "Long path detected, using robocopy for file transfer..." "Yellow" "WARNING" "Copy-MinGWFiles"
        Write-Log -Message "Long path detected, switching to robocopy" -Level "WARNING" -Component "Copy-MinGWFiles"
        
        # Use robocopy for long path support
        Write-Log -Message "Executing robocopy with parameters: /E /R:1 /W:1 /NP /NDL /NJH /NJS" -Level "DEBUG" -Component "Copy-MinGWFiles"
        $robocopyResult = robocopy "$SourcePath" "$DestinationPath" /E /R:1 /W:1 /NP /NDL /NJH /NJS
        
        # Check robocopy exit code (0-7 are success codes)
        Write-Log -Message "Robocopy completed with exit code: $LASTEXITCODE" -Level "INFO" -Component "Copy-MinGWFiles"
        if ($LASTEXITCODE -le 7) {
            Write-ColoredOutput "Robocopy transfer completed successfully" "Green" "SUCCESS" "Copy-MinGWFiles"
            Write-Log -Message "Robocopy transfer completed successfully" -Level "SUCCESS" -Component "Copy-MinGWFiles"
        } else {
            $warningMsg = "Some files may not have been copied (robocopy exit code: $LASTEXITCODE)"
            Write-ColoredOutput "Warning: $warningMsg" "Yellow" "WARNING" "Copy-MinGWFiles"
            Write-Log $warningMsg -Level "WARNING" -Component "Copy-MinGWFiles"
        }
        Write-FunctionLog -FunctionName "Copy-MinGWFiles" -Action "EXIT" -Details "Robocopy method used"
    }
    catch {
        $errorMsg = "Error during file copy: $($_.Exception.Message)"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Copy-MinGWFiles"
        Write-Log $errorMsg -Level "ERROR" -Component "Copy-MinGWFiles"
        Write-FunctionLog -FunctionName "Copy-MinGWFiles" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to extract 7z archive files
function Extract-MinGWArchive {
    param(
        [string]$ArchivePath,
        [string]$ExtractPath,
        [string]$SevenZipPath
    )
    
    Write-FunctionLog -FunctionName "Extract-MinGWArchive" -Action "ENTER" -Details "Archive: $ArchivePath, Extract: $ExtractPath, 7z: $SevenZipPath"
    
    Write-ColoredOutput "Extracting MinGW-w64 archive: $(Split-Path $ArchivePath -Leaf)" "Yellow" "INFO" "Extract-MinGWArchive"
    Write-Log -Message "Starting 7z extraction: $(Split-Path $ArchivePath -Leaf)" -Level "INFO" -Component "Extract-MinGWArchive"
    
    try {
        # Verify the 7z file exists
        if (-not (Test-Path $ArchivePath)) {
            $errorMsg = "Archive file not found: $ArchivePath"
            Write-Log $errorMsg -Level "ERROR" -Component "Extract-MinGWArchive"
            throw $errorMsg
        }
        
        Write-Log -Message "Archive file verified: $ArchivePath" -Level "DEBUG" -Component "Extract-MinGWArchive"
        
        # Create extraction directory
        New-InstallDirectory $ExtractPath
        
        # Extract using 7-Zip
        Write-ColoredOutput "Using 7-Zip: $SevenZipPath" "Cyan" "INFO" "Extract-MinGWArchive"
        Write-Log -Message "Using 7-Zip executable: $SevenZipPath" -Level "INFO" -Component "Extract-MinGWArchive"
        
        $extractArgs = @("x", "`"$ArchivePath`"", "-o`"$ExtractPath`"", "-y")
        $extractCommand = "`"$SevenZipPath`" $($extractArgs -join ' ')"
        
        Write-ColoredOutput "Executing: $extractCommand" "Gray" "DEBUG" "Extract-MinGWArchive"
        Write-Log -Message "Executing 7z command: $extractCommand" -Level "DEBUG" -Component "Extract-MinGWArchive"
        
        $extractProcess = Start-Process -FilePath $SevenZipPath -ArgumentList $extractArgs -Wait -PassThru -NoNewWindow
        
        Write-Log -Message "7z extraction process completed with exit code: $($extractProcess.ExitCode)" -Level "INFO" -Component "Extract-MinGWArchive"
        
        if ($extractProcess.ExitCode -eq 0) {
            Write-ColoredOutput "7z extraction completed successfully" "Green" "SUCCESS" "Extract-MinGWArchive"
            Write-Log -Message "7z extraction completed successfully" -Level "SUCCESS" -Component "Extract-MinGWArchive"
            
            # Verify extraction results
            $extractedItems = Get-ChildItem -Path $ExtractPath -ErrorAction SilentlyContinue
            Write-ColoredOutput "Extracted $($extractedItems.Count) items" "Cyan" "INFO" "Extract-MinGWArchive"
            Write-Log -Message "Extraction verification: $($extractedItems.Count) items extracted" -Level "INFO" -Component "Extract-MinGWArchive"
            
            Write-FunctionLog -FunctionName "Extract-MinGWArchive" -Action "EXIT" -Details "Success: $($extractedItems.Count) items"
            return $ExtractPath
        }
        else {
            $errorMsg = "7-Zip extraction failed with exit code: $($extractProcess.ExitCode)"
            Write-Log $errorMsg -Level "ERROR" -Component "Extract-MinGWArchive"
            throw $errorMsg
        }
    }
    catch {
        $errorMsg = "7z extraction error: $($_.Exception.Message)"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Extract-MinGWArchive"
        Write-Log $errorMsg -Level "ERROR" -Component "Extract-MinGWArchive"
        Write-FunctionLog -FunctionName "Extract-MinGWArchive" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to create make.exe alias for mingw32-make.exe
function New-MakeAlias {
    param([string]$BinPath)
    
    Write-FunctionLog -FunctionName "New-MakeAlias" -Action "ENTER" -Details "BinPath: $BinPath"
    
    $mingwMakePath = Join-Path $BinPath "mingw32-make.exe"
    $makeAliasPath = Join-Path $BinPath "make.exe"
    
    Write-ColoredOutput "Creating make.exe alias for mingw32-make.exe..." "Yellow" "INFO" "New-MakeAlias"
    Write-Log -Message "Creating make.exe alias from $mingwMakePath to $makeAliasPath" -Level "INFO" -Component "New-MakeAlias"
    
    try {
        if (Test-Path $mingwMakePath) {
            # Create a hard link from make.exe to mingw32-make.exe
            if (Test-Path $makeAliasPath) {
                Remove-Item $makeAliasPath -Force
                Write-Log -Message "Removed existing make.exe" -Level "DEBUG" -Component "New-MakeAlias"
            }
            
            # Use New-Item to create hard link
            New-Item -ItemType HardLink -Path $makeAliasPath -Target $mingwMakePath -Force | Out-Null
            
            if (Test-Path $makeAliasPath) {
                Write-ColoredOutput "Successfully created make.exe alias" "Green" "SUCCESS" "New-MakeAlias"
                Write-Log -Message "Successfully created make.exe hard link to mingw32-make.exe" -Level "SUCCESS" -Component "New-MakeAlias"
                Write-FunctionLog -FunctionName "New-MakeAlias" -Action "EXIT" -Details "Success"
                return $true
            } else {
                throw "Hard link creation failed - make.exe not found after creation"
            }
        } else {
            $warningMsg = "mingw32-make.exe not found at: $mingwMakePath"
            Write-ColoredOutput "Warning: $warningMsg" "Yellow" "WARNING" "New-MakeAlias"
            Write-Log $warningMsg -Level "WARNING" -Component "New-MakeAlias"
            Write-FunctionLog -FunctionName "New-MakeAlias" -Action "EXIT" -Details "mingw32-make.exe not found"
            return $false
        }
    }
    catch {
        $errorMsg = "Failed to create make.exe alias: $($_.Exception.Message)"
        Write-ColoredOutput "Warning: $errorMsg" "Yellow" "WARNING" "New-MakeAlias"
        Write-Log $errorMsg -Level "WARNING" -Component "New-MakeAlias"
        Write-FunctionLog -FunctionName "New-MakeAlias" -Action "ERROR" -Details $_.Exception.Message
        return $false
    }
}

# Function to display all installed executables
function Show-InstalledExecutables {
    param([string]$BinPath)
    
    Write-FunctionLog -FunctionName "Show-InstalledExecutables" -Action "ENTER" -Details "BinPath: $BinPath"
    
    Write-ColoredOutput "`n=== ALL INSTALLED EXECUTABLES ===" "Magenta" "INFO" "Show-InstalledExecutables"
    Write-Log -Message "Displaying all installed executables from: $BinPath" -Level "INFO" -Component "Show-InstalledExecutables"
    
    try {
        if (Test-Path $BinPath) {
            $executables = Get-ChildItem -Path $BinPath -Name "*.exe" -ErrorAction SilentlyContinue | Sort-Object
            
            if ($executables.Count -gt 0) {
                Write-ColoredOutput "Found $($executables.Count) executable files in bin directory:" "Cyan" "INFO" "Show-InstalledExecutables"
                Write-Log -Message "Found $($executables.Count) executable files" -Level "INFO" -Component "Show-InstalledExecutables"
                
                # Group executables by category for better display
                $gccExecutables = @()
                $mingwExecutables = @()
                $otherExecutables = @()
                
                foreach ($exe in $executables) {
                    if ($exe -match "^(gcc|g\+\+|gfortran|gcov)") {
                        $gccExecutables += $exe
                    } elseif ($exe -match "^(mingw|make|windres|dlltool|ar|ranlib|nm|objdump|objcopy|strip|size|strings|addr2line|readelf|gprof|gdb)") {
                        $mingwExecutables += $exe
                    } else {
                        $otherExecutables += $exe
                    }
                }
                
                # Display GCC toolchain
                if ($gccExecutables.Count -gt 0) {
                    Write-ColoredOutput "`nGCC Toolchain ($($gccExecutables.Count) executables):" "Yellow" "INFO" "Show-InstalledExecutables"
                    foreach ($exe in $gccExecutables) {
                        $exePath = Join-Path $BinPath $exe
                        Write-ColoredOutput "  - $exe" "Green" "INFO" "Show-InstalledExecutables"
                        Write-Log -Message "  GCC: $exePath" -Level "INFO" -Component "Show-InstalledExecutables"
                    }
                }
                
                # Display MinGW utilities
                if ($mingwExecutables.Count -gt 0) {
                    Write-ColoredOutput "`nMinGW-w64 Utilities & GNU Tools ($($mingwExecutables.Count) executables):" "Yellow" "INFO" "Show-InstalledExecutables"
                    foreach ($exe in $mingwExecutables) {
                        $exePath = Join-Path $BinPath $exe
                        Write-ColoredOutput "  - $exe" "White" "INFO" "Show-InstalledExecutables"
                        Write-Log -Message "  MinGW: $exePath" -Level "INFO" -Component "Show-InstalledExecutables"
                    }
                }
                
                # Display other executables
                if ($otherExecutables.Count -gt 0) {
                    Write-ColoredOutput "`nOther Tools ($($otherExecutables.Count) executables):" "Yellow" "INFO" "Show-InstalledExecutables"
                    foreach ($exe in $otherExecutables) {
                        $exePath = Join-Path $BinPath $exe
                        Write-ColoredOutput "  - $exe" "Gray" "INFO" "Show-InstalledExecutables"
                        Write-Log -Message "  Other: $exePath" -Level "INFO" -Component "Show-InstalledExecutables"
                    }
                }
                
                # Summary
                Write-ColoredOutput "`nSummary:" "Magenta" "INFO" "Show-InstalledExecutables"
                Write-ColoredOutput "Total executables installed: $($executables.Count)" "Cyan" "INFO" "Show-InstalledExecutables"
                Write-ColoredOutput "GCC toolchain: $($gccExecutables.Count) executables" "Green" "INFO" "Show-InstalledExecutables"
                Write-ColoredOutput "MinGW & GNU utilities: $($mingwExecutables.Count) executables" "White" "INFO" "Show-InstalledExecutables"
                Write-ColoredOutput "Other tools: $($otherExecutables.Count) executables" "Gray" "INFO" "Show-InstalledExecutables"
                
                Write-Log -Message "Executable summary: Total=$($executables.Count), GCC=$($gccExecutables.Count), MinGW=$($mingwExecutables.Count), Other=$($otherExecutables.Count)" -Level "INFO" -Component "Show-InstalledExecutables"
                
            } else {
                Write-ColoredOutput "No executable files found in bin directory" "Yellow" "WARNING" "Show-InstalledExecutables"
                Write-Log -Message "No executable files found in bin directory" -Level "WARNING" -Component "Show-InstalledExecutables"
            }
        } else {
            Write-ColoredOutput "Bin directory not found: $BinPath" "Red" "ERROR" "Show-InstalledExecutables"
            Write-Log -Message "Bin directory not found: $BinPath" -Level "ERROR" -Component "Show-InstalledExecutables"
        }
        
        Write-FunctionLog -FunctionName "Show-InstalledExecutables" -Action "EXIT" -Details "Success"
        
    } catch {
        $errorMsg = "Error displaying installed executables: $($_.Exception.Message)"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Show-InstalledExecutables"
        Write-Log $errorMsg -Level "ERROR" -Component "Show-InstalledExecutables"
        Write-FunctionLog -FunctionName "Show-InstalledExecutables" -Action "ERROR" -Details $_.Exception.Message
    }
}

# Function to install MinGW-w64 WITHOUT LLVM with configurable temp directory
function Install-MinGWWithoutLLVM {
    param(
        [string]$BaseInstallPath,
        [string]$TempDir
    )
    
    Write-FunctionLog -FunctionName "Install-MinGWWithoutLLVM" -Action "ENTER" -Details "BaseInstallPath: $BaseInstallPath, TempDir: $TempDir"
    
    Write-ColoredOutput "`n=== MinGW-w64 UCRT POSIX Installation (GCC Only) ===" "Magenta" "INFO" "Install-MinGWWithoutLLVM"
    Write-Log -Message "Starting MinGW-w64 WITHOUT LLVM installation process" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
    Write-Log -Message "Base installation path: $BaseInstallPath" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
    Write-Log -Message "Temporary directory: $TempDir" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
    
    try {
        # Get latest versions from GitHub (top 5 WITHOUT LLVM)
        Write-Log -Message "Getting latest MinGW-w64 WITHOUT LLVM version information" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        $versionResults = Get-LatestMinGWVersionsWithoutLLVM -Count 5
        $mingwRelease = $versionResults.SelectedVersion
        $allVersions = $versionResults.AllVersions
        
        Write-ColoredOutput "`nInstalling selected MinGW-w64 GCC v$($mingwRelease.GccVersion) + MinGW-w64 v$($mingwRelease.MinGWVersion) r$($mingwRelease.Revision) from GitHub" "Cyan" "INFO" "Install-MinGWWithoutLLVM"
        Write-Log -Message "Selected MinGW-w64 version: GCC $($mingwRelease.GccVersion) + MinGW-w64 $($mingwRelease.MinGWVersion) r$($mingwRelease.Revision)" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        
        # Configure paths - Install to PCTOOLS\MinGW-w64 subdirectory
        $pctoolsPath = Join-Path $BaseInstallPath "PCTOOLS"
        $mingwInstallPath = Join-Path $pctoolsPath "MinGW-w64"
        $mingw7zPath = Join-Path $TempDir "mingw.7z"
        $mingwExtractPath = Join-Path $TempDir "extract"
        
        Write-Log -Message "Installation paths configured:" -Level "DEBUG" -Component "Install-MinGWWithoutLLVM"
        Write-Log -Message "  PCTOOLS path: $pctoolsPath" -Level "DEBUG" -Component "Install-MinGWWithoutLLVM"
        Write-Log -Message "  Install path: $mingwInstallPath" -Level "DEBUG" -Component "Install-MinGWWithoutLLVM"
        Write-Log -Message "  Download path: $mingw7zPath" -Level "DEBUG" -Component "Install-MinGWWithoutLLVM"
        Write-Log -Message "  Extract path: $mingwExtractPath" -Level "DEBUG" -Component "Install-MinGWWithoutLLVM"
        
        # Create directories
        Write-Log -Message "Creating required directories" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        New-InstallDirectory $pctoolsPath
        New-InstallDirectory $mingwInstallPath
        New-InstallDirectory $TempDir
        New-InstallDirectory $mingwExtractPath
        
        # Install 7-Zip if needed
        Write-Log -Message "Ensuring 7-Zip availability" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        $sevenZipExe = Install-7Zip $TempDir
        Write-Log -Message "7-Zip executable: $sevenZipExe" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        
        # Download MinGW-w64 WITHOUT LLVM
        Write-ColoredOutput "`nDownloading selected version WITHOUT LLVM..." "Yellow" "INFO" "Install-MinGWWithoutLLVM"
        Write-ColoredOutput "From: $($mingwRelease.DownloadUrl)" "Cyan" "INFO" "Install-MinGWWithoutLLVM"
        Write-Log -Message "Starting MinGW-w64 WITHOUT LLVM download from: $($mingwRelease.DownloadUrl)" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        Download-File $mingwRelease.DownloadUrl $mingw7zPath
        
        # Verify downloaded file
        $fileSize = (Get-Item $mingw7zPath).Length
        Write-ColoredOutput "Downloaded file size: $fileSize bytes" "Cyan" "INFO" "Install-MinGWWithoutLLVM"
        Write-Log -Message "Downloaded file verification: $fileSize bytes" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        
        if ($fileSize -lt 80MB) {
            $errorMsg = "Downloaded file is too small, may be corrupted (GCC-only packages should be >80MB)"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-MinGWWithoutLLVM"
            throw $errorMsg
        }
        
        # Extract with 7-Zip
        Write-Log -Message "Starting archive extraction" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        $actualExtractPath = Extract-MinGWArchive $mingw7zPath $mingwExtractPath $sevenZipExe
        
        # Find the extracted content
        $extractedItems = Get-ChildItem -Path $actualExtractPath -ErrorAction SilentlyContinue
        Write-ColoredOutput "Found $($extractedItems.Count) items in extracted archive" "Cyan" "INFO" "Install-MinGWWithoutLLVM"
        Write-Log -Message "Archive contents: $($extractedItems.Count) items found" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        
        # Look for MinGW directory structure (usually mingw64 folder)
        $sourceDirectory = $actualExtractPath
        Write-Log -Message "Initial source directory: $sourceDirectory" -Level "DEBUG" -Component "Install-MinGWWithoutLLVM"
        
        # Check if there's a mingw64 subdirectory
        $mingwSubDir = $extractedItems | Where-Object { $_.PSIsContainer -and ($_.Name -match "mingw64" -or $_.Name -match "mingw32") } | Select-Object -First 1
        if ($mingwSubDir) {
            $sourceDirectory = $mingwSubDir.FullName
            Write-ColoredOutput "Using MinGW subdirectory: $($mingwSubDir.Name)" "Cyan" "INFO" "Install-MinGWWithoutLLVM"
            Write-Log -Message "Found MinGW subdirectory: $($mingwSubDir.Name), using: $sourceDirectory" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        }
        else {
            Write-Log -Message "No MinGW subdirectory found, using root extract directory" -Level "DEBUG" -Component "Install-MinGWWithoutLLVM"
        }
        
        # Copy all files with long path handling
        Write-ColoredOutput "Installing to: $mingwInstallPath" "Yellow" "INFO" "Install-MinGWWithoutLLVM"
        Write-Log -Message "Starting file installation to: $mingwInstallPath" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        Copy-MinGWFiles $sourceDirectory $mingwInstallPath
        
        # Find GCC executables in the installed directory
        Write-Log -Message "Searching for GCC executables" -Level "DEBUG" -Component "Install-MinGWWithoutLLVM"
        $binPath = Join-Path $mingwInstallPath "bin"
        $gccExecutables = Get-ChildItem -Path $binPath -Name "*.exe" -ErrorAction SilentlyContinue | Where-Object { $_ -match "(gcc|g\+\+|gdb|make)" }
        
        if ($gccExecutables.Count -eq 0) {
            $errorMsg = "GCC executables not found after installation"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-MinGWWithoutLLVM"
            throw $errorMsg
        }
        
        Write-ColoredOutput "Found GCC executables:" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
        Write-Log -Message "GCC executables found: $($gccExecutables.Count)" -Level "SUCCESS" -Component "Install-MinGWWithoutLLVM"
        foreach ($exe in $gccExecutables[0..4]) {  # Show first 5 executables
            $exePath = Join-Path $binPath $exe
            Write-ColoredOutput "  - $exePath" "Cyan" "INFO" "Install-MinGWWithoutLLVM"
            Write-Log -Message "  GCC Executable: $exePath" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        }
        
        # Create make.exe alias for mingw32-make.exe
        Write-ColoredOutput "Creating make.exe alias..." "Yellow" "INFO" "Install-MinGWWithoutLLVM"
        $makeAliasCreated = New-MakeAlias $binPath
        if ($makeAliasCreated) {
            Write-ColoredOutput "make.exe alias created successfully" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
        } else {
            Write-ColoredOutput "Warning: Could not create make.exe alias" "Yellow" "WARNING" "Install-MinGWWithoutLLVM"
        }
        
        # Configure environment variables
        Write-ColoredOutput "Configuring environment variables..." "Yellow" "INFO" "Install-MinGWWithoutLLVM"
        Write-Log -Message "Starting environment variable configuration" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        
        # Determine the correct bin directory
        $mingwBinPath = $binPath
        Write-Log -Message "MinGW-w64 bin directory: $mingwBinPath" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        
        # Add MinGW bin directory to system PATH (at the beginning for priority)
        # Note: MinGW is added at the beginning to ensure compiler priority over other tools
        # This differs from JDK installation which adds to the end for safety
        try {
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            if ($currentPath -notlike "*$mingwBinPath*") {
                $newPath = "$mingwBinPath;$currentPath"
                [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
                Write-ColoredOutput "MinGW-w64 added to system PATH (at beginning for priority): $mingwBinPath" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
                Write-Log -Message "MinGW-w64 added to system PATH at beginning: $mingwBinPath" -Level "SUCCESS" -Component "Install-MinGWWithoutLLVM"
            } else {
                Write-ColoredOutput "MinGW-w64 already present in system PATH" "Yellow" "WARNING" "Install-MinGWWithoutLLVM"
                Write-Log -Message "MinGW-w64 already present in system PATH" -Level "WARNING" -Component "Install-MinGWWithoutLLVM"
            }
            
            # Update PATH for current session
            $env:PATH = "$mingwBinPath;$env:PATH"
            Write-Log -Message "Current session PATH updated" -Level "DEBUG" -Component "Install-MinGWWithoutLLVM"
        }
        catch {
            $errorMsg = "Failed to update system PATH: $($_.Exception.Message)"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-MinGWWithoutLLVM"
            Write-ColoredOutput "Warning: $errorMsg" "Yellow" "WARNING" "Install-MinGWWithoutLLVM"
        }
        
        # Set MINGW_HOME environment variable
        try {
            [Environment]::SetEnvironmentVariable("MINGW_HOME", $mingwInstallPath, "Machine")
            $env:MINGW_HOME = $mingwInstallPath
            Write-ColoredOutput "MINGW_HOME environment variable set: $mingwInstallPath" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
            Write-Log -Message "MINGW_HOME environment variable set: $mingwInstallPath" -Level "SUCCESS" -Component "Install-MinGWWithoutLLVM"
        }
        catch {
            $errorMsg = "Failed to set MINGW_HOME environment variable: $($_.Exception.Message)"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-MinGWWithoutLLVM"
            Write-ColoredOutput "Warning: $errorMsg" "Yellow" "WARNING" "Install-MinGWWithoutLLVM"
        }
        
        # Display all installed executables
        Show-InstalledExecutables $mingwBinPath
        
        # Cleanup temporary files
        Write-ColoredOutput "Cleaning up temporary files..." "Yellow" "INFO" "Install-MinGWWithoutLLVM"
        Write-Log -Message "Starting temporary file cleanup" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        try {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColoredOutput "Cleanup completed" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
            Write-Log -Message "Temporary file cleanup completed successfully" -Level "SUCCESS" -Component "Install-MinGWWithoutLLVM"
        }
        catch {
            $warningMsg = "Some temporary files may remain in $TempDir : $($_.Exception.Message)"
            Write-ColoredOutput "Warning: $warningMsg" "Yellow" "WARNING" "Install-MinGWWithoutLLVM"
            Write-Log $warningMsg -Level "WARNING" -Component "Install-MinGWWithoutLLVM"
        }
        
        # Verify installation
        Write-ColoredOutput "Verifying installation..." "Yellow" "INFO" "Install-MinGWWithoutLLVM"
        Write-Log -Message "Starting installation verification" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
        try {
            $gccExePath = Join-Path $mingwBinPath "gcc.exe"
            $gppExePath = Join-Path $mingwBinPath "g++.exe"
            $makeExePath = Join-Path $mingwBinPath "make.exe"
            
            if ((Test-Path $gccExePath) -and (Test-Path $gppExePath)) {
                # Test GCC version
                try {
                    $gccVersion = & $gccExePath --version 2>$null | Select-Object -First 1
                    Write-ColoredOutput "`n=== INSTALLATION SUCCESSFUL ===" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
                    Write-ColoredOutput "MinGW-w64 (GCC only) installed successfully!" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
                    Write-ColoredOutput "Installation directory: $mingwInstallPath" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
                    Write-ColoredOutput "Binary directory: $mingwBinPath" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
                    Write-ColoredOutput "GCC version: $gccVersion" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
                    Write-ColoredOutput "MinGW-w64 version: $($mingwRelease.MinGWVersion)" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
                    Write-ColoredOutput "Thread model: POSIX" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
                    Write-ColoredOutput "Runtime: UCRT" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
                    Write-ColoredOutput "Architecture: x86_64" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
                    Write-ColoredOutput "Compilers: GCC toolchain (without LLVM/Clang)" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
                    
                    # Check make.exe alias
                    if (Test-Path $makeExePath) {
                        Write-ColoredOutput "make.exe alias available: $makeExePath" "Green" "SUCCESS" "Install-MinGWWithoutLLVM"
                    } else {
                        Write-ColoredOutput "Warning: make.exe alias not found" "Yellow" "WARNING" "Install-MinGWWithoutLLVM"
                    }
                    
                    Write-Log -Message "MinGW-w64 (GCC only) installation completed successfully!" -Level "SUCCESS" -Component "Install-MinGWWithoutLLVM"
                    Write-Log -Message "Installation verified - GCC executable found: $gccExePath" -Level "SUCCESS" -Component "Install-MinGWWithoutLLVM"
                    Write-Log -Message "GCC version output: $gccVersion" -Level "SUCCESS" -Component "Install-MinGWWithoutLLVM"
                    Write-Log -Message "Final installation summary:" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
                    Write-Log -Message "  GCC Version: $($mingwRelease.GccVersion)" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
                    Write-Log -Message "  MinGW-w64 Version: $($mingwRelease.MinGWVersion)" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
                    Write-Log -Message "  Directory: $mingwInstallPath" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
                    Write-Log -Message "  Binary Directory: $mingwBinPath" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
                    Write-Log -Message "  Thread model: POSIX" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
                    Write-Log -Message "  Runtime: UCRT" -Level "INFO" -Component "Install-MinGWWithoutLLVM"
                }
                catch {
                    Write-ColoredOutput "Installation completed but compiler version check failed: $($_.Exception.Message)" "Yellow" "WARNING" "Install-MinGWWithoutLLVM"
                    Write-Log -Message "Compiler version check failed: $($_.Exception.Message)" -Level "WARNING" -Component "Install-MinGWWithoutLLVM"
                }
            } else {
                $warningMsg = "Installation completed but some compiler executables not found in expected location."
                Write-ColoredOutput $warningMsg "Yellow" "WARNING" "Install-MinGWWithoutLLVM"
                Write-Log $warningMsg -Level "WARNING" -Component "Install-MinGWWithoutLLVM"
            }
        }
        catch {
            $warningMsg = "Installation completed but verification failed: $($_.Exception.Message)"
            Write-ColoredOutput $warningMsg "Yellow" "WARNING" "Install-MinGWWithoutLLVM"
            Write-ColoredOutput "MinGW-w64 may still be functional. Try opening a new command prompt." "Yellow" "WARNING" "Install-MinGWWithoutLLVM"
            Write-Log $warningMsg -Level "WARNING" -Component "Install-MinGWWithoutLLVM"
        }
        
        Write-FunctionLog -FunctionName "Install-MinGWWithoutLLVM" -Action "EXIT" -Details "Installation process completed"
        
    }
    catch {
        $errorMsg = "Error during MinGW-w64 (GCC only) installation: $($_.Exception.Message)"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Install-MinGWWithoutLLVM"
        Write-Log $errorMsg -Level "ERROR" -Component "Install-MinGWWithoutLLVM"
        Write-FunctionLog -FunctionName "Install-MinGWWithoutLLVM" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# ============================================================================
# PATH DETERMINATION - After all functions are defined
# ============================================================================

# Determine installation path and log directory
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
$LogFile = Join-Path $LogDirectory "win_install_MinGW-w64.log"

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
    $LogFile = Join-Path (Get-Location) "win_install_MinGW-w64.log"
}

# ============================================================================
# LOG INITIALIZATION
# ============================================================================

# Initialize log file
try {
    # Create or clear the log file
    $logHeader = @"
================================================================================
GameShell65 - MinGW-w64 (GCC Only) Installation Log
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

# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

# Main script
try {
    Write-ColoredOutput "=== GameShell65 - MinGW-w64 UCRT POSIX Installer (GCC Only) ===" "Magenta" "INFO" "MAIN"
    Write-ColoredOutput "Base installation directory: $resolvedInstallPath" "Cyan" "INFO" "MAIN"
    Write-Log -Message "Script execution started" -Level "INFO" -Component "MAIN"
    Write-Log -Message "Parameters - InstallationPath: $InstallationPath, TempDirectory: $TempDirectory" -Level "INFO" -Component "MAIN"
    Write-Log -Message "Resolved paths - InstallPath: $resolvedInstallPath, LogDirectory: $LogDirectory" -Level "INFO" -Component "MAIN"
    
    # Get and validate temporary directory
    Write-Log -Message "Determining temporary directory" -Level "INFO" -Component "MAIN"
    $tempDir = Get-TempDirectory -UserTempDir $TempDirectory -BaseInstallPath $resolvedInstallPath
    
    # Check if script is running as administrator
    Write-Log -Message "Checking administrator privileges" -Level "DEBUG" -Component "MAIN"
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
    
    # Install MinGW-w64 WITHOUT LLVM with custom temp directory
    Write-Log -Message "Starting MinGW-w64 (GCC only) installation process" -Level "INFO" -Component "MAIN"
    Install-MinGWWithoutLLVM $resolvedInstallPath $tempDir
    
    Write-ColoredOutput "`n=== Installation completed successfully! ===" "Green" "SUCCESS" "MAIN"
    Write-ColoredOutput "IMPORTANT: Restart your session or open a new command window to use MinGW-w64." "Yellow" "INFO" "MAIN"
    Write-ColoredOutput "You can start compiling with GCC: gcc --version" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "You can use make: make --version" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "MinGW-w64 (GCC only) installed in: $resolvedInstallPath\PCTOOLS\MinGW-w64" "Cyan" "INFO" "MAIN"
    
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