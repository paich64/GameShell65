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
function Get-RootDirectory {
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
        $rootPath = Split-Path $installDir -Parent  # Arborescence_Principale
        
        return $rootPath
    }
    catch {
        throw "Error detecting root directory: $($_.Exception.Message)"
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
            $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\cygwindll"
            Write-ColoredOutput "Using installation-based temporary directory: $tempDir" "Cyan" "INFO" "Get-TempDirectory"
        }
        else {
            # User provided temp directory
            $tempDir = Join-Path $UserTempDir "GameShell65_temp_Install\cygwindll"
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
                    $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\cygwindll"
                }
            }
        }
        
        # Ensure the temp directory path is not too long to avoid path issues
        if ($tempDir.Length -gt 100) {
            Write-ColoredOutput "Warning: Temporary directory path is long ($($tempDir.Length) chars). This may cause issues with some files." "Yellow" "WARNING" "Get-TempDirectory"
            Write-ColoredOutput "Consider using a shorter path" "Yellow" "WARNING" "Get-TempDirectory"
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

# Function to get official Cygwin mirrors
function Get-CygwinMirrors {
    Write-FunctionLog -FunctionName "Get-CygwinMirrors" -Action "ENTER"
    
    try {
        # Official Cygwin mirrors (prioritized by reliability)
        $mirrors = @(
            "https://cygwin.mirror.constant.com/x86_64/release/cygwin/",
            "https://mirror.cs.vt.edu/pub/cygwin/cygwin/x86_64/release/cygwin/",
            "https://download.nus.edu.sg/mirror/cygwin/x86_64/release/cygwin/",
            "https://mirrors.kernel.org/sourceware/cygwin/x86_64/release/cygwin/",
            "https://cygwin.mirror.gtcomm.net/x86_64/release/cygwin/",
            "https://ftp.acc.umu.se/mirror/cygwin/x86_64/release/cygwin/"
        )
        
        Write-Log -Message "Retrieved $($mirrors.Count) official Cygwin mirrors" -Level "SUCCESS" -Component "Get-CygwinMirrors"
        Write-FunctionLog -FunctionName "Get-CygwinMirrors" -Action "EXIT" -Details "$($mirrors.Count) mirrors"
        return $mirrors
    }
    catch {
        Write-Log -Message "Error getting Cygwin mirrors: $($_.Exception.Message)" -Level "ERROR" -Component "Get-CygwinMirrors"
        Write-FunctionLog -FunctionName "Get-CygwinMirrors" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to discover latest Cygwin version from mirrors
function Get-LatestCygwinVersion {
    Write-FunctionLog -FunctionName "Get-LatestCygwinVersion" -Action "ENTER"
    
    Write-ColoredOutput "Discovering latest Cygwin version from mirrors..." "Yellow" "INFO" "Get-LatestCygwinVersion"
    
    try {
        $mirrors = Get-CygwinMirrors
        $latestVersion = $null
        $packageUrl = $null
        $workingMirror = $null
        
        foreach ($mirror in $mirrors) {
            try {
                Write-ColoredOutput "Testing mirror: $mirror" "Gray" "DEBUG" "Get-LatestCygwinVersion"
                Write-Log -Message "Testing mirror: $mirror" -Level "DEBUG" -Component "Get-LatestCygwinVersion"
                
                # Try to get the directory listing
                $response = Invoke-WebRequest -Uri $mirror -UseBasicParsing -TimeoutSec 15
                
                if ($response.StatusCode -eq 200) {
                    # Look for ALL cygwin patterns in the content
                    $content = $response.Content
                    
                    # Extended pattern to capture ALL possible versions
                    # Supported formats:
                    # - cygwin-3.6.4-1-x86_64.tar.xz (stable version)
                    # - cygwin-3.7.0-0.287.g3a03874f73db-x86_64.tar.xz (dev version)
                    $pattern = 'cygwin-(\d+\.\d+\.\d+(?:-\d+)?(?:\.\d+\.g[a-f0-9]+)?)-x86_64\.tar\.xz'
                    $matches = [regex]::Matches($content, $pattern)
                    
                    if ($matches.Count -gt 0) {
                        # Get all versions for comparison
                        $versions = @()
                        foreach ($match in $matches) {
                            $fullVersion = $match.Groups[1].Value
                            $fileName = "cygwin-$fullVersion-x86_64.tar.xz"
                            
                            # Parse different version formats
                            $sortValue = 0
                            
                            # Stable format: 3.6.4-1
                            if ($fullVersion -match '^(\d+)\.(\d+)\.(\d+)-(\d+)$') {
                                $major = [int]$matches[1]
                                $minor = [int]$matches[2] 
                                $patch = [int]$matches[3]
                                $build = [int]$matches[4]
                                
                                # Stable version: higher weight if same major version
                                $sortValue = ($major * 1000000000) + ($minor * 1000000) + ($patch * 1000) + ($build * 10) + 5
                            }
                            # Dev format: 3.7.0-0.287.g3a03874f73db  
                            elseif ($fullVersion -match '^(\d+)\.(\d+)\.(\d+)-(\d+)\.(\d+)\.g([a-f0-9]+)$') {
                                $major = [int]$matches[1]
                                $minor = [int]$matches[2]
                                $patch = [int]$matches[3]
                                $devBuild = [int]$matches[4]  # usually 0
                                $devNumber = [int]$matches[5] # 287, 286, etc.
                                
                                # Dev version: includes dev number
                                $sortValue = ($major * 1000000000) + ($minor * 1000000) + ($patch * 1000) + ($devBuild * 10) + $devNumber
                            }
                            
                            if ($sortValue -gt 0) {
                                $versions += @{
                                    FullVersion = $fullVersion
                                    FileName = $fileName
                                    SortValue = $sortValue
                                    IsStable = ($fullVersion -match '^\d+\.\d+\.\d+-\d+$')
                                }
                                
                                Write-Log -Message "Found version: $fullVersion (SortValue: $sortValue)" -Level "DEBUG" -Component "Get-LatestCygwinVersion"
                            }
                        }
                        
                        if ($versions.Count -gt 0) {
                            # Sort by descending value and take the most recent
                            $latest = $versions | Sort-Object SortValue -Descending | Select-Object -First 1
                            $latestVersion = $latest.FullVersion
                            $packageUrl = $mirror + $latest.FileName
                            $workingMirror = $mirror
                            
                            $versionType = if ($latest.IsStable) { "stable" } else { "development" }
                            Write-ColoredOutput "Found latest version: $latestVersion ($versionType)" "Green" "SUCCESS" "Get-LatestCygwinVersion"
                            Write-ColoredOutput "Package URL: $packageUrl" "Green" "SUCCESS" "Get-LatestCygwinVersion"
                            Write-Log -Message "Latest version found: $latestVersion ($versionType) from mirror: $workingMirror" -Level "SUCCESS" -Component "Get-LatestCygwinVersion"
                            break
                        }
                    }
                }
            }
            catch {
                Write-ColoredOutput "Mirror failed: $mirror - $($_.Exception.Message)" "Yellow" "WARNING" "Get-LatestCygwinVersion"
                Write-Log -Message "Mirror failed: $mirror - Error: $($_.Exception.Message)" -Level "WARNING" -Component "Get-LatestCygwinVersion"
                continue
            }
        }
        
        if (-not $latestVersion) {
            throw "No Cygwin package found on any mirror"
        }
        
        $result = @{
            Version = $latestVersion
            PackageUrl = $packageUrl
            Mirror = $workingMirror
            FileName = "cygwin-$latestVersion-x86_64.tar.xz"
        }
        
        Write-FunctionLog -FunctionName "Get-LatestCygwinVersion" -Action "EXIT" -Details "Version: $latestVersion"
        return $result
    }
    catch {
        Write-ColoredOutput "ERROR: Unable to retrieve Cygwin version information" "Red" "ERROR" "Get-LatestCygwinVersion"
        Write-ColoredOutput "Details: $($_.Exception.Message)" "Red" "ERROR" "Get-LatestCygwinVersion"
        Write-FunctionLog -FunctionName "Get-LatestCygwinVersion" -Action "ERROR" -Details $_.Exception.Message
        throw "Failed to retrieve Cygwin version: $($_.Exception.Message)"
    }
}

# Function to extract tar.xz file
function Extract-TarXzFile {
    param(
        [string]$ArchivePath,
        [string]$ExtractPath
    )
    
    Write-FunctionLog -FunctionName "Extract-TarXzFile" -Action "ENTER" -Details "Archive: $ArchivePath, ExtractPath: $ExtractPath"
    
    Write-ColoredOutput "Extracting tar.xz archive..." "Yellow" "INFO" "Extract-TarXzFile"
    
    try {
        # Method 1: Try Windows built-in tar (Windows 10/11)
        Write-ColoredOutput "Attempting extraction with Windows built-in tar..." "Cyan" "INFO" "Extract-TarXzFile"
        Write-Log -Message "Attempting Windows built-in tar extraction" -Level "INFO" -Component "Extract-TarXzFile"
        
        try {
            # Check if tar exists
            $tarExists = Get-Command "tar.exe" -ErrorAction SilentlyContinue
            if ($tarExists) {
                $tarResult = & tar.exe -xf "$ArchivePath" -C "$ExtractPath" 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-ColoredOutput "Windows tar extraction completed successfully" "Green" "SUCCESS" "Extract-TarXzFile"
                    Write-Log -Message "Windows tar extraction successful" -Level "SUCCESS" -Component "Extract-TarXzFile"
                    Write-FunctionLog -FunctionName "Extract-TarXzFile" -Action "EXIT" -Details "Windows tar success"
                    return $true
                }
            }
        }
        catch {
            Write-ColoredOutput "Windows tar failed: $($_.Exception.Message)" "Yellow" "WARNING" "Extract-TarXzFile"
            Write-Log -Message "Windows tar failed: $($_.Exception.Message)" -Level "WARNING" -Component "Extract-TarXzFile"
        }
        
        # Method 2: Try PowerShell with System.IO.Compression (limited support)
        Write-ColoredOutput "Attempting PowerShell extraction..." "Cyan" "INFO" "Extract-TarXzFile"
        Write-Log -Message "Attempting PowerShell extraction" -Level "INFO" -Component "Extract-TarXzFile"
        
        try {
            # This might work if it's actually a zip-compatible format
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $ExtractPath)
            Write-ColoredOutput "PowerShell extraction completed" "Green" "SUCCESS" "Extract-TarXzFile"
            Write-Log -Message "PowerShell extraction successful" -Level "SUCCESS" -Component "Extract-TarXzFile"
            Write-FunctionLog -FunctionName "Extract-TarXzFile" -Action "EXIT" -Details "PowerShell success"
            return $true
        }
        catch {
            Write-ColoredOutput "PowerShell extraction failed (expected for .xz files)" "Yellow" "WARNING" "Extract-TarXzFile"
            Write-Log -Message "PowerShell extraction failed: $($_.Exception.Message)" -Level "WARNING" -Component "Extract-TarXzFile"
        }
        
        # Method 3: Look for 7-Zip in common locations
        Write-ColoredOutput "Searching for 7-Zip for extraction..." "Cyan" "INFO" "Extract-TarXzFile"
        Write-Log -Message "Searching for 7-Zip installation" -Level "INFO" -Component "Extract-TarXzFile"
        
        $rootDir = Get-RootDirectory
        $sevenZipPaths = @(
            "${env:ProgramFiles}\7-Zip\7z.exe",
            "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
            "$rootDir\PCTOOLS\7zip\7z.exe",
            "7z.exe"  # In PATH
        )
        
        $sevenZipExe = $null
        foreach ($path in $sevenZipPaths) {
            if (Test-Path $path -ErrorAction SilentlyContinue) {
                $sevenZipExe = $path
                Write-ColoredOutput "Found 7-Zip at: $path" "Green" "SUCCESS" "Extract-TarXzFile"
                break
            }
        }
        
        if ($sevenZipExe) {
            try {
                # Extract in two steps: .xz -> .tar, then .tar -> files
                Write-ColoredOutput "Extracting with 7-Zip (step 1: .xz -> .tar)..." "Cyan" "INFO" "Extract-TarXzFile"
                $tarFile = [System.IO.Path]::ChangeExtension($ArchivePath, ".tar")
                
                $extract1Result = & "$sevenZipExe" x "$ArchivePath" "-o$ExtractPath" -y 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    $extractedTar = Join-Path $ExtractPath (Split-Path $tarFile -Leaf)
                    if (Test-Path $extractedTar) {
                        Write-ColoredOutput "Extracting with 7-Zip (step 2: .tar -> files)..." "Cyan" "INFO" "Extract-TarXzFile"
                        $extract2Result = & "$sevenZipExe" x "$extractedTar" "-o$ExtractPath" -y 2>&1
                        
                        if ($LASTEXITCODE -eq 0) {
                            Write-ColoredOutput "7-Zip extraction completed successfully" "Green" "SUCCESS" "Extract-TarXzFile"
                            Write-Log -Message "7-Zip extraction successful" -Level "SUCCESS" -Component "Extract-TarXzFile"
                            
                            # Clean up intermediate tar file
                            Remove-Item -Path $extractedTar -Force -ErrorAction SilentlyContinue
                            
                            Write-FunctionLog -FunctionName "Extract-TarXzFile" -Action "EXIT" -Details "7-Zip success"
                            return $true
                        }
                    }
                }
            }
            catch {
                Write-ColoredOutput "7-Zip extraction failed: $($_.Exception.Message)" "Yellow" "WARNING" "Extract-TarXzFile"
                Write-Log -Message "7-Zip extraction failed: $($_.Exception.Message)" -Level "WARNING" -Component "Extract-TarXzFile"
            }
        }
        
        # Method 4: Manual guidance
        Write-ColoredOutput "All extraction methods failed." "Red" "ERROR" "Extract-TarXzFile"
        Write-ColoredOutput "Archive location: $ArchivePath" "Yellow" "WARNING" "Extract-TarXzFile"
        Write-ColoredOutput "Please extract manually to: $ExtractPath" "Yellow" "WARNING" "Extract-TarXzFile"
        Write-ColoredOutput "You can use 7-Zip, WinRAR, or similar tools." "Yellow" "WARNING" "Extract-TarXzFile"
        
        Write-Log -Message "All extraction methods failed - manual extraction required" -Level "ERROR" -Component "Extract-TarXzFile"
        Write-FunctionLog -FunctionName "Extract-TarXzFile" -Action "EXIT" -Details "Manual extraction required"
        return $false
    }
    catch {
        Write-ColoredOutput "Extraction error: $($_.Exception.Message)" "Red" "ERROR" "Extract-TarXzFile"
        Write-FunctionLog -FunctionName "Extract-TarXzFile" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to find and copy cygwin1.dll
function Copy-CygwinDll {
    param(
        [string]$ExtractedPath,
        [string]$DestinationPath
    )
    
    Write-FunctionLog -FunctionName "Copy-CygwinDll" -Action "ENTER" -Details "Source: $ExtractedPath, Destination: $DestinationPath"
    
    Write-ColoredOutput "Searching for cygwin1.dll in extracted files..." "Yellow" "INFO" "Copy-CygwinDll"
    
    try {
        # Search for cygwin1.dll recursively
        $cygwinDllFiles = Get-ChildItem -Path $ExtractedPath -Name "cygwin1.dll" -Recurse -ErrorAction SilentlyContinue
        
        if ($cygwinDllFiles.Count -eq 0) {
            throw "cygwin1.dll not found in extracted files"
        }
        
        # Take the first one found (there should typically be only one)
        $cygwinDllFile = $cygwinDllFiles | Select-Object -First 1
        $sourceDllPath = Join-Path $ExtractedPath $cygwinDllFile
        $destinationDllPath = Join-Path $DestinationPath "cygwin1.dll"
        
        Write-ColoredOutput "Found cygwin1.dll at: $sourceDllPath" "Green" "SUCCESS" "Copy-CygwinDll"
        Write-Log -Message "cygwin1.dll found at: $sourceDllPath" -Level "SUCCESS" -Component "Copy-CygwinDll"
        
        # Ensure destination directory exists
        New-InstallDirectory $DestinationPath
        
        # Copy the DLL
        Write-ColoredOutput "Copying cygwin1.dll to: $destinationDllPath" "Yellow" "INFO" "Copy-CygwinDll"
        Copy-Item -Path $sourceDllPath -Destination $destinationDllPath -Force
        
        # Verify the copy
        if (Test-Path $destinationDllPath) {
            $sourceSize = (Get-Item $sourceDllPath).Length
            $destSize = (Get-Item $destinationDllPath).Length
            
            if ($sourceSize -eq $destSize) {
                Write-ColoredOutput "cygwin1.dll copied successfully!" "Green" "SUCCESS" "Copy-CygwinDll"
                Write-Log -Message "cygwin1.dll copied successfully - Size: $destSize bytes" -Level "SUCCESS" -Component "Copy-CygwinDll"
                
                # Get DLL version info if available
                try {
                    $dllInfo = Get-Item $destinationDllPath
                    $version = $dllInfo.VersionInfo.FileVersion
                    if ($version) {
                        Write-ColoredOutput "DLL Version: $version" "Green" "SUCCESS" "Copy-CygwinDll"
                        Write-Log -Message "DLL Version: $version" -Level "INFO" -Component "Copy-CygwinDll"
                    }
                }
                catch {
                    Write-Log -Message "Could not retrieve DLL version info" -Level "DEBUG" -Component "Copy-CygwinDll"
                }
                
                Write-FunctionLog -FunctionName "Copy-CygwinDll" -Action "EXIT" -Details "Copy successful"
                return $true
            }
            else {
                throw "File size mismatch after copy (Source: $sourceSize, Destination: $destSize)"
            }
        }
        else {
            throw "Destination file not found after copy operation"
        }
    }
    catch {
        Write-ColoredOutput "Error copying cygwin1.dll: $($_.Exception.Message)" "Red" "ERROR" "Copy-CygwinDll"
        Write-FunctionLog -FunctionName "Copy-CygwinDll" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to install Cygwin DLL
function Install-CygwinDll {
    param(
        [string]$TempDir
    )
    
    Write-FunctionLog -FunctionName "Install-CygwinDll" -Action "ENTER" -Details "TempDir: $TempDir"
    
    Write-ColoredOutput "`n=== Cygwin DLL Installation ===" "Magenta" "INFO" "Install-CygwinDll"
    
    try {
        # Get latest version information
        $cygwinInfo = Get-LatestCygwinVersion
        $version = $cygwinInfo.Version
        $packageUrl = $cygwinInfo.PackageUrl
        $fileName = $cygwinInfo.FileName
        $mirror = $cygwinInfo.Mirror
        
        Write-ColoredOutput "Installing Cygwin DLL v$version" "Cyan" "INFO" "Install-CygwinDll"
        Write-ColoredOutput "Mirror: $mirror" "Cyan" "INFO" "Install-CygwinDll"
        Write-ColoredOutput "Package: $fileName" "Cyan" "INFO" "Install-CygwinDll"
        
        # Configure paths - Installation always goes to root\build\MegaTool
        $rootDir = Get-RootDirectory
        $targetDllPath = Join-Path $rootDir "build\MegaTool"
        $packageFilePath = Join-Path $TempDir $fileName
        $extractPath = Join-Path $TempDir "extracted"
        
        Write-Log -Message "Paths configured - Target: $targetDllPath, Package: $packageFilePath, Extract: $extractPath" -Level "INFO" -Component "Install-CygwinDll"
        
        # Create directories
        New-InstallDirectory $TempDir
        New-InstallDirectory $extractPath
        
        # Download the package
        $actualPackagePath = Download-File $packageUrl $packageFilePath
        
        # Extract the package
        $extractionSuccess = Extract-TarXzFile $actualPackagePath $extractPath
        
        if ($extractionSuccess) {
            # Find and copy cygwin1.dll
            Copy-CygwinDll $extractPath $targetDllPath
            
            Write-ColoredOutput "Cygwin DLL installation completed successfully!" "Green" "SUCCESS" "Install-CygwinDll"
            Write-ColoredOutput "Version: $version" "Green" "SUCCESS" "Install-CygwinDll"
            Write-ColoredOutput "Location: $targetDllPath\cygwin1.dll" "Green" "SUCCESS" "Install-CygwinDll"
        }
        else {
            Write-ColoredOutput "Package extraction failed. Manual extraction required." "Yellow" "WARNING" "Install-CygwinDll"
            Write-ColoredOutput "Package location: $actualPackagePath" "Yellow" "WARNING" "Install-CygwinDll"
            Write-ColoredOutput "Extract to: $extractPath" "Yellow" "WARNING" "Install-CygwinDll"
            Write-ColoredOutput "Then copy cygwin1.dll to: $targetDllPath" "Yellow" "WARNING" "Install-CygwinDll"
            Write-Log -Message "Manual extraction required due to extraction failure" -Level "WARNING" -Component "Install-CygwinDll"
        }
        
        # Cleanup temporary files
        Write-ColoredOutput "Cleaning up temporary files..." "Yellow" "INFO" "Install-CygwinDll"
        Write-Log -Message "Starting cleanup of temporary files" -Level "INFO" -Component "Install-CygwinDll"
        try {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColoredOutput "Cleanup completed" "Green" "SUCCESS" "Install-CygwinDll"
            Write-Log -Message "Temporary files cleanup completed successfully" -Level "SUCCESS" -Component "Install-CygwinDll"
        }
        catch {
            Write-ColoredOutput "Warning: Some temporary files may remain in $TempDir" "Yellow" "WARNING" "Install-CygwinDll"
            Write-Log -Message "Cleanup warning: Some temporary files may remain - $($_.Exception.Message)" -Level "WARNING" -Component "Install-CygwinDll"
        }
        
        Write-FunctionLog -FunctionName "Install-CygwinDll" -Action "EXIT" -Details "Installation process completed"
        
    }
    catch {
        Write-ColoredOutput "Error during Cygwin DLL installation: $($_.Exception.Message)" "Red" "ERROR" "Install-CygwinDll"
        Write-FunctionLog -FunctionName "Install-CygwinDll" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Determine installation path and log directory BEFORE Main execution
Write-Host "Detecting main tree root..." -ForegroundColor Yellow

if ([string]::IsNullOrWhiteSpace($InstallationPath)) {
    # Case 1 or Case 4: No installation path provided
    $rootDir = Get-RootDirectory
    Write-Host "Main tree root detected: $rootDir" -ForegroundColor Green
    $resolvedInstallPath = Join-Path $rootDir "install"
    $LogDirectory = Join-Path $resolvedInstallPath "GameShell65_Log_Install"
} else {
    # Case 2 or Case 3: Installation path provided
    $resolvedInstallPath = $InstallationPath.TrimEnd('\', '/')
    $LogDirectory = Join-Path $resolvedInstallPath "GameShell65_Log_Install"
}

# Set log file path
$LogFile = Join-Path $LogDirectory "win_install_cygwindll.log"

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
    $LogFile = Join-Path (Get-Location) "win_install_cygwindll.log"
}

# Initialize log file
try {
    # Create or clear the log file
    $logHeader = @"
================================================================================
GameShell65 - Cygwin DLL Installation Log
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
    Write-ColoredOutput "=== GameShell65 - Cygwin DLL Installer ===" "Magenta" "INFO" "MAIN"
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
        $null = Invoke-WebRequest -Uri "https://cygwin.mirror.constant.com" -Method Head -UseBasicParsing -TimeoutSec 10
        Write-ColoredOutput "Internet connection confirmed" "Green" "SUCCESS" "MAIN"
        Write-Log -Message "Internet connectivity confirmed" -Level "SUCCESS" -Component "MAIN"
    }
    catch {
        Write-ColoredOutput "ERROR: Internet connection required to download Cygwin package" "Red" "ERROR" "MAIN"
        Write-ColoredOutput "Details: $($_.Exception.Message)" "Red" "ERROR" "MAIN"
        Write-Log -Message "FATAL: Internet connection failed - $($_.Exception.Message)" -Level "ERROR" -Component "MAIN"
        exit 1
    }
    
    # Create base directory
    New-InstallDirectory $resolvedInstallPath
    
    # Install Cygwin DLL
    Install-CygwinDll $tempDir
    
    $rootDir = Get-RootDirectory
    Write-ColoredOutput "`n=== Installation completed successfully! ===" "Green" "SUCCESS" "MAIN"
    Write-ColoredOutput "cygwin1.dll has been installed to:" "Green" "SUCCESS" "MAIN"
    Write-ColoredOutput "$rootDir\build\MegaTool\cygwin1.dll" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "Applications requiring cygwin1.dll should now work properly." "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "You may need to restart your terminal session to use the updated environment." "Yellow" "INFO" "MAIN"
    
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