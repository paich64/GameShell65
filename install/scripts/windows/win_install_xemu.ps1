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
            $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\xemu"
            Write-ColoredOutput "Using installation-based temporary directory: $tempDir" "Cyan" "INFO" "Get-TempDirectory"
        }
        else {
            # User provided temp directory
            $tempDir = Join-Path $UserTempDir "GameShell65_temp_Install\xemu"
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
                    $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\xemu"
                }
            }
        }
        
        # Ensure the temp directory path is not too long to avoid path issues
        if ($tempDir.Length -gt 100) {
            Write-ColoredOutput "Warning: Temporary directory path is long ($($tempDir.Length) chars). This may cause issues with some files." "Yellow" "WARNING" "Get-TempDirectory"
            Write-ColoredOutput "Consider using a shorter path like 'C:\Temp\XM65'" "Yellow" "WARNING" "Get-TempDirectory"
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
            
            # Direct download (GitHub raw URL doesn't require special handling)
            $downloadStartTime = Get-Date
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -TimeoutSec 60 -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            $downloadEndTime = Get-Date
            $downloadDuration = ($downloadEndTime - $downloadStartTime).TotalSeconds
            
            # Verify file was downloaded and has content
            if (Test-Path $OutputPath) {
                $fileSize = (Get-Item $OutputPath).Length
                Write-ColoredOutput "File downloaded, size: $fileSize bytes" "Cyan" "INFO" "Download-File"
                Write-Log -Message "Download completed - Size: $fileSize bytes, Duration: $([math]::Round($downloadDuration, 2)) seconds" -Level "SUCCESS" -Component "Download-File"
                
                # For ZIP files, expect at least 1MB for a valid XEMU distribution
                $expectedMinSize = if ($OutputPath.EndsWith(".zip")) { 1MB } else { 1KB }
                
                if ($fileSize -gt $expectedMinSize) {
                    # Additional check for ZIP files - verify it's actually a ZIP archive
                    if ($OutputPath.EndsWith(".zip")) {
                        try {
                            Write-Log -Message "Verifying ZIP file signature" -Level "DEBUG" -Component "Download-File"
                            $fileBytes = [System.IO.File]::ReadAllBytes($OutputPath)
                            # Check ZIP file signature (PK header)
                            if ($fileBytes.Length -ge 4 -and $fileBytes[0] -eq 0x50 -and $fileBytes[1] -eq 0x4B) {
                                Write-ColoredOutput "Download completed successfully - Valid ZIP file" "Green" "SUCCESS" "Download-File"
                                Write-Log -Message "ZIP file signature verification successful" -Level "SUCCESS" -Component "Download-File"
                                Write-FunctionLog -FunctionName "Download-File" -Action "EXIT" -Details "Success"
                                return
                            }
                            else {
                                # Check if it's an HTML file
                                $maxBytes = [Math]::Min(100, $fileBytes.Length - 1)
                                $firstBytes = [System.Text.Encoding]::ASCII.GetString($fileBytes[0..$maxBytes])
                                if ($firstBytes -match "<!DOCTYPE html>|<html") {
                                    $errorMsg = "Downloaded HTML page instead of ZIP file"
                                    Write-Log $errorMsg -Level "ERROR" -Component "Download-File"
                                    throw $errorMsg
                                }
                                else {
                                    $errorMsg = "Downloaded file is not a valid ZIP archive (no PK signature)"
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
                                $errorMsg = "Cannot verify ZIP file integrity: $($_.Exception.Message)"
                                Write-Log $errorMsg -Level "ERROR" -Component "Download-File"
                                throw $errorMsg
                            }
                        }
                    }
                    else {
                        Write-ColoredOutput "Download completed successfully" "Green" "SUCCESS" "Download-File"
                        Write-Log -Message "Non-ZIP file download completed successfully" -Level "SUCCESS" -Component "Download-File"
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

# Function to get the latest version info of XEMU from GitHub
function Get-LatestXemuInfo {
    Write-FunctionLog -FunctionName "Get-LatestXemuInfo" -Action "ENTER"
    
    Write-ColoredOutput "Checking XEMU availability..." "Yellow" "INFO" "Get-LatestXemuInfo"
    
    try {
        # The URL is fixed for the latest build, but let's verify it exists
        $downloadUrl = "https://github.com/lgblgblgb/xemu-binaries/raw/binary-windows-master/xemu-binaries-win64.zip"
        Write-ColoredOutput "Using XEMU download URL: $downloadUrl" "Cyan" "INFO" "Get-LatestXemuInfo"
        Write-Log -Message "Using XEMU download URL: $downloadUrl" -Level "INFO" -Component "Get-LatestXemuInfo"
        
        # Try to get file info from GitHub to verify it exists
        try {
            Write-Log -Message "Verifying XEMU binary availability" -Level "INFO" -Component "Get-LatestXemuInfo"
            $response = Invoke-WebRequest -Uri $downloadUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-ColoredOutput "XEMU binaries confirmed available" "Green" "SUCCESS" "Get-LatestXemuInfo"
                Write-Log -Message "XEMU binaries confirmed available (HTTP 200)" -Level "SUCCESS" -Component "Get-LatestXemuInfo"
                
                # Try to get file size from headers
                $contentLength = $response.Headers["Content-Length"]
                if ($contentLength) {
                    Write-ColoredOutput "Archive size: $contentLength bytes" "Cyan" "INFO" "Get-LatestXemuInfo"
                    Write-Log -Message "Archive size: $contentLength bytes" -Level "INFO" -Component "Get-LatestXemuInfo"
                }
                
                $result = @{
                    DownloadUrl = $downloadUrl
                    Version = "latest"
                    Available = $true
                }
                Write-Log -Message "XEMU info successfully retrieved" -Level "SUCCESS" -Component "Get-LatestXemuInfo"
                Write-FunctionLog -FunctionName "Get-LatestXemuInfo" -Action "EXIT" -Details "Success - Available"
                return $result
            }
            else {
                throw "HTTP $($response.StatusCode) response"
            }
        }
        catch {
            Write-ColoredOutput "Warning: Could not verify XEMU availability: $($_.Exception.Message)" "Yellow" "WARNING" "Get-LatestXemuInfo"
            Write-ColoredOutput "Will attempt download anyway..." "Yellow" "WARNING" "Get-LatestXemuInfo"
            Write-Log -Message "Could not verify XEMU availability: $($_.Exception.Message)" -Level "WARNING" -Component "Get-LatestXemuInfo"
            
            $result = @{
                DownloadUrl = $downloadUrl
                Version = "latest"
                Available = $false
            }
            Write-FunctionLog -FunctionName "Get-LatestXemuInfo" -Action "EXIT" -Details "Warning - Not verified"
            return $result
        }
    }
    catch {
        Write-ColoredOutput "ERROR: Unable to check XEMU availability" "Red" "ERROR" "Get-LatestXemuInfo"
        Write-ColoredOutput "Details: $($_.Exception.Message)" "Red" "ERROR" "Get-LatestXemuInfo"
        Write-Log -Message "Failed to get XEMU information: $($_.Exception.Message)" -Level "ERROR" -Component "Get-LatestXemuInfo"
        Write-FunctionLog -FunctionName "Get-LatestXemuInfo" -Action "ERROR" -Details $_.Exception.Message
        throw "Failed to get XEMU information: $($_.Exception.Message)"
    }
}

# Function to safely copy files handling long paths
function Copy-XemuFiles {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )
    
    Write-FunctionLog -FunctionName "Copy-XemuFiles" -Action "ENTER" -Details "Source: $SourcePath, Destination: $DestinationPath"
    
    Write-ColoredOutput "Copying XEMU files from: $SourcePath" "Yellow" "INFO" "Copy-XemuFiles"
    Write-ColoredOutput "To: $DestinationPath" "Yellow" "INFO" "Copy-XemuFiles"
    Write-Log -Message "Starting file copy from $SourcePath to $DestinationPath" -Level "INFO" -Component "Copy-XemuFiles"
    
    try {
        # Try standard copy first
        Write-Log -Message "Attempting standard PowerShell copy" -Level "DEBUG" -Component "Copy-XemuFiles"
        Copy-Item -Path "$SourcePath\*" -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
        Write-ColoredOutput "Standard copy completed successfully" "Green" "SUCCESS" "Copy-XemuFiles"
        Write-Log -Message "Standard copy completed successfully" -Level "SUCCESS" -Component "Copy-XemuFiles"
        Write-FunctionLog -FunctionName "Copy-XemuFiles" -Action "EXIT" -Details "Standard copy success"
    }
    catch [System.IO.PathTooLongException] {
        Write-ColoredOutput "Long path detected, using robocopy for file transfer..." "Yellow" "WARNING" "Copy-XemuFiles"
        Write-Log -Message "Long path detected, switching to robocopy" -Level "WARNING" -Component "Copy-XemuFiles"
        
        # Use robocopy for long path support
        Write-Log -Message "Executing robocopy with parameters: /E /R:1 /W:1 /NP /NDL /NJH /NJS" -Level "DEBUG" -Component "Copy-XemuFiles"
        $robocopyResult = robocopy "$SourcePath" "$DestinationPath" /E /R:1 /W:1 /NP /NDL /NJH /NJS
        
        # Check robocopy exit code (0-7 are success codes)
        Write-Log -Message "Robocopy completed with exit code: $LASTEXITCODE" -Level "INFO" -Component "Copy-XemuFiles"
        if ($LASTEXITCODE -le 7) {
            Write-ColoredOutput "Robocopy transfer completed successfully" "Green" "SUCCESS" "Copy-XemuFiles"
            Write-Log -Message "Robocopy transfer completed successfully" -Level "SUCCESS" -Component "Copy-XemuFiles"
        } else {
            $warningMsg = "Some files may not have been copied (robocopy exit code: $LASTEXITCODE)"
            Write-ColoredOutput "Warning: $warningMsg" "Yellow" "WARNING" "Copy-XemuFiles"
            Write-Log $warningMsg -Level "WARNING" -Component "Copy-XemuFiles"
        }
        Write-FunctionLog -FunctionName "Copy-XemuFiles" -Action "EXIT" -Details "Robocopy method used"
    }
    catch {
        $errorMsg = "Error during file copy: $($_.Exception.Message)"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Copy-XemuFiles"
        Write-Log $errorMsg -Level "ERROR" -Component "Copy-XemuFiles"
        Write-FunctionLog -FunctionName "Copy-XemuFiles" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to extract ZIP archive files
function Extract-XemuArchive {
    param(
        [string]$ArchivePath,
        [string]$ExtractPath
    )
    
    Write-FunctionLog -FunctionName "Extract-XemuArchive" -Action "ENTER" -Details "Archive: $ArchivePath, Extract: $ExtractPath"
    
    Write-ColoredOutput "Extracting XEMU archive: $(Split-Path $ArchivePath -Leaf)" "Yellow" "INFO" "Extract-XemuArchive"
    Write-Log -Message "Starting ZIP extraction: $(Split-Path $ArchivePath -Leaf)" -Level "INFO" -Component "Extract-XemuArchive"
    
    # Use PowerShell's native Expand-Archive for ZIP files
    try {
        # Verify the ZIP file integrity first
        Write-Log -Message "Verifying ZIP file integrity" -Level "DEBUG" -Component "Extract-XemuArchive"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
        $entryCount = $zip.Entries.Count
        $zip.Dispose()
        Write-ColoredOutput "Archive contains $entryCount entries" "Cyan" "INFO" "Extract-XemuArchive"
        Write-Log -Message "Archive contains $entryCount entries" -Level "INFO" -Component "Extract-XemuArchive"
        
        # Extract with PowerShell
        Write-Log -Message "Starting PowerShell Expand-Archive" -Level "DEBUG" -Component "Extract-XemuArchive"
        Expand-Archive -Path $ArchivePath -DestinationPath $ExtractPath -Force -ErrorAction Stop
        Write-ColoredOutput "ZIP extraction completed successfully" "Green" "SUCCESS" "Extract-XemuArchive"
        Write-Log -Message "ZIP extraction completed successfully" -Level "SUCCESS" -Component "Extract-XemuArchive"
        
        Write-FunctionLog -FunctionName "Extract-XemuArchive" -Action "EXIT" -Details "Success: $entryCount entries"
        return $ExtractPath
    }
    catch [System.IO.PathTooLongException] {
        Write-ColoredOutput "Long path detected during extraction, using alternative method..." "Yellow" "WARNING" "Extract-XemuArchive"
        Write-Log -Message "Long path detected during extraction, using alternative method" -Level "WARNING" -Component "Extract-XemuArchive"
        
        # Try with even shorter path
        $shorterExtractPath = Join-Path ([System.IO.Path]::GetTempPath()) "XM"
        New-InstallDirectory $shorterExtractPath
        
        try {
            Write-Log -Message "Attempting extraction to shorter path: $shorterExtractPath" -Level "INFO" -Component "Extract-XemuArchive"
            Expand-Archive -Path $ArchivePath -DestinationPath $shorterExtractPath -Force -ErrorAction Stop
            Write-ColoredOutput "Alternative extraction completed to: $shorterExtractPath" "Green" "SUCCESS" "Extract-XemuArchive"
            Write-Log -Message "Alternative extraction completed successfully" -Level "SUCCESS" -Component "Extract-XemuArchive"
            Write-FunctionLog -FunctionName "Extract-XemuArchive" -Action "EXIT" -Details "Success - Alternative path"
            return $shorterExtractPath
        }
        catch {
            $errorMsg = "Unable to extract XEMU archive due to long path limitations. Consider using a shorter temporary directory path."
            Write-Log $errorMsg -Level "ERROR" -Component "Extract-XemuArchive"
            throw $errorMsg
        }
    }
    catch {
        $errorMsg = "ZIP extraction error: $($_.Exception.Message)"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Extract-XemuArchive"
        Write-Log $errorMsg -Level "ERROR" -Component "Extract-XemuArchive"
        Write-FunctionLog -FunctionName "Extract-XemuArchive" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to install XEMU with configurable temp directory
function Install-Xemu {
    param(
        [string]$BaseInstallPath,
        [string]$TempDir
    )
    
    Write-FunctionLog -FunctionName "Install-Xemu" -Action "ENTER" -Details "BaseInstallPath: $BaseInstallPath, TempDir: $TempDir"
    
    Write-ColoredOutput "`n=== MEGA65 XEMU Emulator Installation ===" "Magenta" "INFO" "Install-Xemu"
    Write-Log -Message "Starting XEMU installation process" -Level "INFO" -Component "Install-Xemu"
    Write-Log -Message "Base installation path: $BaseInstallPath" -Level "INFO" -Component "Install-Xemu"
    Write-Log -Message "Temporary directory: $TempDir" -Level "INFO" -Component "Install-Xemu"
    
    try {
        # Get latest XEMU info
        Write-Log -Message "Getting latest XEMU information" -Level "INFO" -Component "Install-Xemu"
        $xemuInfo = Get-LatestXemuInfo
        $downloadUrl = $xemuInfo.DownloadUrl
        $version = $xemuInfo.Version
        
        Write-ColoredOutput "Installing MEGA65 XEMU ($version) from GitHub" "Cyan" "INFO" "Install-Xemu"
        Write-Log -Message "Selected XEMU version: $version" -Level "INFO" -Component "Install-Xemu"
        
        # Configure paths - Install directly in BaseInstallPath\xemu
        $xemuInstallPath = Join-Path $BaseInstallPath "xemu"
        $xemuZipPath = Join-Path $TempDir "xemu.zip"
        $xemuExtractPath = Join-Path $TempDir "extract"
        
        Write-ColoredOutput "XEMU will be installed to: $xemuInstallPath" "Cyan" "INFO" "Install-Xemu"
        
        Write-Log -Message "Installation paths configured:" -Level "DEBUG" -Component "Install-Xemu"
        Write-Log -Message "  Install path: $xemuInstallPath" -Level "DEBUG" -Component "Install-Xemu"
        Write-Log -Message "  Download path: $xemuZipPath" -Level "DEBUG" -Component "Install-Xemu"
        Write-Log -Message "  Extract path: $xemuExtractPath" -Level "DEBUG" -Component "Install-Xemu"
        
        # Create directories
        Write-Log -Message "Creating required directories" -Level "INFO" -Component "Install-Xemu"
        New-InstallDirectory $xemuInstallPath
        New-InstallDirectory $TempDir
        New-InstallDirectory $xemuExtractPath
        
        # Download with retry logic
        Write-Log -Message "Starting XEMU download from: $downloadUrl" -Level "INFO" -Component "Install-Xemu"
        Download-File $downloadUrl $xemuZipPath
        
        # Verify downloaded file
        $fileSize = (Get-Item $xemuZipPath).Length
        Write-ColoredOutput "Downloaded file size: $fileSize bytes" "Cyan" "INFO" "Install-Xemu"
        Write-Log -Message "Downloaded file verification: $fileSize bytes" -Level "INFO" -Component "Install-Xemu"
        
        if ($fileSize -lt 1024) {
            $errorMsg = "Downloaded file is too small, may be corrupted"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-Xemu"
            throw $errorMsg
        }
        
        # Extract with error handling
        Write-Log -Message "Starting archive extraction" -Level "INFO" -Component "Install-Xemu"
        $actualExtractPath = Extract-XemuArchive $xemuZipPath $xemuExtractPath
        
        # Find the extracted content
        $extractedItems = Get-ChildItem -Path $actualExtractPath -ErrorAction SilentlyContinue
        Write-ColoredOutput "Found $($extractedItems.Count) items in extracted archive" "Cyan" "INFO" "Install-Xemu"
        Write-Log -Message "Archive contents: $($extractedItems.Count) items found" -Level "INFO" -Component "Install-Xemu"
        
        # Look for XEMU directory structure
        $sourceDirectory = $actualExtractPath
        Write-Log -Message "Initial source directory: $sourceDirectory" -Level "DEBUG" -Component "Install-Xemu"
        
        # Check if there's a subdirectory with the XEMU content
        $xemuSubDir = $extractedItems | Where-Object { $_.PSIsContainer -and ($_.Name -match "xemu" -or $_.Name -match "XEMU") } | Select-Object -First 1
        if ($xemuSubDir) {
            $sourceDirectory = $xemuSubDir.FullName
            Write-ColoredOutput "Using XEMU subdirectory: $($xemuSubDir.Name)" "Cyan" "INFO" "Install-Xemu"
            Write-Log -Message "Found XEMU subdirectory: $($xemuSubDir.Name), using: $sourceDirectory" -Level "INFO" -Component "Install-Xemu"
        }
        else {
            Write-Log -Message "No XEMU subdirectory found, using root extract directory" -Level "DEBUG" -Component "Install-Xemu"
        }
        
        # Copy all files with long path handling
        Write-ColoredOutput "Installing to: $xemuInstallPath" "Yellow" "INFO" "Install-Xemu"
        Write-Log -Message "Starting file installation to: $xemuInstallPath" -Level "INFO" -Component "Install-Xemu"
        Copy-XemuFiles $sourceDirectory $xemuInstallPath
        
        # Find XEMU executables in the installed directory
        Write-Log -Message "Searching for XEMU executables" -Level "DEBUG" -Component "Install-Xemu"
        $xemuExecutables = Get-ChildItem -Path $xemuInstallPath -Name "*.exe" -Recurse | Where-Object { $_ -match "(xemu|mega65)" }
        if ($xemuExecutables.Count -eq 0) {
            # Look for any .exe files as fallback
            Write-Log -Message "No specific XEMU executables found, looking for any .exe files" -Level "WARNING" -Component "Install-Xemu"
            $xemuExecutables = Get-ChildItem -Path $xemuInstallPath -Name "*.exe" -Recurse
        }
        
        if ($xemuExecutables.Count -eq 0) {
            $errorMsg = "XEMU executables not found after installation"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-Xemu"
            throw $errorMsg
        }
        
        Write-ColoredOutput "Found XEMU executables:" "Green" "SUCCESS" "Install-Xemu"
        Write-Log -Message "XEMU executables found: $($xemuExecutables.Count)" -Level "SUCCESS" -Component "Install-Xemu"
        foreach ($exe in $xemuExecutables) {
            $exePath = Join-Path $xemuInstallPath $exe
            Write-ColoredOutput "  - $exePath" "Cyan" "INFO" "Install-Xemu"
            Write-Log -Message "  Executable: $exePath" -Level "INFO" -Component "Install-Xemu"
        }
        
        # Configure environment variables
        Write-ColoredOutput "Configuring environment variables..." "Yellow" "INFO" "Install-Xemu"
        Write-Log -Message "Starting environment variable configuration" -Level "INFO" -Component "Install-Xemu"
        
        # Determine the correct bin directory (where executables are located)
        $firstExe = Join-Path $xemuInstallPath $xemuExecutables[0]
        $xemuBinPath = Split-Path $firstExe -Parent
        Write-Log -Message "XEMU bin directory determined: $xemuBinPath" -Level "INFO" -Component "Install-Xemu"
        
        # Add XEMU bin directory to system PATH
        try {
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            if ($currentPath -notlike "*$xemuBinPath*") {
                $newPath = "$currentPath;$xemuBinPath"
                [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
                Write-ColoredOutput "XEMU added to system PATH: $xemuBinPath" "Green" "SUCCESS" "Install-Xemu"
                Write-Log -Message "XEMU added to system PATH: $xemuBinPath" -Level "SUCCESS" -Component "Install-Xemu"
            } else {
                Write-ColoredOutput "XEMU already present in system PATH" "Yellow" "WARNING" "Install-Xemu"
                Write-Log -Message "XEMU already present in system PATH" -Level "WARNING" -Component "Install-Xemu"
            }
            
            # Update PATH for current session
            if ($env:PATH -notlike "*$xemuBinPath*") {
                $env:PATH += ";$xemuBinPath"
                Write-Log -Message "Current session PATH updated" -Level "DEBUG" -Component "Install-Xemu"
            }
        }
        catch {
            $errorMsg = "Failed to update system PATH: $($_.Exception.Message)"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-Xemu"
            Write-ColoredOutput "Warning: $errorMsg" "Yellow" "WARNING" "Install-Xemu"
        }
        
        # Set XEMU_HOME environment variable
        try {
            [Environment]::SetEnvironmentVariable("XEMU_HOME", $xemuInstallPath, "Machine")
            $env:XEMU_HOME = $xemuInstallPath
            Write-ColoredOutput "XEMU_HOME environment variable set: $xemuInstallPath" "Green" "SUCCESS" "Install-Xemu"
            Write-Log -Message "XEMU_HOME environment variable set: $xemuInstallPath" -Level "SUCCESS" -Component "Install-Xemu"
        }
        catch {
            $errorMsg = "Failed to set XEMU_HOME environment variable: $($_.Exception.Message)"
            Write-Log $errorMsg -Level "ERROR" -Component "Install-Xemu"
            Write-ColoredOutput "Warning: $errorMsg" "Yellow" "WARNING" "Install-Xemu"
        }
        
        # Cleanup temporary files
        Write-ColoredOutput "Cleaning up temporary files..." "Yellow" "INFO" "Install-Xemu"
        Write-Log -Message "Starting temporary file cleanup" -Level "INFO" -Component "Install-Xemu"
        try {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColoredOutput "Cleanup completed" "Green" "SUCCESS" "Install-Xemu"
            Write-Log -Message "Temporary file cleanup completed successfully" -Level "SUCCESS" -Component "Install-Xemu"
        }
        catch {
            $warningMsg = "Some temporary files may remain in $TempDir : $($_.Exception.Message)"
            Write-ColoredOutput "Warning: $warningMsg" "Yellow" "WARNING" "Install-Xemu"
            Write-Log $warningMsg -Level "WARNING" -Component "Install-Xemu"
        }
        
        # Verify installation - CORRECTION: Use hardcoded binary name
        Write-ColoredOutput "Verifying installation..." "Yellow" "INFO" "Install-Xemu"
        Write-Log -Message "Starting installation verification" -Level "INFO" -Component "Install-Xemu"
        try {
            # CORRECTION: The main executable is always named xmega65.exe
            $mainExePath = Join-Path $xemuInstallPath "xmega65.exe"
            
            Write-Log -Message "Verifying executable path: $mainExePath" -Level "DEBUG" -Component "Install-Xemu"
            
            if (Test-Path $mainExePath) {
                Write-ColoredOutput "MEGA65 XEMU installed successfully!" "Green" "SUCCESS" "Install-Xemu"
                Write-ColoredOutput "Installation directory: $xemuInstallPath" "Green" "SUCCESS" "Install-Xemu"
                Write-ColoredOutput "Main executable: $mainExePath" "Green" "SUCCESS" "Install-Xemu"
                Write-ColoredOutput "Available executables: $($xemuExecutables -join ', ')" "Green" "SUCCESS" "Install-Xemu"
                
                # Display additional info about XEMU
                Write-ColoredOutput "`nXEMU Usage Notes:" "Yellow" "INFO" "Install-Xemu"
                Write-ColoredOutput "- XEMU is a MEGA65 emulator" "Cyan" "INFO" "Install-Xemu"
                Write-ColoredOutput "- You may need MEGA65 ROM files to run software" "Cyan" "INFO" "Install-Xemu"
                Write-ColoredOutput "- Check the XEMU documentation for ROM setup" "Cyan" "INFO" "Install-Xemu"
                
                Write-Log -Message "XEMU installation completed successfully!" -Level "SUCCESS" -Component "Install-Xemu"
                Write-Log -Message "Installation verified - Main executable found: $mainExePath" -Level "SUCCESS" -Component "Install-Xemu"
                Write-Log -Message "Final installation summary:" -Level "INFO" -Component "Install-Xemu"
                Write-Log -Message "  Version: $version" -Level "INFO" -Component "Install-Xemu"
                Write-Log -Message "  Directory: $xemuInstallPath" -Level "INFO" -Component "Install-Xemu"
                Write-Log -Message "  Executables: $($xemuExecutables -join ', ')" -Level "INFO" -Component "Install-Xemu"
            } else {
                $warningMsg = "Installation completed but main executable not found at expected location: $mainExePath"
                Write-ColoredOutput $warningMsg "Yellow" "WARNING" "Install-Xemu"
                Write-Log $warningMsg -Level "WARNING" -Component "Install-Xemu"
            }
        }
        catch {
            $warningMsg = "Installation completed but verification failed: $($_.Exception.Message)"
            Write-ColoredOutput $warningMsg "Yellow" "WARNING" "Install-Xemu"
            Write-ColoredOutput "XEMU may still be functional. Try opening a new command prompt." "Yellow" "WARNING" "Install-Xemu"
            Write-Log $warningMsg -Level "WARNING" -Component "Install-Xemu"
        }
        
        Write-FunctionLog -FunctionName "Install-Xemu" -Action "EXIT" -Details "Installation process completed"
        
    }
    catch {
        $errorMsg = "Error during XEMU installation: $($_.Exception.Message)"
        Write-ColoredOutput $errorMsg "Red" "ERROR" "Install-Xemu"
        Write-Log $errorMsg -Level "ERROR" -Component "Install-Xemu"
        Write-FunctionLog -FunctionName "Install-Xemu" -Action "ERROR" -Details $_.Exception.Message
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
$LogFile = Join-Path $LogDirectory "win_install_xemu.log"

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
    $LogFile = Join-Path (Get-Location) "win_install_xemu.log"
}

# Initialize log file
try {
    # Create or clear the log file
    $logHeader = @"
================================================================================
GameShell65 - XEMU Installation Log
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
    Write-ColoredOutput "=== GameShell65 - MEGA65 XEMU Emulator Installer ===" "Magenta" "INFO" "MAIN"
    Write-ColoredOutput "Base installation directory: $resolvedInstallPath" "Cyan" "INFO" "MAIN"
    Write-Log -Message "Script execution started" -Level "INFO" -Component "MAIN"
    Write-Log -Message "Parameters - InstallationPath: $resolvedInstallPath, TempDirectory: $TempDirectory" -Level "INFO" -Component "MAIN"
    
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
    
    # Check internet connection
    Write-ColoredOutput "Checking internet connection..." "Yellow" "INFO" "MAIN"
    Write-Log -Message "Testing internet connectivity" -Level "INFO" -Component "MAIN"
    try {
        $null = Invoke-WebRequest -Uri "https://github.com" -Method Head -UseBasicParsing -TimeoutSec 10
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
    
    # Install XEMU with custom temp directory
    Write-Log -Message "Starting XEMU installation process" -Level "INFO" -Component "MAIN"
    Install-Xemu $resolvedInstallPath $tempDir
    
    Write-ColoredOutput "`n=== Installation completed successfully! ===" "Green" "SUCCESS" "MAIN"
    Write-ColoredOutput "IMPORTANT: Restart your session or open a new command window to use XEMU." "Yellow" "INFO" "MAIN"
    Write-ColoredOutput "You can start the MEGA65 emulator by running the XEMU executable" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "XEMU has been installed in: $resolvedInstallPath\xemu" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "`nNote: You may need MEGA65 ROM files for full functionality." "Yellow" "INFO" "MAIN"
    
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