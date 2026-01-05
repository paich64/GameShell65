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
            $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\kickass"
            Write-ColoredOutput "Using installation-based temporary directory: $tempDir" "Cyan" "INFO" "Get-TempDirectory"
        }
        else {
            # User provided temp directory
            $tempDir = Join-Path $UserTempDir "GameShell65_temp_Install\kickass"
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
                    $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\kickass"
                }
            }
        }
        
        # Ensure the temp directory path is not too long to avoid path issues
        if ($tempDir.Length -gt 100) {
            Write-ColoredOutput "Warning: Temporary directory path is long ($($tempDir.Length) chars). This may cause issues with some files." "Yellow" "WARNING" "Get-TempDirectory"
            Write-ColoredOutput "Consider using a shorter path like 'C:\Temp\KA65'" "Yellow" "WARNING" "Get-TempDirectory"
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

# Function to download a file with progress and validation
function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath,
        [int]$MaxRetries = 3
    )
    
    Write-FunctionLog -FunctionName "Download-File" -Action "ENTER" -Details "URL: $Url, OutputPath: $OutputPath, MaxRetries: $MaxRetries"
    
    Write-ColoredOutput "Downloading from: $Url" "Cyan" "INFO" "Download-File"
    Write-ColoredOutput "Destination: $OutputPath" "Cyan" "INFO" "Download-File"
    
    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            Write-Log -Message "Download attempt $($retryCount + 1) of $MaxRetries" -Level "INFO" -Component "Download-File"
            
            # Remove existing file if it exists
            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -Force
                Write-Log -Message "Removed existing file: $OutputPath" -Level "INFO" -Component "Download-File"
            }
            
            # Direct download from GitLab raw URL
            $downloadStartTime = Get-Date
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -TimeoutSec 60 -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            $downloadEndTime = Get-Date
            $downloadDuration = ($downloadEndTime - $downloadStartTime).TotalSeconds
            
            # Verify file was downloaded and has content
            if (Test-Path $OutputPath) {
                $fileSize = (Get-Item $OutputPath).Length
                Write-ColoredOutput "File downloaded, size: $fileSize bytes" "Cyan" "INFO" "Download-File"
                Write-Log -Message "File downloaded successfully - Size: $fileSize bytes, Duration: $([math]::Round($downloadDuration, 2)) seconds" -Level "SUCCESS" -Component "Download-File"
                
                # For JAR files, expect at least 100KB for a valid KickAssembler distribution
                $expectedMinSize = if ($OutputPath.EndsWith(".jar")) { 100KB } else { 1KB }
                
                if ($fileSize -gt $expectedMinSize) {
                    # Additional check for JAR files - verify it's actually a JAR archive
                    if ($OutputPath.EndsWith(".jar")) {
                        try {
                            Write-Log -Message "Validating JAR file integrity" -Level "INFO" -Component "Download-File"
                            $fileBytes = [System.IO.File]::ReadAllBytes($OutputPath)
                            # Check ZIP/JAR file signature (PK header - JAR files are ZIP archives)
                            if ($fileBytes.Length -ge 4 -and $fileBytes[0] -eq 0x50 -and $fileBytes[1] -eq 0x4B) {
                                Write-ColoredOutput "Download completed successfully - Valid JAR file" "Green" "SUCCESS" "Download-File"
                                Write-Log -Message "JAR file validation successful - Valid ZIP/JAR signature found" -Level "SUCCESS" -Component "Download-File"
                                Write-FunctionLog -FunctionName "Download-File" -Action "EXIT" -Details "Success after $($retryCount + 1) attempts"
                                return
                            }
                            else {
                                # Check if it's an HTML file
                                $maxBytes = [Math]::Min(100, $fileBytes.Length - 1)
                                $firstBytes = [System.Text.Encoding]::ASCII.GetString($fileBytes[0..$maxBytes])
                                if ($firstBytes -match "<!DOCTYPE html>|<html") {
                                    throw "Downloaded HTML page instead of JAR file"
                                }
                                else {
                                    throw "Downloaded file is not a valid JAR archive (no PK signature)"
                                }
                            }
                        }
                        catch {
                            if ($_.Exception.Message -match "HTML page") {
                                Write-Log -Message "JAR validation failed: Downloaded HTML page instead of JAR file" -Level "ERROR" -Component "Download-File"
                                throw $_.Exception.Message
                            }
                            else {
                                Write-Log -Message "JAR validation failed: $($_.Exception.Message)" -Level "ERROR" -Component "Download-File"
                                throw "Cannot verify JAR file integrity: $($_.Exception.Message)"
                            }
                        }
                    }
                    else {
                        Write-ColoredOutput "Download completed successfully" "Green" "SUCCESS" "Download-File"
                        Write-FunctionLog -FunctionName "Download-File" -Action "EXIT" -Details "Success after $($retryCount + 1) attempts"
                        return
                    }
                }
                else {
                    throw "Downloaded file is too small ($fileSize bytes, expected at least $expectedMinSize bytes)"
                }
            }
            else {
                throw "Download failed - file not created"
            }
        }
        catch {
            $retryCount++
            Write-ColoredOutput "Download attempt $retryCount failed: $($_.Exception.Message)" "Yellow" "WARNING" "Download-File"
            Write-Log -Message "Download attempt $retryCount failed: $($_.Exception.Message)" -Level "WARNING" -Component "Download-File"
            
            if ($retryCount -lt $MaxRetries) {
                Write-ColoredOutput "Retrying download in 3 seconds..." "Yellow" "WARNING" "Download-File"
                Write-Log -Message "Retrying download in 3 seconds..." -Level "INFO" -Component "Download-File"
                Start-Sleep -Seconds 3
            }
            else {
                Write-ColoredOutput "Download error after $MaxRetries attempts: $($_.Exception.Message)" "Red" "ERROR" "Download-File"
                Write-Log -Message "Download failed after $MaxRetries attempts: $($_.Exception.Message)" -Level "ERROR" -Component "Download-File"
                Write-FunctionLog -FunctionName "Download-File" -Action "ERROR" -Details "Failed after $MaxRetries attempts"
                throw
            }
        }
    }
}

