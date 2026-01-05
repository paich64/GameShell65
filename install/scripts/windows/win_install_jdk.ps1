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
            $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\jdk"
            Write-ColoredOutput "Using installation-based temporary directory: $tempDir" "Cyan" "INFO" "Get-TempDirectory"
        }
        else {
            # User provided temp directory
            $tempDir = Join-Path $UserTempDir "GameShell65_temp_Install\jdk"
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
                    $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\jdk"
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

# Function to get the latest LTS version of OpenJDK
function Get-LatestOpenJDKVersion {
    Write-FunctionLog -FunctionName "Get-LatestOpenJDKVersion" -Action "ENTER"
    
    Write-ColoredOutput "Searching for the latest LTS version of OpenJDK..." "Yellow" "INFO" "Get-LatestOpenJDKVersion"
    
    try {
        # Call to the Adoptium API to get the latest LTS release info
        $apiUrl = "https://api.adoptium.net/v3/info/available_releases"
        Write-ColoredOutput "Querying Adoptium API: $apiUrl" "Cyan" "INFO" "Get-LatestOpenJDKVersion"
        Write-Log -Message "Attempting to fetch OpenJDK LTS versions from Adoptium API: $apiUrl" -Level "INFO" -Component "Get-LatestOpenJDKVersion"
        
        $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 30
        
        if (-not $response -or -not $response.available_lts_releases) {
            throw "Empty or invalid response from Adoptium API"
        }
        
        # Get the latest LTS version
        $latestLtsVersion = $response.available_lts_releases | Sort-Object -Descending | Select-Object -First 1
        
        if (-not $latestLtsVersion) {
            throw "No LTS version found in API response"
        }
        
        Write-ColoredOutput "Latest LTS version found: $latestLtsVersion" "Green" "SUCCESS" "Get-LatestOpenJDKVersion"
        Write-Log -Message "Latest LTS version identified: $latestLtsVersion" -Level "SUCCESS" -Component "Get-LatestOpenJDKVersion"
        
        # Now get the specific release information for this version
        $releaseApiUrl = "https://api.adoptium.net/v3/assets/latest/$latestLtsVersion/hotspot"
        Write-ColoredOutput "Getting release details from: $releaseApiUrl" "Cyan" "INFO" "Get-LatestOpenJDKVersion"
        Write-Log -Message "Fetching release details from: $releaseApiUrl" -Level "INFO" -Component "Get-LatestOpenJDKVersion"
        
        $releaseResponse = Invoke-RestMethod -Uri $releaseApiUrl -UseBasicParsing -TimeoutSec 30
        
        if (-not $releaseResponse -or $releaseResponse.Count -eq 0) {
            throw "No release information found for version $latestLtsVersion"
        }
        
        Write-Log -Message "Release information retrieved successfully, found $($releaseResponse.Count) assets" -Level "SUCCESS" -Component "Get-LatestOpenJDKVersion"
        
        # Find Windows x64 JDK package
        Write-Log -Message "Searching for Windows x64 JDK ZIP package" -Level "INFO" -Component "Get-LatestOpenJDKVersion"
        $windowsPackage = $releaseResponse | Where-Object {
            $_.binary.os -eq "windows" -and 
            $_.binary.architecture -eq "x64" -and 
            $_.binary.image_type -eq "jdk" -and
            $_.binary.package.name -like "*.zip"
        } | Select-Object -First 1
        
        if (-not $windowsPackage) {
            throw "No Windows x64 JDK ZIP package found for version $latestLtsVersion"
        }
        
        $downloadUrl = $windowsPackage.binary.package.link
        $version = $windowsPackage.version_data.semver
        $versionName = $windowsPackage.release_name
        $packageSize = $windowsPackage.binary.package.size
        
        Write-ColoredOutput "Found OpenJDK package: $versionName" "Green" "SUCCESS" "Get-LatestOpenJDKVersion"
        Write-ColoredOutput "Download URL confirmed: $downloadUrl" "Green" "SUCCESS" "Get-LatestOpenJDKVersion"
        
        Write-Log -Message "Windows x64 JDK package found - Name: $versionName, Size: $([math]::Round($packageSize/1MB, 2)) MB" -Level "SUCCESS" -Component "Get-LatestOpenJDKVersion"
        Write-Log -Message "Download URL: $downloadUrl" -Level "SUCCESS" -Component "Get-LatestOpenJDKVersion"
        
        $result = @{
            Version = $latestLtsVersion
            FullVersion = $version
            ReleaseName = $versionName
            DownloadUrl = $downloadUrl
            PackageSize = $packageSize
        }
        
        Write-FunctionLog -FunctionName "Get-LatestOpenJDKVersion" -Action "EXIT" -Details "Success: $latestLtsVersion"
        return $result
    }
    catch {
        Write-ColoredOutput "ERROR: Unable to retrieve OpenJDK version" "Red" "ERROR" "Get-LatestOpenJDKVersion"
        Write-ColoredOutput "Details: $($_.Exception.Message)" "Red" "ERROR" "Get-LatestOpenJDKVersion"
        Write-ColoredOutput "Check your internet connection and try again" "Red" "ERROR" "Get-LatestOpenJDKVersion"
        Write-Log -Message "Failed to retrieve OpenJDK version: $($_.Exception.Message)" -Level "ERROR" -Component "Get-LatestOpenJDKVersion"
        Write-FunctionLog -FunctionName "Get-LatestOpenJDKVersion" -Action "ERROR" -Details $_.Exception.Message
        throw "Failed to retrieve OpenJDK version: $($_.Exception.Message)"
    }
}

# Function to safely copy files handling long paths
function Copy-JDKFiles {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )
    
    Write-FunctionLog -FunctionName "Copy-JDKFiles" -Action "ENTER" -Details "Source: $SourcePath, Destination: $DestinationPath"
    
    Write-ColoredOutput "Copying OpenJDK files from: $SourcePath" "Yellow" "INFO" "Copy-JDKFiles"
    Write-ColoredOutput "To: $DestinationPath" "Yellow" "INFO" "Copy-JDKFiles"
    
    try {
        # Try standard copy first
        Write-Log -Message "Attempting standard copy method" -Level "INFO" -Component "Copy-JDKFiles"
        Copy-Item -Path "$SourcePath\*" -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
        Write-ColoredOutput "Standard copy completed successfully" "Green" "SUCCESS" "Copy-JDKFiles"
        Write-Log -Message "Standard copy completed successfully" -Level "SUCCESS" -Component "Copy-JDKFiles"
        Write-FunctionLog -FunctionName "Copy-JDKFiles" -Action "EXIT" -Details "Standard copy success"
    }
    catch [System.IO.PathTooLongException] {
        Write-ColoredOutput "Long path detected, using robocopy for file transfer..." "Yellow" "WARNING" "Copy-JDKFiles"
        Write-Log -Message "PathTooLongException encountered, using robocopy" -Level "WARNING" -Component "Copy-JDKFiles"
        
        # Use robocopy for long path support
        $robocopyResult = robocopy "$SourcePath" "$DestinationPath" /E /R:1 /W:1 /NP /NDL /NJH /NJS
        
        # Check robocopy exit code (0-7 are success codes)
        if ($LASTEXITCODE -le 7) {
            Write-ColoredOutput "Robocopy transfer completed successfully" "Green" "SUCCESS" "Copy-JDKFiles"
            Write-Log -Message "Robocopy transfer completed successfully (exit code: $LASTEXITCODE)" -Level "SUCCESS" -Component "Copy-JDKFiles"
        } else {
            Write-ColoredOutput "Warning: Some files may not have been copied (robocopy exit code: $LASTEXITCODE)" "Yellow" "WARNING" "Copy-JDKFiles"
            Write-Log -Message "Robocopy completed with warnings (exit code: $LASTEXITCODE)" -Level "WARNING" -Component "Copy-JDKFiles"
        }
        Write-FunctionLog -FunctionName "Copy-JDKFiles" -Action "EXIT" -Details "Robocopy method used"
    }
    catch {
        Write-ColoredOutput "Error during file copy: $($_.Exception.Message)" "Red" "ERROR" "Copy-JDKFiles"
        Write-Log -Message "File copy error: $($_.Exception.Message)" -Level "ERROR" -Component "Copy-JDKFiles"
        Write-FunctionLog -FunctionName "Copy-JDKFiles" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to install OpenJDK with configurable temp directory
function Install-OpenJDK {
    param(
        [string]$BaseInstallPath,
        [string]$TempDir
    )
    
    Write-FunctionLog -FunctionName "Install-OpenJDK" -Action "ENTER" -Details "BaseInstallPath: $BaseInstallPath, TempDir: $TempDir"
    
    Write-ColoredOutput "`n=== OpenJDK Installation ===" "Magenta" "INFO" "Install-OpenJDK"
    
    try {
        # Get latest version information
        $jdkInfo = Get-LatestOpenJDKVersion
        $jdkVersion = $jdkInfo.Version
        $fullVersion = $jdkInfo.FullVersion
        $releaseName = $jdkInfo.ReleaseName
        $downloadUrl = $jdkInfo.DownloadUrl
        
        Write-ColoredOutput "Installing OpenJDK $jdkVersion ($releaseName)" "Cyan" "INFO" "Install-OpenJDK"
        
        # Configure paths
        $jdkInstallPath = Join-Path $BaseInstallPath "PCTOOLS\jdk"
        $jdkZipPath = Join-Path $TempDir "openjdk.zip"
        $jdkExtractPath = Join-Path $TempDir "extract"
        
        Write-Log -Message "Installation paths configured - Install: $jdkInstallPath, Archive: $jdkZipPath, Extract: $jdkExtractPath" -Level "INFO" -Component "Install-OpenJDK"
        
        # Create directories
        New-InstallDirectory $jdkInstallPath
        New-InstallDirectory $TempDir
        New-InstallDirectory $jdkExtractPath
        
        # Download
        Download-File $downloadUrl $jdkZipPath
        
        # Extract with error handling for long paths
        Write-ColoredOutput "Extracting OpenJDK..." "Yellow" "INFO" "Install-OpenJDK"
        Write-Log -Message "Starting OpenJDK extraction" -Level "INFO" -Component "Install-OpenJDK"
        try {
            # Try standard extraction first
            Write-Log -Message "Attempting standard extraction method" -Level "INFO" -Component "Install-OpenJDK"
            Expand-Archive -Path $jdkZipPath -DestinationPath $jdkExtractPath -Force -ErrorAction Stop
            Write-ColoredOutput "Standard extraction completed" "Green" "SUCCESS" "Install-OpenJDK"
            Write-Log -Message "Standard extraction completed successfully" -Level "SUCCESS" -Component "Install-OpenJDK"
        }
        catch [System.IO.PathTooLongException] {
            Write-ColoredOutput "Long path detected during extraction, using alternative method..." "Yellow" "WARNING" "Install-OpenJDK"
            Write-Log -Message "PathTooLongException during extraction, using alternative method" -Level "WARNING" -Component "Install-OpenJDK"
            
            # Try with even shorter path - create a fallback temp directory
            $shorterExtractPath = Join-Path ([System.IO.Path]::GetTempPath()) "J"
            Remove-Item -Path $jdkExtractPath -Recurse -Force -ErrorAction SilentlyContinue
            New-InstallDirectory $shorterExtractPath
            
            Write-Log -Message "Using shorter extraction path: $shorterExtractPath" -Level "INFO" -Component "Install-OpenJDK"
            
            try {
                Expand-Archive -Path $jdkZipPath -DestinationPath $shorterExtractPath -Force -ErrorAction Stop
                $jdkExtractPath = $shorterExtractPath
                Write-ColoredOutput "Alternative extraction completed to: $shorterExtractPath" "Green" "SUCCESS" "Install-OpenJDK"
                Write-Log -Message "Alternative extraction completed successfully to: $shorterExtractPath" -Level "SUCCESS" -Component "Install-OpenJDK"
            }
            catch {
                $errorMsg = "Unable to extract OpenJDK archive due to long path limitations. Consider using a shorter temporary directory path or enabling Windows long path support."
                Write-Log -Message $errorMsg -Level "ERROR" -Component "Install-OpenJDK"
                throw $errorMsg
            }
        }
        catch {
            Write-ColoredOutput "Extraction error: $($_.Exception.Message)" "Red" "ERROR" "Install-OpenJDK"
            Write-Log -Message "Extraction error: $($_.Exception.Message)" -Level "ERROR" -Component "Install-OpenJDK"
            throw
        }
        
        # Find extracted folder
        Write-Log -Message "Searching for extracted OpenJDK folder" -Level "INFO" -Component "Install-OpenJDK"
        $extractedFolders = Get-ChildItem -Path $jdkExtractPath -Directory -ErrorAction SilentlyContinue
        if ($extractedFolders.Count -eq 0) {
            $errorMsg = "No folder found after ZIP extraction. Archive may be corrupted."
            Write-Log -Message $errorMsg -Level "ERROR" -Component "Install-OpenJDK"
            throw $errorMsg
        }
        
        $sourceJdkPath = $extractedFolders[0].FullName
        Write-ColoredOutput "Found extracted OpenJDK folder: $($extractedFolders[0].Name)" "Green" "SUCCESS" "Install-OpenJDK"
        Write-Log -Message "Found extracted OpenJDK folder: $($extractedFolders[0].Name)" -Level "SUCCESS" -Component "Install-OpenJDK"
        
        # Copy files with long path handling
        Write-ColoredOutput "Installing to: $jdkInstallPath" "Yellow" "INFO" "Install-OpenJDK"
        Copy-JDKFiles $sourceJdkPath $jdkInstallPath
        
        # Verify essential files are present
        Write-Log -Message "Verifying installation - checking for essential files" -Level "INFO" -Component "Install-OpenJDK"
        $essentialFiles = @("bin\java.exe", "bin\javac.exe")
        foreach ($file in $essentialFiles) {
            $filePath = Join-Path $jdkInstallPath $file
            Write-Log -Message "Checking for essential file: $filePath" -Level "DEBUG" -Component "Install-OpenJDK"
            if (-not (Test-Path $filePath)) {
                $errorMsg = "Essential file missing: $file. Installation may be incomplete."
                Write-Log -Message $errorMsg -Level "ERROR" -Component "Install-OpenJDK"
                throw $errorMsg
            } else {
                Write-Log -Message "Essential file found: $file" -Level "SUCCESS" -Component "Install-OpenJDK"
            }
        }
        Write-ColoredOutput "Essential files verified" "Green" "SUCCESS" "Install-OpenJDK"
        
        # Configure environment variables
        Write-ColoredOutput "Configuring environment variables..." "Yellow" "INFO" "Install-OpenJDK"
        Write-Log -Message "Configuring environment variables" -Level "INFO" -Component "Install-OpenJDK"
        
        # Set JAVA_HOME
        $javaHome = $jdkInstallPath
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $javaHome, "Machine")
        Write-ColoredOutput "JAVA_HOME set to: $javaHome" "Green" "SUCCESS" "Install-OpenJDK"
        Write-Log -Message "JAVA_HOME set to: $javaHome" -Level "SUCCESS" -Component "Install-OpenJDK"
        
        # Update JAVA_HOME for current session
        $env:JAVA_HOME = $javaHome
        Write-Log -Message "JAVA_HOME updated for current session" -Level "INFO" -Component "Install-OpenJDK"
        
        # Add Java bin directory to system PATH
        $javaBinPath = Join-Path $jdkInstallPath "bin"
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($currentPath -notlike "*$javaBinPath*") {
            $newPath = "$currentPath;$javaBinPath"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
            Write-ColoredOutput "Java bin directory added to system PATH: $javaBinPath" "Green" "SUCCESS" "Install-OpenJDK"
            Write-Log -Message "Java bin directory added to system PATH: $javaBinPath" -Level "SUCCESS" -Component "Install-OpenJDK"
        } else {
            Write-ColoredOutput "Java bin directory already present in system PATH" "Yellow" "INFO" "Install-OpenJDK"
            Write-Log -Message "Java bin directory already present in system PATH" -Level "INFO" -Component "Install-OpenJDK"
        }
        
        # Update PATH for current session (with verification to avoid duplicates)
        if ($env:PATH -notlike "*$javaBinPath*") {
            $env:PATH += ";$javaBinPath"
            Write-Log -Message "PATH updated for current session" -Level "INFO" -Component "Install-OpenJDK"
        }
        
        # Cleanup temporary files
        Write-ColoredOutput "Cleaning up temporary files..." "Yellow" "INFO" "Install-OpenJDK"
        Write-Log -Message "Starting cleanup of temporary files" -Level "INFO" -Component "Install-OpenJDK"
        try {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColoredOutput "Cleanup completed" "Green" "SUCCESS" "Install-OpenJDK"
            Write-Log -Message "Temporary files cleanup completed successfully" -Level "SUCCESS" -Component "Install-OpenJDK"
        }
        catch {
            Write-ColoredOutput "Warning: Some temporary files may remain in $TempDir" "Yellow" "WARNING" "Install-OpenJDK"
            Write-Log -Message "Cleanup warning: Some temporary files may remain - $($_.Exception.Message)" -Level "WARNING" -Component "Install-OpenJDK"
        }
        
        # Verify installation
        Write-ColoredOutput "Verifying installation..." "Yellow" "INFO" "Install-OpenJDK"
        Write-Log -Message "Starting installation verification" -Level "INFO" -Component "Install-OpenJDK"
        
        # Save current ErrorActionPreference and temporarily set to Continue
        # This is necessary because java/javac write their version output to STDERR by design
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        
        try {
            # Capture java version (writes to STDERR by design)
            $javaVersionOutput = & "$javaBinPath\java.exe" -version 2>&1
            $javaExitCode = $LASTEXITCODE
            
            # Capture javac version (writes to STDERR by design)
            $javacVersionOutput = & "$javaBinPath\javac.exe" -version 2>&1
            $javacExitCode = $LASTEXITCODE
            
            # Check if commands succeeded based on exit codes
            if ($javaExitCode -eq 0 -and $javacExitCode -eq 0) {
                Write-ColoredOutput "OpenJDK installed successfully!" "Green" "SUCCESS" "Install-OpenJDK"
                Write-ColoredOutput "Java version output:" "Green" "SUCCESS" "Install-OpenJDK"
                
                # Display java version output (handle both single string and array)
                if ($javaVersionOutput -is [array]) {
                    $javaVersionOutput | ForEach-Object { Write-ColoredOutput "  $_" "Green" "SUCCESS" "Install-OpenJDK" }
                } else {
                    Write-ColoredOutput "  $javaVersionOutput" "Green" "SUCCESS" "Install-OpenJDK"
                }
                
                Write-ColoredOutput "Javac version: $javacVersionOutput" "Green" "SUCCESS" "Install-OpenJDK"
                Write-ColoredOutput "Release: $releaseName" "Green" "SUCCESS" "Install-OpenJDK"
                Write-ColoredOutput "Installation directory: $jdkInstallPath" "Green" "SUCCESS" "Install-OpenJDK"
                Write-ColoredOutput "JAVA_HOME: $javaHome" "Green" "SUCCESS" "Install-OpenJDK"
                
                Write-Log -Message "Installation verification successful - Java: $($javaVersionOutput -join ' '), Javac: $javacVersionOutput" -Level "SUCCESS" -Component "Install-OpenJDK"
                Write-Log -Message "OpenJDK installed successfully - Path: $jdkInstallPath, JAVA_HOME: $javaHome" -Level "SUCCESS" -Component "Install-OpenJDK"
            } else {
                Write-ColoredOutput "Installation completed but verification failed." "Yellow" "WARNING" "Install-OpenJDK"
                Write-ColoredOutput "Java exit code: $javaExitCode, Javac exit code: $javacExitCode" "Yellow" "WARNING" "Install-OpenJDK"
                Write-Log -Message "Installation verification failed - Java exit code: $javaExitCode, Javac exit code: $javacExitCode" -Level "WARNING" -Component "Install-OpenJDK"
            }
        }
        catch {
            Write-ColoredOutput "Installation completed but verification encountered an error: $($_.Exception.Message)" "Yellow" "WARNING" "Install-OpenJDK"
            Write-ColoredOutput "OpenJDK may still be functional. Try opening a new command prompt." "Yellow" "WARNING" "Install-OpenJDK"
            Write-Log -Message "Installation verification error: $($_.Exception.Message)" -Level "WARNING" -Component "Install-OpenJDK"
        }
        finally {
            # Restore original ErrorActionPreference
            $ErrorActionPreference = $previousErrorActionPreference
        }
        
        Write-FunctionLog -FunctionName "Install-OpenJDK" -Action "EXIT" -Details "Installation process completed"
        
    }
    catch {
        Write-ColoredOutput "Error during OpenJDK installation: $($_.Exception.Message)" "Red" "ERROR" "Install-OpenJDK"
        Write-Log -Message "OpenJDK installation error: $($_.Exception.Message)" -Level "ERROR" -Component "Install-OpenJDK"
        Write-FunctionLog -FunctionName "Install-OpenJDK" -Action "ERROR" -Details $_.Exception.Message
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
$LogFile = Join-Path $LogDirectory "win_install_jdk.log"

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
    $LogFile = Join-Path (Get-Location) "win_install_jdk.log"
}

# Initialize log file
try {
    # Create or clear the log file
    $logHeader = @"
================================================================================
GameShell65 - OpenJDK Installation Log
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
    Write-ColoredOutput "=== GameShell65 - OpenJDK Installer ===" "Magenta" "INFO" "MAIN"
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
        $null = Invoke-WebRequest -Uri "https://api.adoptium.net" -Method Head -UseBasicParsing -TimeoutSec 10
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
    
    # Install OpenJDK with custom temp directory
    Install-OpenJDK $resolvedInstallPath $tempDir
    
    Write-ColoredOutput "`n=== Installation completed successfully! ===" "Green" "SUCCESS" "MAIN"
    Write-ColoredOutput "IMPORTANT: Restart your session or open a new command window to use the new tools." "Yellow" "INFO" "MAIN"
    Write-ColoredOutput "You can verify the installation by running: java -version" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "You can also check: javac -version" "Cyan" "INFO" "MAIN"
    
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