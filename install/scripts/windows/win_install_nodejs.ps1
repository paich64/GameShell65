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
            $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\nodejs"
            Write-ColoredOutput "Using installation-based temporary directory: $tempDir" "Cyan" "INFO" "Get-TempDirectory"
        }
        else {
            # User provided temp directory
            $tempDir = Join-Path $UserTempDir "GameShell65_temp_Install\nodejs"
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
                    $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\nodejs"
                }
            }
        }
        
        # Ensure the temp directory path is not too long to avoid path issues
        if ($tempDir.Length -gt 100) {
            Write-ColoredOutput "Warning: Temporary directory path is long ($($tempDir.Length) chars). This may cause issues with some files." "Yellow" "WARNING" "Get-TempDirectory"
            Write-ColoredOutput "Consider using a shorter path like 'C:\Temp\MS65'" "Yellow" "WARNING" "Get-TempDirectory"
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
        
        $fileSize = (Get-Item $OutputPath).Length
        Write-ColoredOutput "Download completed successfully" "Green" "SUCCESS" "Download-File"
        Write-Log -Message "Download completed - Size: $fileSize bytes, Duration: $([math]::Round($downloadDuration, 2)) seconds" -Level "SUCCESS" -Component "Download-File"
        
        Write-FunctionLog -FunctionName "Download-File" -Action "EXIT" -Details "Success: $OutputPath"
    }
    catch {
        Write-ColoredOutput "Download error: $($_.Exception.Message)" "Red" "ERROR" "Download-File"
        Write-FunctionLog -FunctionName "Download-File" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to get the latest LTS version of Node.js with proper version sorting
function Get-LatestNodeJSVersion {
    Write-FunctionLog -FunctionName "Get-LatestNodeJSVersion" -Action "ENTER"
    
    Write-ColoredOutput "Searching for the latest LTS version of Node.js..." "Yellow" "INFO" "Get-LatestNodeJSVersion"
    
    try {
        # Call to the official Node.js API to get version information
        $apiUrl = "https://nodejs.org/dist/index.json"
        Write-ColoredOutput "Querying Node.js API: $apiUrl" "Cyan" "INFO" "Get-LatestNodeJSVersion"
        Write-Log -Message "Attempting to fetch Node.js versions from official API: $apiUrl" -Level "INFO" -Component "Get-LatestNodeJSVersion"
        
        $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 30
        
        if (-not $response -or $response.Count -eq 0) {
            throw "Empty response from Node.js API"
        }
        
        Write-Log -Message "Node.js API response received with $($response.Count) versions" -Level "SUCCESS" -Component "Get-LatestNodeJSVersion"
        
        # Filter to get LTS versions only
        $ltsVersions = $response | Where-Object { 
            $_.lts -ne $false -and $_.lts -ne $null -and $_.lts -ne "" 
        }
        
        if ($ltsVersions.Count -eq 0) {
            throw "No LTS version found in API response"
        }
        
        Write-ColoredOutput "Found $($ltsVersions.Count) LTS versions" "Cyan" "SUCCESS" "Get-LatestNodeJSVersion"
        Write-Log -Message "Found $($ltsVersions.Count) LTS versions in API response" -Level "SUCCESS" -Component "Get-LatestNodeJSVersion"
        
        # Sort versions properly by converting to System.Version for numeric comparison
        Write-Log -Message "Starting version sorting using System.Version for proper numeric comparison" -Level "INFO" -Component "Get-LatestNodeJSVersion"
        $sortedLtsVersions = $ltsVersions | Sort-Object {
            # Convert version string to System.Version object for proper numeric sorting
            try {
                $versionString = $_.version.TrimStart('v')
                # Handle versions like "22.18.0" properly
                $systemVersion = [System.Version]$versionString
                Write-Log -Message "Version $($_.version) converted to System.Version: $systemVersion" -Level "DEBUG" -Component "Get-LatestNodeJSVersion"
                return $systemVersion
            }
            catch {
                # Fallback for malformed versions
                Write-Log -Message "Version conversion failed for $($_.version), using fallback" -Level "WARNING" -Component "Get-LatestNodeJSVersion"
                return [System.Version]"0.0.0"
            }
        } -Descending
        
        $latestLts = $sortedLtsVersions[0]
        $version = $latestLts.version.TrimStart('v')  # Remove the 'v' prefix
        $ltsName = $latestLts.lts
        
        Write-ColoredOutput "Latest LTS version found: $version ($ltsName)" "Green" "SUCCESS" "Get-LatestNodeJSVersion"
        Write-Log -Message "Latest LTS version determined: $version (LTS name: $ltsName)" -Level "SUCCESS" -Component "Get-LatestNodeJSVersion"
        
        # Display some debug info
        Write-ColoredOutput "Debug: Top 3 LTS versions found:" "Gray" "DEBUG" "Get-LatestNodeJSVersion"
        for ($i = 0; $i -lt [Math]::Min(3, $sortedLtsVersions.Count); $i++) {
            $debugVersion = $sortedLtsVersions[$i].version
            $debugLtsName = $sortedLtsVersions[$i].lts
            Write-ColoredOutput "  $($i+1). $debugVersion ($debugLtsName)" "Gray" "DEBUG" "Get-LatestNodeJSVersion"
            Write-Log -Message "Top LTS version $($i+1): $debugVersion ($debugLtsName)" -Level "DEBUG" -Component "Get-LatestNodeJSVersion"
        }
        
        $result = @{
            Version = $version
            LtsName = $ltsName
            FullVersion = $latestLts.version
        }
        
        Write-FunctionLog -FunctionName "Get-LatestNodeJSVersion" -Action "EXIT" -Details "Success: $version"
        return $result
    }
    catch {
        Write-ColoredOutput "ERROR: Unable to retrieve Node.js version" "Red" "ERROR" "Get-LatestNodeJSVersion"
        Write-ColoredOutput "Details: $($_.Exception.Message)" "Red" "ERROR" "Get-LatestNodeJSVersion"
        Write-ColoredOutput "Check your internet connection and try again" "Red" "ERROR" "Get-LatestNodeJSVersion"
        Write-Log -Message "Failed to retrieve Node.js version: $($_.Exception.Message)" -Level "ERROR" -Component "Get-LatestNodeJSVersion"
        Write-FunctionLog -FunctionName "Get-LatestNodeJSVersion" -Action "ERROR" -Details $_.Exception.Message
        throw "Failed to retrieve Node.js version: $($_.Exception.Message)"
    }
}

# Function to check if a URL exists
function Test-UrlExists {
    param([string]$Url)
    
    Write-FunctionLog -FunctionName "Test-UrlExists" -Action "ENTER" -Details "URL: $Url"
    
    try {
        Write-Log -Message "Testing URL availability: $Url" -Level "INFO" -Component "Test-UrlExists"
        $response = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $exists = $response.StatusCode -eq 200
        Write-Log -Message "URL test result: $exists (Status: $($response.StatusCode))" -Level "SUCCESS" -Component "Test-UrlExists"
        Write-FunctionLog -FunctionName "Test-UrlExists" -Action "EXIT" -Details "Result: $exists"
        return $exists
    }
    catch {
        Write-Log -Message "URL test failed: $($_.Exception.Message)" -Level "WARNING" -Component "Test-UrlExists"
        Write-FunctionLog -FunctionName "Test-UrlExists" -Action "EXIT" -Details "Result: false (error)"
        return $false
    }
}

# Function to build Node.js download URL
function Get-NodeJSDownloadUrl {
    param(
        [string]$Version,
        [string]$Architecture = "x64"
    )
    
    Write-FunctionLog -FunctionName "Get-NodeJSDownloadUrl" -Action "ENTER" -Details "Version: $Version, Architecture: $Architecture"
    
    # Build primary URL
    $primaryUrl = "https://nodejs.org/dist/v$Version/node-v$Version-win-$Architecture.zip"
    
    Write-ColoredOutput "Checking availability: $primaryUrl" "Cyan" "INFO" "Get-NodeJSDownloadUrl"
    Write-Log -Message "Testing primary URL: $primaryUrl" -Level "INFO" -Component "Get-NodeJSDownloadUrl"
    
    if (Test-UrlExists $primaryUrl) {
        Write-ColoredOutput "Download URL confirmed" "Green" "SUCCESS" "Get-NodeJSDownloadUrl"
        Write-Log -Message "Primary URL confirmed available" -Level "SUCCESS" -Component "Get-NodeJSDownloadUrl"
        Write-FunctionLog -FunctionName "Get-NodeJSDownloadUrl" -Action "EXIT" -Details "Primary URL success"
        return $primaryUrl
    }
    
    # If primary URL doesn't work, try other architectures
    Write-ColoredOutput "Primary URL unavailable, trying alternatives..." "Yellow" "WARNING" "Get-NodeJSDownloadUrl"
    Write-Log -Message "Primary URL unavailable, trying alternative architectures" -Level "WARNING" -Component "Get-NodeJSDownloadUrl"
    
    $alternativeUrls = @(
        "https://nodejs.org/dist/v$Version/node-v$Version-win-x86.zip"
    )
    
    foreach ($altUrl in $alternativeUrls) {
        Write-ColoredOutput "Trying alternative URL: $altUrl" "Yellow" "INFO" "Get-NodeJSDownloadUrl"
        Write-Log -Message "Testing alternative URL: $altUrl" -Level "INFO" -Component "Get-NodeJSDownloadUrl"
        if (Test-UrlExists $altUrl) {
            Write-ColoredOutput "Alternative URL confirmed" "Green" "SUCCESS" "Get-NodeJSDownloadUrl"
            Write-Log -Message "Alternative URL confirmed available: $altUrl" -Level "SUCCESS" -Component "Get-NodeJSDownloadUrl"
            Write-FunctionLog -FunctionName "Get-NodeJSDownloadUrl" -Action "EXIT" -Details "Alternative URL success"
            return $altUrl
        }
    }
    
    $errorMsg = "ERROR: No valid download URL found for Node.js v$Version. The version may not be available for download yet."
    Write-Log -Message $errorMsg -Level "ERROR" -Component "Get-NodeJSDownloadUrl"
    Write-FunctionLog -FunctionName "Get-NodeJSDownloadUrl" -Action "ERROR" -Details "No valid URLs found"
    throw $errorMsg
}

# Function to safely copy files handling long paths
function Copy-NodeFiles {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )
    
    Write-FunctionLog -FunctionName "Copy-NodeFiles" -Action "ENTER" -Details "Source: $SourcePath, Destination: $DestinationPath"
    
    Write-ColoredOutput "Copying Node.js files from: $SourcePath" "Yellow" "INFO" "Copy-NodeFiles"
    Write-ColoredOutput "To: $DestinationPath" "Yellow" "INFO" "Copy-NodeFiles"
    
    try {
        # Try standard copy first
        Write-Log -Message "Attempting standard copy method" -Level "INFO" -Component "Copy-NodeFiles"
        Copy-Item -Path "$SourcePath\*" -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
        Write-ColoredOutput "Standard copy completed successfully" "Green" "SUCCESS" "Copy-NodeFiles"
        Write-Log -Message "Standard copy completed successfully" -Level "SUCCESS" -Component "Copy-NodeFiles"
        Write-FunctionLog -FunctionName "Copy-NodeFiles" -Action "EXIT" -Details "Standard copy success"
    }
    catch [System.IO.PathTooLongException] {
        Write-ColoredOutput "Long path detected, using robocopy for file transfer..." "Yellow" "WARNING" "Copy-NodeFiles"
        Write-Log -Message "PathTooLongException encountered, using robocopy" -Level "WARNING" -Component "Copy-NodeFiles"
        
        # Use robocopy for long path support
        $robocopyResult = robocopy "$SourcePath" "$DestinationPath" /E /R:1 /W:1 /NP /NDL /NJH /NJS
        
        # Check robocopy exit code (0-7 are success codes)
        if ($LASTEXITCODE -le 7) {
            Write-ColoredOutput "Robocopy transfer completed successfully" "Green" "SUCCESS" "Copy-NodeFiles"
            Write-Log -Message "Robocopy transfer completed successfully (exit code: $LASTEXITCODE)" -Level "SUCCESS" -Component "Copy-NodeFiles"
        } else {
            Write-ColoredOutput "Warning: Some files may not have been copied (robocopy exit code: $LASTEXITCODE)" "Yellow" "WARNING" "Copy-NodeFiles"
            Write-Log -Message "Robocopy completed with warnings (exit code: $LASTEXITCODE)" -Level "WARNING" -Component "Copy-NodeFiles"
        }
        Write-FunctionLog -FunctionName "Copy-NodeFiles" -Action "EXIT" -Details "Robocopy method used"
    }
    catch {
        Write-ColoredOutput "Error during file copy: $($_.Exception.Message)" "Red" "ERROR" "Copy-NodeFiles"
        Write-Log -Message "File copy error: $($_.Exception.Message)" -Level "ERROR" -Component "Copy-NodeFiles"
        Write-FunctionLog -FunctionName "Copy-NodeFiles" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to install Node.js with configurable temp directory
function Install-NodeJS {
    param(
        [string]$BaseInstallPath,
        [string]$TempDir
    )
    
    Write-FunctionLog -FunctionName "Install-NodeJS" -Action "ENTER" -Details "BaseInstallPath: $BaseInstallPath, TempDir: $TempDir"
    
    Write-ColoredOutput "`n=== Node.js Installation ===" "Magenta" "INFO" "Install-NodeJS"
    
    try {
        # Get latest version with corrected sorting
        $nodeInfo = Get-LatestNodeJSVersion
        $nodeVersion = $nodeInfo.Version
        $ltsName = $nodeInfo.LtsName
        
        Write-ColoredOutput "Installing Node.js v$nodeVersion ($ltsName)" "Cyan" "INFO" "Install-NodeJS"
        Write-Log -Message "Starting Node.js installation - Version: $nodeVersion, LTS: $ltsName" -Level "INFO" -Component "Install-NodeJS"
        
        # Configure paths
        $nodeInstallPath = Join-Path $BaseInstallPath "PCTOOLS\nodejs"
        $nodeZipPath = Join-Path $TempDir "node.zip"
        $nodeExtractPath = Join-Path $TempDir "extract"
        
        Write-Log -Message "Installation paths configured - Install: $nodeInstallPath, ZIP: $nodeZipPath, Extract: $nodeExtractPath" -Level "INFO" -Component "Install-NodeJS"
        
        # Get download URL
        $nodeUrl = Get-NodeJSDownloadUrl $nodeVersion
        
        # Create directories
        New-InstallDirectory $nodeInstallPath
        New-InstallDirectory $TempDir
        New-InstallDirectory $nodeExtractPath
        
        # Download
        Download-File $nodeUrl $nodeZipPath
        
        # Extract with error handling for long paths
        Write-ColoredOutput "Extracting Node.js..." "Yellow" "INFO" "Install-NodeJS"
        Write-Log -Message "Starting Node.js extraction" -Level "INFO" -Component "Install-NodeJS"
        try {
            # Try standard extraction first
            Write-Log -Message "Attempting standard extraction method" -Level "INFO" -Component "Install-NodeJS"
            Expand-Archive -Path $nodeZipPath -DestinationPath $nodeExtractPath -Force -ErrorAction Stop
            Write-ColoredOutput "Standard extraction completed" "Green" "SUCCESS" "Install-NodeJS"
            Write-Log -Message "Standard extraction completed successfully" -Level "SUCCESS" -Component "Install-NodeJS"
        }
        catch [System.IO.PathTooLongException] {
            Write-ColoredOutput "Long path detected during extraction, using alternative method..." "Yellow" "WARNING" "Install-NodeJS"
            Write-Log -Message "PathTooLongException during extraction, using alternative method" -Level "WARNING" -Component "Install-NodeJS"
            
            # Try with even shorter path - create a fallback temp directory
            $shorterExtractPath = Join-Path ([System.IO.Path]::GetTempPath()) "N"
            Remove-Item -Path $nodeExtractPath -Recurse -Force -ErrorAction SilentlyContinue
            New-InstallDirectory $shorterExtractPath
            
            Write-Log -Message "Using shorter extraction path: $shorterExtractPath" -Level "INFO" -Component "Install-NodeJS"
            
            try {
                Expand-Archive -Path $nodeZipPath -DestinationPath $shorterExtractPath -Force -ErrorAction Stop
                $nodeExtractPath = $shorterExtractPath
                Write-ColoredOutput "Alternative extraction completed to: $shorterExtractPath" "Green" "SUCCESS" "Install-NodeJS"
                Write-Log -Message "Alternative extraction completed successfully to: $shorterExtractPath" -Level "SUCCESS" -Component "Install-NodeJS"
            }
            catch {
                $errorMsg = "Unable to extract Node.js archive due to long path limitations. Consider using a shorter temporary directory path or enabling Windows long path support."
                Write-Log -Message $errorMsg -Level "ERROR" -Component "Install-NodeJS"
                throw $errorMsg
            }
        }
        catch {
            Write-ColoredOutput "Extraction error: $($_.Exception.Message)" "Red" "ERROR" "Install-NodeJS"
            Write-Log -Message "Extraction error: $($_.Exception.Message)" -Level "ERROR" -Component "Install-NodeJS"
            throw
        }
        
        # Find extracted folder
        Write-Log -Message "Searching for extracted Node.js folder" -Level "INFO" -Component "Install-NodeJS"
        $extractedFolders = Get-ChildItem -Path $nodeExtractPath -Directory -ErrorAction SilentlyContinue
        if ($extractedFolders.Count -eq 0) {
            $errorMsg = "No folder found after ZIP extraction. Archive may be corrupted."
            Write-Log -Message $errorMsg -Level "ERROR" -Component "Install-NodeJS"
            throw $errorMsg
        }
        
        $sourceNodePath = $extractedFolders[0].FullName
        Write-ColoredOutput "Found extracted Node.js folder: $($extractedFolders[0].Name)" "Green" "SUCCESS" "Install-NodeJS"
        Write-Log -Message "Found extracted Node.js folder: $($extractedFolders[0].Name)" -Level "SUCCESS" -Component "Install-NodeJS"
        
        # Copy files with long path handling
        Write-ColoredOutput "Installing to: $nodeInstallPath" "Yellow" "INFO" "Install-NodeJS"
        Copy-NodeFiles $sourceNodePath $nodeInstallPath
        
        # Verify essential files are present
        Write-Log -Message "Verifying installation - checking for essential files" -Level "INFO" -Component "Install-NodeJS"
        $essentialFiles = @("node.exe", "npm.cmd")
        foreach ($file in $essentialFiles) {
            $filePath = Join-Path $nodeInstallPath $file
            Write-Log -Message "Checking for essential file: $filePath" -Level "DEBUG" -Component "Install-NodeJS"
            if (-not (Test-Path $filePath)) {
                $errorMsg = "Essential file missing: $file. Installation may be incomplete."
                Write-Log -Message $errorMsg -Level "ERROR" -Component "Install-NodeJS"
                throw $errorMsg
            } else {
                Write-Log -Message "Essential file found: $file" -Level "SUCCESS" -Component "Install-NodeJS"
            }
        }
        Write-ColoredOutput "Essential files verified" "Green" "SUCCESS" "Install-NodeJS"
        
        # Configure environment variables
        Write-ColoredOutput "Configuring environment variables..." "Yellow" "INFO" "Install-NodeJS"
        Write-Log -Message "Configuring environment variables" -Level "INFO" -Component "Install-NodeJS"
        
        # Add to system PATH
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($currentPath -notlike "*$nodeInstallPath*") {
            $newPath = "$currentPath;$nodeInstallPath"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
            Write-ColoredOutput "Node.js added to system PATH" "Green" "SUCCESS" "Install-NodeJS"
            Write-Log -Message "Node.js added to system PATH: $nodeInstallPath" -Level "SUCCESS" -Component "Install-NodeJS"
        } else {
            Write-ColoredOutput "Node.js already present in system PATH" "Yellow" "INFO" "Install-NodeJS"
            Write-Log -Message "Node.js already present in system PATH" -Level "INFO" -Component "Install-NodeJS"
        }
        
        # Update PATH for current session (with verification to avoid duplicates)
        if ($env:PATH -notlike "*$nodeInstallPath*") {
            $env:PATH += ";$nodeInstallPath"
            Write-Log -Message "PATH updated for current session" -Level "INFO" -Component "Install-NodeJS"
        }
        
        # Create npm global directory
        $npmGlobalPath = Join-Path $nodeInstallPath "node_global"
        $npmCachePath = Join-Path $nodeInstallPath "node_cache"
        New-InstallDirectory $npmGlobalPath
        New-InstallDirectory $npmCachePath
        Write-Log -Message "npm directories created - Global: $npmGlobalPath, Cache: $npmCachePath" -Level "SUCCESS" -Component "Install-NodeJS"
        
        # Configure npm with error handling
        Write-ColoredOutput "Configuring npm..." "Yellow" "INFO" "Install-NodeJS"
        Write-Log -Message "Starting npm configuration" -Level "INFO" -Component "Install-NodeJS"
        try {
            & "$nodeInstallPath\npm.cmd" config set prefix $npmGlobalPath 2>$null
            & "$nodeInstallPath\npm.cmd" config set cache $npmCachePath 2>$null
            Write-ColoredOutput "npm configuration completed" "Green" "SUCCESS" "Install-NodeJS"
            Write-Log -Message "npm configuration completed successfully" -Level "SUCCESS" -Component "Install-NodeJS"
        }
        catch {
            Write-ColoredOutput "Warning: npm configuration may be incomplete" "Yellow" "WARNING" "Install-NodeJS"
            Write-Log -Message "npm configuration warning: $($_.Exception.Message)" -Level "WARNING" -Component "Install-NodeJS"
        }
        
        # Add npm global directory to PATH
        $npmBinPath = Join-Path $npmGlobalPath "bin"
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($currentPath -notlike "*$npmBinPath*") {
            $newPath = "$currentPath;$npmBinPath"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
            Write-ColoredOutput "npm global directory added to system PATH" "Green" "SUCCESS" "Install-NodeJS"
            Write-Log -Message "npm global directory added to system PATH: $npmBinPath" -Level "SUCCESS" -Component "Install-NodeJS"
        } else {
            Write-Log -Message "npm global directory already present in system PATH" -Level "INFO" -Component "Install-NodeJS"
        }
        
        # Cleanup temporary files
        Write-ColoredOutput "Cleaning up temporary files..." "Yellow" "INFO" "Install-NodeJS"
        Write-Log -Message "Starting cleanup of temporary files" -Level "INFO" -Component "Install-NodeJS"
        try {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColoredOutput "Cleanup completed" "Green" "SUCCESS" "Install-NodeJS"
            Write-Log -Message "Temporary files cleanup completed successfully" -Level "SUCCESS" -Component "Install-NodeJS"
        }
        catch {
            Write-ColoredOutput "Warning: Some temporary files may remain in $TempDir" "Yellow" "WARNING" "Install-NodeJS"
            Write-Log -Message "Cleanup warning: Some temporary files may remain - $($_.Exception.Message)" -Level "WARNING" -Component "Install-NodeJS"
        }
        
        # Verify installation
        Write-ColoredOutput "Verifying installation..." "Yellow" "INFO" "Install-NodeJS"
        Write-Log -Message "Starting installation verification" -Level "INFO" -Component "Install-NodeJS"
        try {
            $installedNodeVersion = & "$nodeInstallPath\node.exe" --version 2>$null
            $installedNpmVersion = & "$nodeInstallPath\npm.cmd" --version 2>$null
            
            if ($installedNodeVersion -and $installedNpmVersion) {
                Write-ColoredOutput "Node.js installed successfully!" "Green" "SUCCESS" "Install-NodeJS"
                Write-ColoredOutput "Installed Node.js version: $installedNodeVersion" "Green" "SUCCESS" "Install-NodeJS"
                Write-ColoredOutput "Installed npm version: $installedNpmVersion" "Green" "SUCCESS" "Install-NodeJS"
                Write-ColoredOutput "LTS version: $ltsName" "Green" "SUCCESS" "Install-NodeJS"
                Write-ColoredOutput "Installation directory: $nodeInstallPath" "Green" "SUCCESS" "Install-NodeJS"
                
                Write-Log -Message "Installation verification successful - Node.js: $installedNodeVersion, npm: $installedNpmVersion" -Level "SUCCESS" -Component "Install-NodeJS"
                Write-Log -Message "Node.js installed successfully - Version: $nodeVersion, LTS: $ltsName, Path: $nodeInstallPath" -Level "SUCCESS" -Component "Install-NodeJS"
            } else {
                Write-ColoredOutput "Installation completed but verification failed. Node.js may still be functional." "Yellow" "WARNING" "Install-NodeJS"
                Write-Log -Message "Installation verification failed - no version output" -Level "WARNING" -Component "Install-NodeJS"
            }
        }
        catch {
            Write-ColoredOutput "Installation completed but verification failed: $($_.Exception.Message)" "Yellow" "WARNING" "Install-NodeJS"
            Write-ColoredOutput "Node.js may still be functional. Try opening a new command prompt." "Yellow" "WARNING" "Install-NodeJS"
            Write-Log -Message "Installation verification failed: $($_.Exception.Message)" -Level "WARNING" -Component "Install-NodeJS"
        }
        
        Write-FunctionLog -FunctionName "Install-NodeJS" -Action "EXIT" -Details "Installation process completed"
        
    }
    catch {
        Write-ColoredOutput "Error during Node.js installation: $($_.Exception.Message)" "Red" "ERROR" "Install-NodeJS"
        Write-Log -Message "Node.js installation error: $($_.Exception.Message)" -Level "ERROR" -Component "Install-NodeJS"
        Write-FunctionLog -FunctionName "Install-NodeJS" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

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
$LogFile = Join-Path $LogDirectory "win_install_nodejs.log"

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
    $LogFile = Join-Path (Get-Location) "win_install_nodejs.log"
}

# Initialize log file
try {
    # Create or clear the log file
    $logHeader = @"
================================================================================
GameShell65 - Node.js Installation Log
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
    Write-ColoredOutput "=== GameShell65 - Software Installer ===" "Magenta" "INFO" "MAIN"
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
        $null = Invoke-WebRequest -Uri "https://nodejs.org" -Method Head -UseBasicParsing -TimeoutSec 10
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
    
    # Install Node.js with custom temp directory
    Install-NodeJS $resolvedInstallPath $tempDir
    
    Write-ColoredOutput "`n=== Installation completed successfully! ===" "Green" "SUCCESS" "MAIN"
    Write-ColoredOutput "IMPORTANT: Restart your session or open a new command window to use the new tools." "Yellow" "INFO" "MAIN"
    Write-ColoredOutput "You can verify the installation by running: node --version" "Cyan" "INFO" "MAIN"
    
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