# Custom version comparison function to handle suffixes like 5.24a, 5.24b, 5.24c
function Compare-KickAssVersion {
    param(
        [string]$Version1,
        [string]$Version2
    )
    
    Write-FunctionLog -FunctionName "Compare-KickAssVersion" -Action "ENTER" -Details "Version1: $Version1, Version2: $Version2"
    
    # Parse versions with potential suffixes
    $v1Match = [regex]::Match($Version1, '^(\d+)\.(\d+)([a-z]*)$')
    $v2Match = [regex]::Match($Version2, '^(\d+)\.(\d+)([a-z]*)$')
    
    if (-not $v1Match.Success -or -not $v2Match.Success) {
        # Fallback to string comparison if regex fails
        Write-Log -Message "Version comparison fallback to string comparison - V1: $Version1, V2: $Version2" -Level "WARNING" -Component "Compare-KickAssVersion"
        $result = [string]::Compare($Version1, $Version2)
        Write-FunctionLog -FunctionName "Compare-KickAssVersion" -Action "EXIT" -Details "String comparison result: $result"
        return $result
    }
    
    $v1Major = [int]$v1Match.Groups[1].Value
    $v1Minor = [int]$v1Match.Groups[2].Value
    $v1Suffix = $v1Match.Groups[3].Value
    
    $v2Major = [int]$v2Match.Groups[1].Value
    $v2Minor = [int]$v2Match.Groups[2].Value
    $v2Suffix = $v2Match.Groups[3].Value
    
    Write-Log -Message "Version parsing - V1: $v1Major.$v1Minor$v1Suffix, V2: $v2Major.$v2Minor$v2Suffix" -Level "DEBUG" -Component "Compare-KickAssVersion"
    
    # Compare major versions
    if ($v1Major -ne $v2Major) {
        $result = $v1Major - $v2Major
        Write-FunctionLog -FunctionName "Compare-KickAssVersion" -Action "EXIT" -Details "Major version comparison result: $result"
        return $result
    }
    
    # Compare minor versions
    if ($v1Minor -ne $v2Minor) {
        $result = $v1Minor - $v2Minor
        Write-FunctionLog -FunctionName "Compare-KickAssVersion" -Action "EXIT" -Details "Minor version comparison result: $result"
        return $result
    }
    
    # Compare suffixes (empty comes first, then a, b, c, etc.)
    if ([string]::IsNullOrEmpty($v1Suffix) -and [string]::IsNullOrEmpty($v2Suffix)) {
        Write-FunctionLog -FunctionName "Compare-KickAssVersion" -Action "EXIT" -Details "Versions are equal"
        return 0
    }
    elseif ([string]::IsNullOrEmpty($v1Suffix)) {
        Write-FunctionLog -FunctionName "Compare-KickAssVersion" -Action "EXIT" -Details "V1 has no suffix (older)"
        return -1  # Version without suffix is older
    }
    elseif ([string]::IsNullOrEmpty($v2Suffix)) {
        Write-FunctionLog -FunctionName "Compare-KickAssVersion" -Action "EXIT" -Details "V2 has no suffix (older)"
        return 1   # Version without suffix is older
    }
    else {
        $result = [string]::Compare($v1Suffix, $v2Suffix)
        Write-FunctionLog -FunctionName "Compare-KickAssVersion" -Action "EXIT" -Details "Suffix comparison result: $result"
        return $result
    }
}

