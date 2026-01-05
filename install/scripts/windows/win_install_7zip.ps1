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
            $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\7zip"
            Write-ColoredOutput "Using installation-based temporary directory: $tempDir" "Cyan" "INFO" "Get-TempDirectory"
        }
        else {
            # User provided temp directory
            $tempDir = Join-Path $UserTempDir "GameShell65_temp_Install\7zip"
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
                    $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\7zip"
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

# Function to download a file with progress and clean filename
function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    Write-FunctionLog -FunctionName "Download-File" -Action "ENTER" -Details "URL: $Url, OutputPath: $OutputPath"
    
    try {
        # Clean the output path to remove URL parameters and invalid characters
        $cleanFileName = [System.IO.Path]::GetFileName($OutputPath)
        if ($cleanFileName -match '^([^?]+)') {
            $cleanFileName = $matches[1]
        }
        
        # Remove invalid filename characters
        $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
        foreach ($char in $invalidChars) {
            $cleanFileName = $cleanFileName.Replace($char, '_')
        }
        
        $cleanOutputPath = Join-Path (Split-Path $OutputPath -Parent) $cleanFileName
        
        Write-ColoredOutput "Downloading from: $Url" "Cyan" "INFO" "Download-File"
        Write-ColoredOutput "Destination: $cleanOutputPath" "Cyan" "INFO" "Download-File"
        
        $downloadStartTime = Get-Date
        Invoke-WebRequest -Uri $Url -OutFile $cleanOutputPath -UseBasicParsing
        $downloadEndTime = Get-Date
        $downloadDuration = ($downloadEndTime - $downloadStartTime).TotalSeconds
        
        $fileSize = (Get-Item $cleanOutputPath).Length
        Write-ColoredOutput "Download completed successfully" "Green" "SUCCESS" "Download-File"
        Write-Log -Message "Download completed - Size: $fileSize bytes, Duration: $([math]::Round($downloadDuration, 2)) seconds" -Level "SUCCESS" -Component "Download-File"
        
        Write-FunctionLog -FunctionName "Download-File" -Action "EXIT" -Details "Success: $cleanOutputPath"
        return $cleanOutputPath  # Return the actual path used
    }
    catch {
        Write-ColoredOutput "Download error: $($_.Exception.Message)" "Red" "ERROR" "Download-File"
        Write-FunctionLog -FunctionName "Download-File" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to get the latest version of 7-Zip
function Get-Latest7ZipVersion {
    Write-FunctionLog -FunctionName "Get-Latest7ZipVersion" -Action "ENTER"
    
    Write-ColoredOutput "Searching for latest 7-Zip version..." "Yellow" "INFO" "Get-Latest7ZipVersion"
    
    try {
        # Try GitHub API first (more reliable)
        try {
            Write-ColoredOutput "Attempting via GitHub API..." "Cyan" "INFO" "Get-Latest7ZipVersion"
            Write-Log -Message "Attempting to fetch version from GitHub API" -Level "INFO" -Component "Get-Latest7ZipVersion"
            
            $response = Invoke-RestMethod -Uri "https://api.github.com/repos/ip7z/7zip/releases/latest" -UseBasicParsing -TimeoutSec 20
            
            if ($response -and $response.tag_name) {
                $version = $response.tag_name -replace '^v', ''
                
                # Look for Windows x64 asset
                $windowsAsset = $response.assets | Where-Object {
                    $_.name -like "*x64*" -and $_.name -like "*.exe"
                } | Select-Object -First 1
                
                if ($windowsAsset) {
                    Write-ColoredOutput "Found via GitHub: v$version" "Green" "SUCCESS" "Get-Latest7ZipVersion"
                    $result = @{
                        Version = $version
                        DownloadUrl = $windowsAsset.browser_download_url
                        FileName = $windowsAsset.name
                        Source = "GitHub API"
                    }
                    Write-Log -Message "GitHub API success - Version: $version, URL: $($windowsAsset.browser_download_url)" -Level "SUCCESS" -Component "Get-Latest7ZipVersion"
                    Write-FunctionLog -FunctionName "Get-Latest7ZipVersion" -Action "EXIT" -Details "GitHub API Success"
                    return $result
                }
            }
        }
        catch {
            Write-ColoredOutput "GitHub API failed: $($_.Exception.Message)" "Yellow" "WARNING" "Get-Latest7ZipVersion"
            Write-Log -Message "GitHub API failed: $($_.Exception.Message)" -Level "WARNING" -Component "Get-Latest7ZipVersion"
        }
        
        # Fallback to known URLs
        Write-ColoredOutput "Using fallback URLs..." "Yellow" "WARNING" "Get-Latest7ZipVersion"
        Write-Log -Message "Falling back to hardcoded URLs" -Level "WARNING" -Component "Get-Latest7ZipVersion"
        
        $fallbackUrls = @(
            @{ Url = "https://www.7-zip.org/a/7z2501-x64.exe"; Version = "25.01" },
            @{ Url = "https://www.7-zip.org/a/7z2400-x64.exe"; Version = "24.00" },
            @{ Url = "https://www.7-zip.org/a/7z2301-x64.exe"; Version = "23.01" }
        )
        
        foreach ($fallback in $fallbackUrls) {
            try {
                Write-ColoredOutput "Testing: $($fallback.Url)" "Gray" "DEBUG" "Get-Latest7ZipVersion"
                Write-Log -Message "Testing fallback URL: $($fallback.Url)" -Level "DEBUG" -Component "Get-Latest7ZipVersion"
                
                $testResponse = Invoke-WebRequest -Uri $fallback.Url -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                
                if ($testResponse.StatusCode -eq 200) {
                    Write-ColoredOutput "Valid URL found: v$($fallback.Version)" "Green" "SUCCESS" "Get-Latest7ZipVersion"
                    $result = @{
                        Version = $fallback.Version
                        DownloadUrl = $fallback.Url
                        FileName = [System.IO.Path]::GetFileName($fallback.Url)
                        Source = "Fallback URL"
                    }
                    Write-Log -Message "Fallback URL success - Version: $($fallback.Version), URL: $($fallback.Url)" -Level "SUCCESS" -Component "Get-Latest7ZipVersion"
                    Write-FunctionLog -FunctionName "Get-Latest7ZipVersion" -Action "EXIT" -Details "Fallback Success"
                    return $result
                }
            }
            catch {
                Write-Log -Message "Fallback URL failed: $($fallback.Url) - Error: $($_.Exception.Message)" -Level "DEBUG" -Component "Get-Latest7ZipVersion"
                continue
            }
        }
        
        throw "No valid URL found"
    }
    catch {
        Write-ColoredOutput "ERROR: Unable to retrieve 7-Zip information" "Red" "ERROR" "Get-Latest7ZipVersion"
        Write-ColoredOutput "Details: $($_.Exception.Message)" "Red" "ERROR" "Get-Latest7ZipVersion"
        Write-FunctionLog -FunctionName "Get-Latest7ZipVersion" -Action "ERROR" -Details $_.Exception.Message
        throw "Failed to retrieve 7-Zip version: $($_.Exception.Message)"
    }
}

# Function to extract 7-Zip installer
function Extract-7ZipInstaller {
    param(
        [string]$InstallerPath,
        [string]$ExtractPath
    )
    
    Write-FunctionLog -FunctionName "Extract-7ZipInstaller" -Action "ENTER" -Details "Installer: $InstallerPath, ExtractPath: $ExtractPath"
    
    Write-ColoredOutput "Extracting 7-Zip installer..." "Yellow" "INFO" "Extract-7ZipInstaller"
    
    try {
        # Method 1: Try to run with /S (silent) flag to extract
        Write-ColoredOutput "Attempting silent extraction method..." "Cyan" "INFO" "Extract-7ZipInstaller"
        Write-Log -Message "Attempting silent extraction method" -Level "INFO" -Component "Extract-7ZipInstaller"
        
        # Create a temporary batch file to handle the extraction
        $batchFile = Join-Path $ExtractPath "extract.bat"
        $batchContent = "@echo off`n`"$InstallerPath`" /S /D=`"$ExtractPath`""
        $batchContent | Out-File -FilePath $batchFile -Encoding ASCII
        
        try {
            $extractProcess = Start-Process -FilePath $batchFile -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
            
            if ($extractProcess.ExitCode -eq 0) {
                Write-ColoredOutput "Silent extraction completed" "Green" "SUCCESS" "Extract-7ZipInstaller"
                Write-Log -Message "Silent extraction successful" -Level "SUCCESS" -Component "Extract-7ZipInstaller"
                Remove-Item -Path $batchFile -Force -ErrorAction SilentlyContinue
                Write-FunctionLog -FunctionName "Extract-7ZipInstaller" -Action "EXIT" -Details "Silent extraction success"
                return $true
            }
        }
        catch {
            Write-ColoredOutput "Silent extraction failed, trying alternative method..." "Yellow" "WARNING" "Extract-7ZipInstaller"
            Write-Log -Message "Silent extraction failed: $($_.Exception.Message)" -Level "WARNING" -Component "Extract-7ZipInstaller"
        }
        
        # Method 2: Try to extract using PowerShell if it's a ZIP-based installer
        try {
            Write-ColoredOutput "Attempting PowerShell extraction..." "Cyan" "INFO" "Extract-7ZipInstaller"
            Write-Log -Message "Attempting PowerShell extraction method" -Level "INFO" -Component "Extract-7ZipInstaller"
            
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($InstallerPath, $ExtractPath)
            Write-ColoredOutput "PowerShell extraction completed" "Green" "SUCCESS" "Extract-7ZipInstaller"
            Write-Log -Message "PowerShell extraction successful" -Level "SUCCESS" -Component "Extract-7ZipInstaller"
            Write-FunctionLog -FunctionName "Extract-7ZipInstaller" -Action "EXIT" -Details "PowerShell extraction success"
            return $true
        }
        catch {
            Write-ColoredOutput "PowerShell extraction failed" "Yellow" "WARNING" "Extract-7ZipInstaller"
            Write-Log -Message "PowerShell extraction failed: $($_.Exception.Message)" -Level "WARNING" -Component "Extract-7ZipInstaller"
        }
        
        # Method 3: Manual extraction using Windows built-in tools
        try {
            Write-ColoredOutput "Attempting manual extraction using Windows tools..." "Cyan" "INFO" "Extract-7ZipInstaller"
            Write-Log -Message "Attempting manual extraction using expand.exe" -Level "INFO" -Component "Extract-7ZipInstaller"
            
            # Try using expand.exe (Windows built-in)
            $expandResult = & expand.exe "$InstallerPath" -F:* "$ExtractPath" 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-ColoredOutput "Manual extraction completed" "Green" "SUCCESS" "Extract-7ZipInstaller"
                Write-Log -Message "Manual extraction successful using expand.exe" -Level "SUCCESS" -Component "Extract-7ZipInstaller"
                Write-FunctionLog -FunctionName "Extract-7ZipInstaller" -Action "EXIT" -Details "Manual extraction success"
                return $true
            }
        }
        catch {
            Write-ColoredOutput "Manual extraction failed" "Yellow" "WARNING" "Extract-7ZipInstaller"
            Write-Log -Message "Manual extraction failed: $($_.Exception.Message)" -Level "WARNING" -Component "Extract-7ZipInstaller"
        }
        
        # Method 4: Just copy the installer and let user know
        Write-ColoredOutput "All extraction methods failed. Copying installer for manual handling..." "Yellow" "WARNING" "Extract-7ZipInstaller"
        Write-Log -Message "All extraction methods failed, copying installer for manual handling" -Level "WARNING" -Component "Extract-7ZipInstaller"
        
        $installerCopy = Join-Path $ExtractPath "7zip-installer.exe"
        Copy-Item -Path $InstallerPath -Destination $installerCopy -Force
        
        Write-ColoredOutput "7-Zip installer copied to: $installerCopy" "Yellow" "WARNING" "Extract-7ZipInstaller"
        Write-ColoredOutput "You may need to run this manually after the script completes." "Yellow" "WARNING" "Extract-7ZipInstaller"
        
        Write-FunctionLog -FunctionName "Extract-7ZipInstaller" -Action "EXIT" -Details "Manual copy fallback"
        return $false
    }
    catch {
        Write-ColoredOutput "Extraction error: $($_.Exception.Message)" "Red" "ERROR" "Extract-7ZipInstaller"
        Write-FunctionLog -FunctionName "Extract-7ZipInstaller" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to safely copy files handling long paths
function Copy-7ZipFiles {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )
    
    Write-FunctionLog -FunctionName "Copy-7ZipFiles" -Action "ENTER" -Details "Source: $SourcePath, Destination: $DestinationPath"
    
    Write-ColoredOutput "Copying 7-Zip files from: $SourcePath" "Yellow" "INFO" "Copy-7ZipFiles"
    Write-ColoredOutput "To: $DestinationPath" "Yellow" "INFO" "Copy-7ZipFiles"
    
    try {
        # Look for 7-Zip files in common locations within the extraction
        $possibleSources = @(
            $SourcePath,
            (Join-Path $SourcePath "Files"),
            (Join-Path $SourcePath "Program Files"),
            (Join-Path $SourcePath "7-Zip")
        )
        
        Write-Log -Message "Searching for 7-Zip files in possible source locations" -Level "INFO" -Component "Copy-7ZipFiles"
        
        $actualSource = $null
        foreach ($testPath in $possibleSources) {
            Write-Log -Message "Checking path: $testPath" -Level "DEBUG" -Component "Copy-7ZipFiles"
            if (Test-Path $testPath) {
                $sevenZipExe = Join-Path $testPath "7z.exe"
                if (Test-Path $sevenZipExe) {
                    $actualSource = $testPath
                    Write-Log -Message "Found 7z.exe in: $actualSource" -Level "SUCCESS" -Component "Copy-7ZipFiles"
                    break
                }
            }
        }
        
        if (-not $actualSource) {
            # Look for any directory containing 7z.exe
            Write-Log -Message "Standard locations failed, performing recursive search for 7z.exe" -Level "INFO" -Component "Copy-7ZipFiles"
            $foundExe = Get-ChildItem -Path $SourcePath -Name "7z.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($foundExe) {
                $actualSource = Split-Path (Join-Path $SourcePath $foundExe) -Parent
                Write-ColoredOutput "Found 7z.exe in: $actualSource" "Green" "SUCCESS" "Copy-7ZipFiles"
            }
        }
        
        if ($actualSource) {
            # Try standard copy first
            Write-Log -Message "Attempting standard copy from: $actualSource" -Level "INFO" -Component "Copy-7ZipFiles"
            Copy-Item -Path "$actualSource\*" -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
            Write-ColoredOutput "Standard copy completed successfully" "Green" "SUCCESS" "Copy-7ZipFiles"
            Write-Log -Message "Standard copy completed successfully" -Level "SUCCESS" -Component "Copy-7ZipFiles"
        } else {
            Write-ColoredOutput "Could not locate 7-Zip files in extracted content" "Yellow" "WARNING" "Copy-7ZipFiles"
            Write-ColoredOutput "Copying all extracted content..." "Yellow" "WARNING" "Copy-7ZipFiles"
            Write-Log -Message "7z.exe not found, copying all extracted content" -Level "WARNING" -Component "Copy-7ZipFiles"
            Copy-Item -Path "$SourcePath\*" -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
            Write-ColoredOutput "Copy completed - please verify installation manually" "Yellow" "WARNING" "Copy-7ZipFiles"
        }
        
        Write-FunctionLog -FunctionName "Copy-7ZipFiles" -Action "EXIT" -Details "Copy completed successfully"
    }
    catch [System.IO.PathTooLongException] {
        Write-ColoredOutput "Long path detected, using robocopy for file transfer..." "Yellow" "WARNING" "Copy-7ZipFiles"
        Write-Log -Message "PathTooLongException encountered, using robocopy" -Level "WARNING" -Component "Copy-7ZipFiles"
        
        $sourceForRobocopy = $actualSource -or $SourcePath
        $robocopyResult = robocopy "$sourceForRobocopy" "$DestinationPath" /E /R:1 /W:1 /NP /NDL /NJH /NJS
        
        # Check robocopy exit code (0-7 are success codes)
        if ($LASTEXITCODE -le 7) {
            Write-ColoredOutput "Robocopy transfer completed successfully" "Green" "SUCCESS" "Copy-7ZipFiles"
            Write-Log -Message "Robocopy transfer completed successfully (exit code: $LASTEXITCODE)" -Level "SUCCESS" -Component "Copy-7ZipFiles"
        } else {
            Write-ColoredOutput "Warning: Some files may not have been copied (robocopy exit code: $LASTEXITCODE)" "Yellow" "WARNING" "Copy-7ZipFiles"
            Write-Log -Message "Robocopy completed with warnings (exit code: $LASTEXITCODE)" -Level "WARNING" -Component "Copy-7ZipFiles"
        }
        Write-FunctionLog -FunctionName "Copy-7ZipFiles" -Action "EXIT" -Details "Robocopy method used"
    }
    catch {
        Write-ColoredOutput "Error during file copy: $($_.Exception.Message)" "Red" "ERROR" "Copy-7ZipFiles"
        Write-FunctionLog -FunctionName "Copy-7ZipFiles" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to install 7-Zip with configurable temp directory
function Install-7Zip {
    param(
        [string]$BaseInstallPath,
        [string]$TempDir
    )
    
    Write-FunctionLog -FunctionName "Install-7Zip" -Action "ENTER" -Details "BaseInstallPath: $BaseInstallPath, TempDir: $TempDir"
    
    Write-ColoredOutput "`n=== 7-Zip Installation ===" "Magenta" "INFO" "Install-7Zip"
    
    try {
        # Get latest version information
        $zipInfo = Get-Latest7ZipVersion
        $version = $zipInfo.Version
        $originalFileName = $zipInfo.FileName
        $downloadUrl = $zipInfo.DownloadUrl
        $source = $zipInfo.Source
        
        Write-ColoredOutput "Installing 7-Zip v$version" "Cyan" "INFO" "Install-7Zip"
        Write-ColoredOutput "Source: $source" "Cyan" "INFO" "Install-7Zip"
        Write-ColoredOutput "File: $originalFileName" "Cyan" "INFO" "Install-7Zip"
        
        # Configure paths
        $zipInstallPath = Join-Path $BaseInstallPath "PCTOOLS\7zip"
        $zipInstallerPath = Join-Path $TempDir $originalFileName  # This will be cleaned by Download-File
        $zipExtractPath = Join-Path $TempDir "extract"
        
        Write-Log -Message "Installation paths configured - Install: $zipInstallPath, Installer: $zipInstallerPath, Extract: $zipExtractPath" -Level "INFO" -Component "Install-7Zip"
        
        # Create directories
        New-InstallDirectory $zipInstallPath
        New-InstallDirectory $TempDir
        New-InstallDirectory $zipExtractPath
        
        # Download (returns the actual clean path used)
        $actualInstallerPath = Download-File $downloadUrl $zipInstallerPath
        
        # Extract the installer
        $extractionSuccess = Extract-7ZipInstaller $actualInstallerPath $zipExtractPath
        
        if ($extractionSuccess) {
            # Copy files with long path handling
            Write-ColoredOutput "Installing to: $zipInstallPath" "Yellow" "INFO" "Install-7Zip"
            Copy-7ZipFiles $zipExtractPath $zipInstallPath
        } else {
            Write-ColoredOutput "Extraction was not fully successful. Checking for manual installation options..." "Yellow" "WARNING" "Install-7Zip"
            Write-Log -Message "Extraction was not fully successful, setting up manual installation option" -Level "WARNING" -Component "Install-7Zip"
            
            # If extraction failed, copy the installer to the install directory for manual use
            $manualInstaller = Join-Path $zipInstallPath "7zip-installer.exe"
            Copy-Item -Path $actualInstallerPath -Destination $manualInstaller -Force
            Write-ColoredOutput "Installer copied to: $manualInstaller" "Yellow" "WARNING" "Install-7Zip"
            Write-ColoredOutput "Please run this installer manually to complete the installation." "Yellow" "WARNING" "Install-7Zip"
        }
        
        # Verify essential files are present
        Write-Log -Message "Verifying installation - checking for essential files" -Level "INFO" -Component "Install-7Zip"
        $essentialFiles = @("7z.exe", "7za.exe")
        $toolsFound = @()
        foreach ($file in $essentialFiles) {
            $filePath = Join-Path $zipInstallPath $file
            if (Test-Path $filePath) {
                $toolsFound += $file
                Write-Log -Message "Essential file found: $file" -Level "SUCCESS" -Component "Install-7Zip"
            } else {
                Write-Log -Message "Essential file missing: $file" -Level "WARNING" -Component "Install-7Zip"
            }
        }
        
        if ($toolsFound.Count -eq 0) {
            Write-ColoredOutput "Warning: No 7-Zip executables found. Installation may need manual completion." "Yellow" "WARNING" "Install-7Zip"
            Write-Log -Message "No essential 7-Zip executables found" -Level "WARNING" -Component "Install-7Zip"
            
            # List what we actually found
            $actualFiles = Get-ChildItem -Path $zipInstallPath -Filter "*.exe" -ErrorAction SilentlyContinue
            if ($actualFiles.Count -gt 0) {
                Write-ColoredOutput "Found executable files:" "Yellow" "INFO" "Install-7Zip"
                foreach ($file in $actualFiles) {
                    Write-ColoredOutput "  $($file.Name)" "Yellow" "INFO" "Install-7Zip"
                    $toolsFound += $file.Name
                    Write-Log -Message "Found executable: $($file.Name)" -Level "INFO" -Component "Install-7Zip"
                }
            }
        } else {
            Write-ColoredOutput "Found 7-Zip tools: $($toolsFound -join ', ')" "Green" "SUCCESS" "Install-7Zip"
        }
        
        # Configure environment variables
        Write-ColoredOutput "Configuring environment variables..." "Yellow" "INFO" "Install-7Zip"
        Write-Log -Message "Configuring environment variables" -Level "INFO" -Component "Install-7Zip"
        
        # Add 7-Zip directory to system PATH
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($currentPath -notlike "*$zipInstallPath*") {
            $newPath = "$currentPath;$zipInstallPath"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
            Write-ColoredOutput "7-Zip added to system PATH: $zipInstallPath" "Green" "SUCCESS" "Install-7Zip"
            Write-Log -Message "7-Zip added to system PATH" -Level "SUCCESS" -Component "Install-7Zip"
        } else {
            Write-ColoredOutput "7-Zip already present in system PATH" "Yellow" "INFO" "Install-7Zip"
            Write-Log -Message "7-Zip already present in system PATH" -Level "INFO" -Component "Install-7Zip"
        }
        
        # Update PATH for current session
        if ($env:PATH -notlike "*$zipInstallPath*") {
            $env:PATH += ";$zipInstallPath"
            Write-Log -Message "Updated PATH for current session" -Level "INFO" -Component "Install-7Zip"
        }
        
        # Cleanup temporary files
        Write-ColoredOutput "Cleaning up temporary files..." "Yellow" "INFO" "Install-7Zip"
        Write-Log -Message "Starting cleanup of temporary files" -Level "INFO" -Component "Install-7Zip"
        try {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColoredOutput "Cleanup completed" "Green" "SUCCESS" "Install-7Zip"
            Write-Log -Message "Temporary files cleanup completed successfully" -Level "SUCCESS" -Component "Install-7Zip"
        }
        catch {
            Write-ColoredOutput "Warning: Some temporary files may remain in $TempDir" "Yellow" "WARNING" "Install-7Zip"
            Write-Log -Message "Cleanup warning: Some temporary files may remain - $($_.Exception.Message)" -Level "WARNING" -Component "Install-7Zip"
        }
        
        # Verify installation
        Write-ColoredOutput "Verifying installation..." "Yellow" "INFO" "Install-7Zip"
        Write-Log -Message "Starting installation verification" -Level "INFO" -Component "Install-7Zip"
        try {
            $verificationResults = @()
            
            foreach ($tool in $toolsFound) {
                $toolPath = Join-Path $zipInstallPath $tool
                try {
                    # For 7-Zip, we can just check if the file exists and get basic info
                    if (Test-Path $toolPath) {
                        $fileInfo = Get-Item $toolPath
                        $fileVersion = $fileInfo.VersionInfo.FileVersion
                        if ($fileVersion) {
                            $verificationResults += "$tool : v$fileVersion"
                            Write-Log -Message "Verification: $tool version $fileVersion" -Level "SUCCESS" -Component "Install-7Zip"
                        } else {
                            $verificationResults += "$tool : Available"
                            Write-Log -Message "Verification: $tool available (no version info)" -Level "SUCCESS" -Component "Install-7Zip"
                        }
                    }
                }
                catch {
                    $verificationResults += "$tool : Available (version check failed)"
                    Write-Log -Message "Verification: $tool available but version check failed - $($_.Exception.Message)" -Level "WARNING" -Component "Install-7Zip"
                }
            }
            
            if ($verificationResults.Count -gt 0) {
                Write-ColoredOutput "7-Zip installed successfully!" "Green" "SUCCESS" "Install-7Zip"
                foreach ($result in $verificationResults) {
                    Write-ColoredOutput "  $result" "Green" "SUCCESS" "Install-7Zip"
                }
                Write-ColoredOutput "Version: $version" "Green" "SUCCESS" "Install-7Zip"
                Write-ColoredOutput "Installation directory: $zipInstallPath" "Green" "SUCCESS" "Install-7Zip"
                Write-Log -Message "Installation completed successfully - Version: $version, Path: $zipInstallPath" -Level "SUCCESS" -Component "Install-7Zip"
            } else {
                Write-ColoredOutput "Installation completed but verification inconclusive." "Yellow" "WARNING" "Install-7Zip"
                Write-ColoredOutput "Check the installation directory manually: $zipInstallPath" "Yellow" "WARNING" "Install-7Zip"
                Write-Log -Message "Installation completed but verification inconclusive" -Level "WARNING" -Component "Install-7Zip"
            }
        }
        catch {
            Write-ColoredOutput "Installation completed but verification failed: $($_.Exception.Message)" "Yellow" "WARNING" "Install-7Zip"
            Write-ColoredOutput "7-Zip may still be functional. Try opening a new command prompt." "Yellow" "WARNING" "Install-7Zip"
            Write-Log -Message "Installation verification failed: $($_.Exception.Message)" -Level "WARNING" -Component "Install-7Zip"
        }
        
        Write-FunctionLog -FunctionName "Install-7Zip" -Action "EXIT" -Details "Installation process completed"
        
    }
    catch {
        Write-ColoredOutput "Error during 7-Zip installation: $($_.Exception.Message)" "Red" "ERROR" "Install-7Zip"
        Write-FunctionLog -FunctionName "Install-7Zip" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Determine paths based on parameters (Case 1, 2, 3, 4)
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
$LogFile = Join-Path $LogDirectory "win_install_7zip.log"

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
    $LogFile = Join-Path (Get-Location) "win_install_7zip.log"
}

# Initialize log file
try {
    # Create or clear the log file
    $logHeader = @"
================================================================================
GameShell65 - 7-Zip Installation Log
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
    Write-ColoredOutput "=== GameShell65 - 7-Zip Installer ===" "Magenta" "INFO" "MAIN"
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
        $null = Invoke-WebRequest -Uri "https://www.7-zip.org" -Method Head -UseBasicParsing -TimeoutSec 10
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
    
    # Install 7-Zip with custom temp directory
    Install-7Zip $resolvedInstallPath $tempDir
    
    Write-ColoredOutput "`n=== Installation completed successfully! ===" "Green" "SUCCESS" "MAIN"
    Write-ColoredOutput "IMPORTANT: Restart your session or open a new command window to use the new tools." "Yellow" "INFO" "MAIN"
    Write-ColoredOutput "You can verify the installation by running: 7z" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "Or check version with: 7z --help" "Cyan" "INFO" "MAIN"
    
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