# Function to get the latest version of KickAssembler from GitLab API
function Get-LatestKickAssemblerVersion {
    Write-FunctionLog -FunctionName "Get-LatestKickAssemblerVersion" -Action "ENTER"
    
    Write-ColoredOutput "Searching for the latest version of KickAssembler65CE02..." "Yellow" "INFO" "Get-LatestKickAssemblerVersion"
    
    try {
        # Use GitLab API to list files in the release directory
        $apiUrl = "https://gitlab.com/api/v4/projects/jespergravgaard%2Fkickassembler65ce02/repository/tree?path=release&ref=master"
        Write-ColoredOutput "Querying GitLab API: $apiUrl" "Cyan" "INFO" "Get-LatestKickAssemblerVersion"
        Write-Log -Message "Attempting to fetch KickAssembler versions from GitLab API: $apiUrl" -Level "INFO" -Component "Get-LatestKickAssemblerVersion"
        
        $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 30
        
        if (-not $response -or $response.Count -eq 0) {
            throw "Empty response from GitLab API"
        }
        
        Write-Log -Message "GitLab API response received with $($response.Count) items" -Level "SUCCESS" -Component "Get-LatestKickAssemblerVersion"
        
        # Filter JAR files
        $jarFiles = $response | Where-Object { $_.name -like "*.jar" -and $_.type -eq "blob" }
        
        if ($jarFiles.Count -eq 0) {
            throw "No JAR files found in GitLab release directory"
        }
        
        Write-ColoredOutput "Found $($jarFiles.Count) JAR files" "Green" "SUCCESS" "Get-LatestKickAssemblerVersion"
        Write-Log -Message "Found $($jarFiles.Count) JAR files in release directory" -Level "SUCCESS" -Component "Get-LatestKickAssemblerVersion"
        
        # Extract versions from filenames
        $versions = @()
        $jarFileMap = @{}
        
        foreach ($jarFile in $jarFiles) {
            $fileName = $jarFile.name
            Write-ColoredOutput "Found JAR: $fileName" "Gray" "DEBUG" "Get-LatestKickAssemblerVersion"
            
            # Pattern to extract version from filename
            if ($fileName -match 'KickAss65CE02-(\d+\.\d+[a-z]?)\.jar') {
                $version = $matches[1]
                $versions += $version
                $jarFileMap[$version] = $fileName
                Write-ColoredOutput "  -> Version: $version" "Gray" "DEBUG" "Get-LatestKickAssemblerVersion"
                Write-Log -Message "Extracted version $version from filename $fileName" -Level "SUCCESS" -Component "Get-LatestKickAssemblerVersion"
            } else {
                Write-Log -Message "Could not extract version from filename: $fileName" -Level "WARNING" -Component "Get-LatestKickAssemblerVersion"
            }
        }
        
        if ($versions.Count -eq 0) {
            throw "No valid versions found in JAR files"
        }
        
        Write-Log -Message "Successfully extracted $($versions.Count) versions from JAR files" -Level "SUCCESS" -Component "Get-LatestKickAssemblerVersion"
        
        # Sort versions (custom sorting logic to handle suffixes)
        $sortedVersions = $versions | Sort-Object {
            $versionMatch = [regex]::Match($_, '^(\d+)\.(\d+)([a-z]*)$')
            if ($versionMatch.Success) {
                $major = [int]$versionMatch.Groups[1].Value
                $minor = [int]$versionMatch.Groups[2].Value
                $suffix = $versionMatch.Groups[3].Value
                
                # Create sort key: major*1000 + minor*10 + suffix_value
                $suffixValue = if ([string]::IsNullOrEmpty($suffix)) { 0 } else { [byte][char]$suffix - [byte][char]'a' + 1 }
                $sortKey = $major * 1000 + $minor * 10 + $suffixValue
                Write-Log -Message "Version $_ sort key: $sortKey (major=$major, minor=$minor, suffix='$suffix', suffixValue=$suffixValue)" -Level "DEBUG" -Component "Get-LatestKickAssemblerVersion"
                return $sortKey
            }
            return 0
        } -Descending
        
        $latestVersion = $sortedVersions[0]
        $latestJarFile = $jarFileMap[$latestVersion]
        
        Write-ColoredOutput "Latest KickAssembler version found: $latestVersion" "Green" "SUCCESS" "Get-LatestKickAssemblerVersion"
        Write-ColoredOutput "JAR file: $latestJarFile" "Green" "SUCCESS" "Get-LatestKickAssemblerVersion"
        Write-Log -Message "Latest version determined: $latestVersion (JAR: $latestJarFile)" -Level "SUCCESS" -Component "Get-LatestKickAssemblerVersion"
        
        # Display top 5 versions for debug
        Write-ColoredOutput "Debug: Top 5 versions found:" "Gray" "DEBUG" "Get-LatestKickAssemblerVersion"
        for ($i = 0; $i -lt [Math]::Min(5, $sortedVersions.Count); $i++) {
            $debugVersion = $sortedVersions[$i]
            $debugJar = $jarFileMap[$debugVersion]
            Write-ColoredOutput "  $($i+1). $debugVersion ($debugJar)" "Gray" "DEBUG" "Get-LatestKickAssemblerVersion"
            Write-Log -Message "Top version $($i+1): $debugVersion ($debugJar)" -Level "DEBUG" -Component "Get-LatestKickAssemblerVersion"
        }
        
        $result = @{
            Version = $latestVersion
            JarFileName = $latestJarFile
            Available = $true
        }
        
        Write-FunctionLog -FunctionName "Get-LatestKickAssemblerVersion" -Action "EXIT" -Details "Success: $latestVersion"
        return $result
    }
    catch {
        Write-ColoredOutput "ERROR: Unable to retrieve KickAssembler version from GitLab API" "Red" "ERROR" "Get-LatestKickAssemblerVersion"
        Write-ColoredOutput "Details: $($_.Exception.Message)" "Red" "ERROR" "Get-LatestKickAssemblerVersion"
        Write-ColoredOutput "Using known JAR filename" "Yellow" "WARNING" "Get-LatestKickAssemblerVersion"
        Write-Log -Message "GitLab API failed: $($_.Exception.Message)" -Level "ERROR" -Component "Get-LatestKickAssemblerVersion"
        Write-Log -Message "Falling back to known version 5.25" -Level "WARNING" -Component "Get-LatestKickAssemblerVersion"
        
        # Fallback to version 5.25 as requested
        $fallbackResult = @{
            Version = "5.25"
            JarFileName = "KickAss65CE02-5.25.jar"
            Available = $false
        }
        
        Write-FunctionLog -FunctionName "Get-LatestKickAssemblerVersion" -Action "EXIT" -Details "Fallback to version 5.25"
        return $fallbackResult
    }
}

# Function to build KickAssembler download URL
function Get-KickAssemblerDownloadUrl {
    param(
        [string]$JarFileName
    )
    
    Write-FunctionLog -FunctionName "Get-KickAssemblerDownloadUrl" -Action "ENTER" -Details "JarFileName: $JarFileName"
    
    # Build the raw download URL for GitLab - CORRECTED to use /raw/master/ directly
    $downloadUrl = "https://gitlab.com/jespergravgaard/kickassembler65ce02/-/raw/master/release/$JarFileName"
    
    Write-ColoredOutput "KickAssembler download URL: $downloadUrl" "Cyan" "INFO" "Get-KickAssemblerDownloadUrl"
    Write-Log -Message "Constructed download URL: $downloadUrl" -Level "INFO" -Component "Get-KickAssemblerDownloadUrl"
    
    # Verify the URL exists
    try {
        Write-Log -Message "Verifying URL accessibility" -Level "INFO" -Component "Get-KickAssemblerDownloadUrl"
        $response = Invoke-WebRequest -Uri $downloadUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-ColoredOutput "KickAssembler JAR file confirmed available" "Green" "SUCCESS" "Get-KickAssemblerDownloadUrl"
            Write-Log -Message "URL verification successful - HTTP 200 response" -Level "SUCCESS" -Component "Get-KickAssemblerDownloadUrl"
            Write-FunctionLog -FunctionName "Get-KickAssemblerDownloadUrl" -Action "EXIT" -Details "URL verified successfully"
            return $downloadUrl
        }
        else {
            throw "HTTP $($response.StatusCode) response"
        }
    }
    catch {
        Write-ColoredOutput "Warning: Could not verify JAR file availability: $($_.Exception.Message)" "Yellow" "WARNING" "Get-KickAssemblerDownloadUrl"
        Write-ColoredOutput "Will attempt download anyway..." "Yellow" "WARNING" "Get-KickAssemblerDownloadUrl"
        Write-Log -Message "URL verification failed: $($_.Exception.Message)" -Level "WARNING" -Component "Get-KickAssemblerDownloadUrl"
        Write-Log -Message "Proceeding with download attempt despite verification failure" -Level "WARNING" -Component "Get-KickAssemblerDownloadUrl"
        Write-FunctionLog -FunctionName "Get-KickAssemblerDownloadUrl" -Action "EXIT" -Details "URL verification failed but proceeding"
        return $downloadUrl
    }
}

# Function to install KickAssembler
function Install-KickAssembler {
    param(
        [string]$BaseInstallPath,
        [string]$TempDir
    )
    
    Write-FunctionLog -FunctionName "Install-KickAssembler" -Action "ENTER" -Details "BaseInstallPath: $BaseInstallPath, TempDir: $TempDir"
    
    Write-ColoredOutput "`n=== KickAssembler65CE02 Installation ===" "Magenta" "INFO" "Install-KickAssembler"
    
    try {
        # Get latest version info
        $kickAssInfo = Get-LatestKickAssemblerVersion
        $version = $kickAssInfo.Version
        $jarFileName = $kickAssInfo.JarFileName
        
        Write-ColoredOutput "Installing KickAssembler65CE02 v$version from GitLab" "Cyan" "INFO" "Install-KickAssembler"
        Write-Log -Message "Starting KickAssembler installation - Version: $version, JAR: $jarFileName" -Level "INFO" -Component "Install-KickAssembler"
        
        # Configure paths
        $kickAssInstallPath = Join-Path $BaseInstallPath "PCTOOLS\kickass"
        $jarDownloadPath = Join-Path $TempDir $jarFileName
        
        Write-Log -Message "Installation paths configured - Install: $kickAssInstallPath, Download: $jarDownloadPath" -Level "INFO" -Component "Install-KickAssembler"
        
        # Get download URL
        $downloadUrl = Get-KickAssemblerDownloadUrl $jarFileName
        
        # Create directories
        New-InstallDirectory $kickAssInstallPath
        New-InstallDirectory $TempDir
        
        # Download JAR file
        Download-File $downloadUrl $jarDownloadPath
        
        # Verify downloaded file
        $fileSize = (Get-Item $jarDownloadPath).Length
        Write-ColoredOutput "Downloaded JAR file size: $fileSize bytes" "Cyan" "INFO" "Install-KickAssembler"
        Write-Log -Message "Downloaded JAR file verification - Size: $fileSize bytes" -Level "SUCCESS" -Component "Install-KickAssembler"
        
        if ($fileSize -lt 1024) {
            $errorMsg = "Downloaded JAR file is too small, may be corrupted"
            Write-Log -Message $errorMsg -Level "ERROR" -Component "Install-KickAssembler"
            throw $errorMsg
        }
        
        # Copy JAR file to installation directory
        $finalJarPath = Join-Path $kickAssInstallPath $jarFileName
        Write-ColoredOutput "Installing JAR file to: $finalJarPath" "Yellow" "INFO" "Install-KickAssembler"
        Write-Log -Message "Copying JAR file from $jarDownloadPath to $finalJarPath" -Level "INFO" -Component "Install-KickAssembler"
        
        Copy-Item -Path $jarDownloadPath -Destination $finalJarPath -Force
        Write-ColoredOutput "JAR file installation completed" "Green" "SUCCESS" "Install-KickAssembler"
        Write-Log -Message "JAR file successfully copied to installation directory" -Level "SUCCESS" -Component "Install-KickAssembler"
        
        # Configure environment variables
        Write-ColoredOutput "Configuring environment variables..." "Yellow" "INFO" "Install-KickAssembler"
        Write-Log -Message "Configuring environment variables" -Level "INFO" -Component "Install-KickAssembler"
        
        # Add KickAssembler directory to system PATH
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($currentPath -notlike "*$kickAssInstallPath*") {
            $newPath = "$currentPath;$kickAssInstallPath"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
            Write-ColoredOutput "KickAssembler added to system PATH: $kickAssInstallPath" "Green" "SUCCESS" "Install-KickAssembler"
            Write-Log -Message "KickAssembler added to system PATH" -Level "SUCCESS" -Component "Install-KickAssembler"
        } else {
            Write-ColoredOutput "KickAssembler already present in system PATH" "Yellow" "INFO" "Install-KickAssembler"
            Write-Log -Message "KickAssembler already present in system PATH" -Level "INFO" -Component "Install-KickAssembler"
        }
        
        # Update PATH for current session (with verification to avoid duplicates)
        if ($env:PATH -notlike "*$kickAssInstallPath*") {
            $env:PATH += ";$kickAssInstallPath"
            Write-Log -Message "PATH updated for current session" -Level "INFO" -Component "Install-KickAssembler"
        }
        
        # Set KICKASSEMBLER_HOME environment variable
        [Environment]::SetEnvironmentVariable("KICKASSEMBLER_HOME", $kickAssInstallPath, "Machine")
        $env:KICKASSEMBLER_HOME = $kickAssInstallPath
        Write-ColoredOutput "KICKASSEMBLER_HOME environment variable set: $kickAssInstallPath" "Green" "SUCCESS" "Install-KickAssembler"
        Write-Log -Message "KICKASSEMBLER_HOME environment variable set: $kickAssInstallPath" -Level "SUCCESS" -Component "Install-KickAssembler"
        
        # Cleanup temporary files
        Write-ColoredOutput "Cleaning up temporary files..." "Yellow" "INFO" "Install-KickAssembler"
        Write-Log -Message "Starting cleanup of temporary files" -Level "INFO" -Component "Install-KickAssembler"
        try {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColoredOutput "Cleanup completed" "Green" "SUCCESS" "Install-KickAssembler"
            Write-Log -Message "Temporary files cleanup completed successfully" -Level "SUCCESS" -Component "Install-KickAssembler"
        }
        catch {
            Write-ColoredOutput "Warning: Some temporary files may remain in $TempDir" "Yellow" "WARNING" "Install-KickAssembler"
            Write-Log -Message "Cleanup warning: Some temporary files may remain - $($_.Exception.Message)" -Level "WARNING" -Component "Install-KickAssembler"
        }
        
        # Verify installation
        Write-ColoredOutput "Verifying installation..." "Yellow" "INFO" "Install-KickAssembler"
        Write-Log -Message "Starting installation verification" -Level "INFO" -Component "Install-KickAssembler"
        try {
            if (Test-Path $finalJarPath) {
                Write-ColoredOutput "KickAssembler65CE02 installed successfully!" "Green" "SUCCESS" "Install-KickAssembler"
                Write-ColoredOutput "Installation directory: $kickAssInstallPath" "Green" "SUCCESS" "Install-KickAssembler"
                Write-ColoredOutput "JAR file: $finalJarPath" "Green" "SUCCESS" "Install-KickAssembler"
                Write-ColoredOutput "Version: $version" "Green" "SUCCESS" "Install-KickAssembler"
                Write-Log -Message "Installation verification successful - JAR file exists at $finalJarPath" -Level "SUCCESS" -Component "Install-KickAssembler"
                Write-Log -Message "KickAssembler65CE02 installed successfully - Version: $version, Path: $kickAssInstallPath" -Level "SUCCESS" -Component "Install-KickAssembler"
            } else {
                Write-ColoredOutput "Installation completed but JAR file not found in expected location." "Yellow" "WARNING" "Install-KickAssembler"
                Write-Log -Message "Installation verification warning - JAR file not found at expected location: $finalJarPath" -Level "WARNING" -Component "Install-KickAssembler"
            }
        }
        catch {
            Write-ColoredOutput "Installation completed but verification failed: $($_.Exception.Message)" "Yellow" "WARNING" "Install-KickAssembler"
            Write-ColoredOutput "KickAssembler may still be functional if Java is installed." "Yellow" "WARNING" "Install-KickAssembler"
            Write-Log -Message "Installation verification failed: $($_.Exception.Message)" -Level "WARNING" -Component "Install-KickAssembler"
        }
        
        Write-FunctionLog -FunctionName "Install-KickAssembler" -Action "EXIT" -Details "Installation process completed"
        
    }
    catch {
        Write-ColoredOutput "Error during KickAssembler installation: $($_.Exception.Message)" "Red" "ERROR" "Install-KickAssembler"
        Write-Log -Message "KickAssembler installation error: $($_.Exception.Message)" -Level "ERROR" -Component "Install-KickAssembler"
        Write-FunctionLog -FunctionName "Install-KickAssembler" -Action "ERROR" -Details $_.Exception.Message
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
$LogFile = Join-Path $LogDirectory "win_install_kickass.log"

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
    $LogFile = Join-Path (Get-Location) "win_install_kickass.log"
}

# Initialize log file
try {
    # Create or clear the log file
    $logHeader = @"
================================================================================
GameShell65 - KickAssembler65CE02 Installation Log
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
    Write-ColoredOutput "=== GameShell65 - KickAssembler65CE02 Installer ===" "Magenta" "INFO" "MAIN"
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
        $null = Invoke-WebRequest -Uri "https://gitlab.com" -Method Head -UseBasicParsing -TimeoutSec 10
        Write-ColoredOutput "Internet connection confirmed" "Green" "SUCCESS" "MAIN"
        Write-Log -Message "Internet connectivity confirmed" -Level "SUCCESS" -Component "MAIN"
    }
    catch {
        Write-ColoredOutput "ERROR: Internet connection required to download software" "Red" "ERROR" "MAIN"
        Write-ColoredOutput "Details: $($_.Exception.Message)" "Red" "ERROR" "MAIN"
        Write-Log -Message "FATAL: Internet connection failed - $($_.Exception.Message)" -Level "ERROR" -Component "MAIN"
        exit 1
    }
    
    # Check if Java is available
    Write-ColoredOutput "Checking Java availability..." "Yellow" "INFO" "MAIN"
    Write-Log -Message "Checking Java availability" -Level "INFO" -Component "MAIN"
    try {
        # Use java --version (double dash) and capture both stdout and stderr
        $javaOutput = & java --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $javaVersion = $javaOutput | Select-Object -First 1
            Write-ColoredOutput "Java found: $javaVersion" "Green" "SUCCESS" "MAIN"
            Write-Log -Message "Java detected successfully: $javaVersion" -Level "SUCCESS" -Component "MAIN"
        }
        else {
            Write-ColoredOutput "WARNING: Java not found in PATH. KickAssembler requires Java to run." "Yellow" "WARNING" "MAIN"
            Write-ColoredOutput "Please install Java from https://www.oracle.com/java/ or https://adoptium.net/" "Yellow" "WARNING" "MAIN"
            Write-Log -Message "Java not found in PATH - Exit code: $LASTEXITCODE" -Level "WARNING" -Component "MAIN"
        }
    }
    catch {
        Write-ColoredOutput "WARNING: Could not detect Java installation." "Yellow" "WARNING" "MAIN"
        Write-ColoredOutput "KickAssembler requires Java to run. Please ensure Java is installed." "Yellow" "WARNING" "MAIN"
        Write-Log -Message "Java detection failed: $($_.Exception.Message)" -Level "WARNING" -Component "MAIN"
    }
    
    # Create base directory
    New-InstallDirectory $resolvedInstallPath
    
    # Install KickAssembler
    Install-KickAssembler $resolvedInstallPath $tempDir
    
    Write-ColoredOutput "`n=== Installation completed successfully! ===" "Green" "SUCCESS" "MAIN"
    Write-ColoredOutput "IMPORTANT: Restart your session or open a new command window to use KickAssembler." "Yellow" "INFO" "MAIN"
    Write-ColoredOutput "`nNote: Java is required to run KickAssembler JAR files." "Yellow" "INFO" "MAIN"
    
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