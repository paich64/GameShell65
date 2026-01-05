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
function Get-MainArborescence {
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
            $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\mega65rom"
            Write-ColoredOutput "Using installation-based temporary directory: $tempDir" "Cyan" "INFO" "Get-TempDirectory"
        }
        else {
            # User provided temp directory
            $tempDir = Join-Path $UserTempDir "GameShell65_temp_Install\mega65rom"
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
                    $tempDir = Join-Path $BaseInstallPath "GameShell65_temp_Install\mega65rom"
                }
            }
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

# Function to extract RDF file from ZIP
function Extract-RdfFromZip {
    param(
        [string]$ZipPath,
        [string]$DestinationPath
    )
    
    Write-FunctionLog -FunctionName "Extract-RdfFromZip" -Action "ENTER" -Details "ZipPath: $ZipPath, DestinationPath: $DestinationPath"
    
    try {
        Write-ColoredOutput "Extracting RDF file from ZIP archive..." "Yellow" "INFO" "Extract-RdfFromZip"
        
        # Load required assembly for ZIP operations
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        
        # Open the ZIP file
        $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        
        try {
            # Find the RDF file
            $rdfFile = $zipArchive.Entries | Where-Object { $_.Name -like "*.rdf" } | Select-Object -First 1
            
            if ($rdfFile) {
                Write-ColoredOutput "Found RDF file: $($rdfFile.Name)" "Green" "SUCCESS" "Extract-RdfFromZip"
                
                # Extract the RDF file to destination
                $rdfDestination = Join-Path $DestinationPath $rdfFile.Name
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($rdfFile, $rdfDestination, $true)
                
                Write-ColoredOutput "RDF file extracted to: $rdfDestination" "Green" "SUCCESS" "Extract-RdfFromZip"
                Write-Log -Message "RDF file extracted successfully: $($rdfFile.Name)" -Level "SUCCESS" -Component "Extract-RdfFromZip"
                
                Write-FunctionLog -FunctionName "Extract-RdfFromZip" -Action "EXIT" -Details "Success: $($rdfFile.Name)"
                return $rdfFile.Name
            }
            else {
                throw "No RDF file found in the ZIP archive"
            }
        }
        finally {
            $zipArchive.Dispose()
        }
    }
    catch {
        Write-ColoredOutput "Error extracting RDF file: $($_.Exception.Message)" "Red" "ERROR" "Extract-RdfFromZip"
        Write-FunctionLog -FunctionName "Extract-RdfFromZip" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to execute romdiff command
function Invoke-RomDiff {
    param(
        [string]$RdfFile,
        [string]$WorkingDirectory
    )
    
    Write-FunctionLog -FunctionName "Invoke-RomDiff" -Action "ENTER" -Details "RDF: $RdfFile, WorkDir: $WorkingDirectory"
    
    try {
        Write-ColoredOutput "Executing romdiff command..." "Yellow" "INFO" "Invoke-RomDiff"
        
        # Verify romdiff.exe is available
        try {
            $romdiffPath = Get-Command "romdiff.exe" -ErrorAction Stop
            Write-ColoredOutput "Found romdiff.exe at: $($romdiffPath.Source)" "Green" "SUCCESS" "Invoke-RomDiff"
        }
        catch {
            throw "romdiff.exe not found in PATH. Please ensure it is installed and available."
        }
        
        # Prepare the command paths
        $rdfPath = ".\$RdfFile"
        $mega65RomPath = ".\mega65.rom"
        
        Write-ColoredOutput "Working directory: $WorkingDirectory" "Cyan" "INFO" "Invoke-RomDiff"
        Write-ColoredOutput "RDF input file: $rdfPath" "Cyan" "INFO" "Invoke-RomDiff"
        Write-ColoredOutput "Output file: $mega65RomPath" "Cyan" "INFO" "Invoke-RomDiff"
        
        # Verify RDF file exists
        $fullRdfPath = Join-Path $WorkingDirectory $RdfFile
        if (-not (Test-Path $fullRdfPath)) {
            throw "RDF file not found: $fullRdfPath"
        }
        
        # Verify 910828.bin exists (romdiff looks for this automatically)
        $bin910828Path = Join-Path $WorkingDirectory "910828.bin"
        if (-not (Test-Path $bin910828Path)) {
            throw "Required file 910828.bin not found: $bin910828Path (romdiff searches for this file automatically)"
        }
        
        # Ensure mega65.rom doesn't exist before running (clean start)
        $fullMega65RomPath = Join-Path $WorkingDirectory "mega65.rom"
        if (Test-Path $fullMega65RomPath) {
            Write-ColoredOutput "Removing existing mega65.rom file..." "Yellow" "INFO" "Invoke-RomDiff"
            Remove-Item -Path $fullMega65RomPath -Force
        }
        
        # Execute romdiff command
        $originalLocation = Get-Location
        Set-Location $WorkingDirectory
        
        try {
            Write-ColoredOutput "Running: romdiff.exe $rdfPath $mega65RomPath" "Cyan" "INFO" "Invoke-RomDiff"
            Write-ColoredOutput "Note: romdiff will automatically use 910828.bin as implicit input" "Gray" "INFO" "Invoke-RomDiff"
            $romdiffStartTime = Get-Date
            
            $processResult = Start-Process -FilePath "romdiff.exe" -ArgumentList "$rdfPath", "$mega65RomPath" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "romdiff_output.txt" -RedirectStandardError "romdiff_error.txt"
            
            $romdiffEndTime = Get-Date
            $romdiffDuration = ($romdiffEndTime - $romdiffStartTime).TotalSeconds
            
            # Read output files
            $stdOutput = ""
            $stdError = ""
            
            if (Test-Path "romdiff_output.txt") {
                $stdOutput = Get-Content "romdiff_output.txt" -Raw
                Remove-Item "romdiff_output.txt" -Force -ErrorAction SilentlyContinue
            }
            
            if (Test-Path "romdiff_error.txt") {
                $stdError = Get-Content "romdiff_error.txt" -Raw
                Remove-Item "romdiff_error.txt" -Force -ErrorAction SilentlyContinue
            }
            
            # Check if mega65.rom was created
            if (Test-Path "mega65.rom") {
                $outputFileSize = (Get-Item "mega65.rom").Length
                Write-ColoredOutput "mega65.rom created successfully (Size: $outputFileSize bytes)" "Green" "SUCCESS" "Invoke-RomDiff"
                Write-Log -Message "mega65.rom created successfully - Size: $outputFileSize bytes" -Level "SUCCESS" -Component "Invoke-RomDiff"
            } else {
                Write-ColoredOutput "Warning: mega65.rom was not created" "Yellow" "WARNING" "Invoke-RomDiff"
                Write-Log -Message "Warning: mega65.rom output file was not created" -Level "WARNING" -Component "Invoke-RomDiff"
            }
            
            if ($processResult.ExitCode -eq 0) {
                Write-ColoredOutput "romdiff completed successfully" "Green" "SUCCESS" "Invoke-RomDiff"
                Write-Log -Message "romdiff completed successfully - Duration: $([math]::Round($romdiffDuration, 2)) seconds, Exit Code: $($processResult.ExitCode)" -Level "SUCCESS" -Component "Invoke-RomDiff"
                
                if ($stdOutput) {
                    Write-ColoredOutput "romdiff output:" "Cyan" "INFO" "Invoke-RomDiff"
                    Write-ColoredOutput $stdOutput "White" "INFO" "Invoke-RomDiff"
                    Write-Log -Message "romdiff output: $stdOutput" -Level "INFO" -Component "Invoke-RomDiff"
                }
            }
            else {
                Write-ColoredOutput "romdiff completed with warnings/errors (Exit Code: $($processResult.ExitCode))" "Yellow" "WARNING" "Invoke-RomDiff"
                Write-Log -Message "romdiff completed with exit code $($processResult.ExitCode)" -Level "WARNING" -Component "Invoke-RomDiff"
                
                if ($stdError) {
                    Write-ColoredOutput "romdiff errors:" "Yellow" "WARNING" "Invoke-RomDiff"
                    Write-ColoredOutput $stdError "Yellow" "WARNING" "Invoke-RomDiff"
                    Write-Log -Message "romdiff error output: $stdError" -Level "WARNING" -Component "Invoke-RomDiff"
                }
                
                if ($stdOutput) {
                    Write-ColoredOutput "romdiff output:" "Cyan" "INFO" "Invoke-RomDiff"
                    Write-ColoredOutput $stdOutput "White" "INFO" "Invoke-RomDiff"
                    Write-Log -Message "romdiff output: $stdOutput" -Level "INFO" -Component "Invoke-RomDiff"
                }
            }
            
            Write-FunctionLog -FunctionName "Invoke-RomDiff" -Action "EXIT" -Details "Completed with exit code: $($processResult.ExitCode)"
        }
        finally {
            Set-Location $originalLocation
        }
    }
    catch {
        Set-Location $originalLocation -ErrorAction SilentlyContinue
        Write-ColoredOutput "Error executing romdiff: $($_.Exception.Message)" "Red" "ERROR" "Invoke-RomDiff"
        Write-FunctionLog -FunctionName "Invoke-RomDiff" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Main function to process MEGA65 ROM files
function Install-Mega65Rom {
    param(
        [string]$BaseInstallPath,
        [string]$TempDir
    )
    
    Write-FunctionLog -FunctionName "Install-Mega65Rom" -Action "ENTER" -Details "BaseInstallPath: $BaseInstallPath, TempDir: $TempDir"
    
    Write-ColoredOutput "`n=== MEGA65 ROM Processing ===" "Magenta" "INFO" "Install-Mega65Rom"
    
    try {
        # URLs to download
        $binUrl = "https://www.zimmers.net/anonftp/pub/cbm/firmware/computers/c65/910828.bin"
        $zipUrl = "https://files.mega65.org/files/other/920413_Sn7YEw.zip"
        
        # Configure paths - no longer add "\mega65rom" as it's already in BaseInstallPath
        $mega65RomPath = $BaseInstallPath
        
        Write-ColoredOutput "MEGA65 ROM directory: $mega65RomPath" "Cyan" "INFO" "Install-Mega65Rom"
        Write-Log -Message "Processing paths configured - ROM directory: $mega65RomPath, Temp: $TempDir" -Level "INFO" -Component "Install-Mega65Rom"
        
        # Create directories
        New-InstallDirectory $mega65RomPath
        New-InstallDirectory $TempDir
        
        # Step 1 & 2: Download both files to mega65rom directory
        Write-ColoredOutput "`nStep 1-2: Downloading ROM files to mega65rom directory..." "Yellow" "INFO" "Install-Mega65Rom"
        
        $binDestination = Join-Path $mega65RomPath "910828.bin"
        $zipDestination = Join-Path $TempDir "920413_Sn7YEw.zip"
        
        Write-ColoredOutput "Downloading 910828.bin..." "Cyan" "INFO" "Install-Mega65Rom"
        Download-File $binUrl $binDestination
        
        Write-ColoredOutput "Downloading 920413_Sn7YEw.zip..." "Cyan" "INFO" "Install-Mega65Rom"
        $actualZipPath = Download-File $zipUrl $zipDestination
        
        # Step 3: Extract RDF file from ZIP to mega65rom directory
        Write-ColoredOutput "`nStep 3: Extracting RDF file from ZIP to mega65rom directory..." "Yellow" "INFO" "Install-Mega65Rom"
        $rdfFileName = Extract-RdfFromZip $actualZipPath $mega65RomPath
        
        # Step 4: Execute romdiff command
        Write-ColoredOutput "`nStep 4: Executing romdiff command..." "Yellow" "INFO" "Install-Mega65Rom"
        Write-ColoredOutput "Note: romdiff.exe will automatically look for 910828.bin in the working directory" "Cyan" "INFO" "Install-Mega65Rom"
        Invoke-RomDiff $rdfFileName $mega65RomPath
        
        # Step 5: Clean up intermediate files but keep mega65.rom
        Write-ColoredOutput "`nStep 5: Cleaning up intermediate files (keeping only mega65.rom)..." "Yellow" "INFO" "Install-Mega65Rom"
        
        # Get list of all files in mega65rom directory
        $allFiles = Get-ChildItem -Path $mega65RomPath -File
        $mega65RomFile = Join-Path $mega65RomPath "mega65.rom"
        
        # Verify mega65.rom exists before cleanup
        if (-not (Test-Path $mega65RomFile)) {
            Write-ColoredOutput "Warning: mega65.rom not found before cleanup!" "Yellow" "WARNING" "Install-Mega65Rom"
            Write-Log -Message "Warning: mega65.rom not found before cleanup" -Level "WARNING" -Component "Install-Mega65Rom"
        }
        
        # Remove all files except mega65.rom
        foreach ($file in $allFiles) {
            if ($file.Name -ne "mega65.rom") {
                try {
                    Remove-Item -Path $file.FullName -Force
                    Write-ColoredOutput "Removed: $($file.Name)" "Green" "SUCCESS" "Install-Mega65Rom"
                    Write-Log -Message "Removed intermediate file: $($file.Name)" -Level "SUCCESS" -Component "Install-Mega65Rom"
                }
                catch {
                    Write-ColoredOutput "Warning: Could not remove $($file.Name): $($_.Exception.Message)" "Yellow" "WARNING" "Install-Mega65Rom"
                    Write-Log -Message "Failed to remove $($file.Name): $($_.Exception.Message)" -Level "WARNING" -Component "Install-Mega65Rom"
                }
            }
        }
        
        # Verify final state
        $remainingFiles = Get-ChildItem -Path $mega65RomPath -File
        if ($remainingFiles.Count -eq 1 -and $remainingFiles[0].Name -eq "mega65.rom") {
            $fileSize = $remainingFiles[0].Length
            Write-ColoredOutput "Cleanup completed successfully - only mega65.rom remains (Size: $fileSize bytes)" "Green" "SUCCESS" "Install-Mega65Rom"
            Write-Log -Message "Cleanup completed successfully - only mega65.rom remains (Size: $fileSize bytes)" -Level "SUCCESS" -Component "Install-Mega65Rom"
        } elseif ($remainingFiles.Count -eq 0) {
            Write-ColoredOutput "Warning: No files remain in mega65rom directory (mega65.rom may not have been created)" "Yellow" "WARNING" "Install-Mega65Rom"
            Write-Log -Message "Warning: No files remain in mega65rom directory" -Level "WARNING" -Component "Install-Mega65Rom"
        } else {
            Write-ColoredOutput "Warning: Multiple files remain in mega65rom directory:" "Yellow" "WARNING" "Install-Mega65Rom"
            foreach ($file in $remainingFiles) {
                Write-ColoredOutput "  - $($file.Name)" "Yellow" "WARNING" "Install-Mega65Rom"
            }
            Write-Log -Message "Warning: Multiple files remain: $($remainingFiles.Name -join ', ')" -Level "WARNING" -Component "Install-Mega65Rom"
        }
        
        # Also clean up temp directory
        Write-ColoredOutput "Cleaning up temporary files..." "Yellow" "INFO" "Install-Mega65Rom"
        try {
            if (Test-Path $TempDir) {
                Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-ColoredOutput "Temporary files cleanup completed" "Green" "SUCCESS" "Install-Mega65Rom"
                Write-Log -Message "Temporary files cleanup completed successfully" -Level "SUCCESS" -Component "Install-Mega65Rom"
            }
        }
        catch {
            Write-ColoredOutput "Warning: Some temporary files may remain in $TempDir" "Yellow" "WARNING" "Install-Mega65Rom"
            Write-Log -Message "Cleanup warning: Some temporary files may remain - $($_.Exception.Message)" -Level "WARNING" -Component "Install-Mega65Rom"
        }
        
        Write-ColoredOutput "MEGA65 ROM processing completed successfully!" "Green" "SUCCESS" "Install-Mega65Rom"
        Write-Log -Message "MEGA65 ROM processing completed successfully" -Level "SUCCESS" -Component "Install-Mega65Rom"
        
        Write-FunctionLog -FunctionName "Install-Mega65Rom" -Action "EXIT" -Details "Processing completed successfully"
        
    }
    catch {
        Write-ColoredOutput "Error during MEGA65 ROM processing: $($_.Exception.Message)" "Red" "ERROR" "Install-Mega65Rom"
        Write-FunctionLog -FunctionName "Install-Mega65Rom" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Determine installation path and log directory BEFORE Main execution
if ([string]::IsNullOrWhiteSpace($InstallationPath)) {
    # Case 1 or Case 4: No installation path provided
    $mainTreeRoot = Get-MainArborescence
    $resolvedInstallPath = Join-Path $mainTreeRoot "install"
    $LogDirectory = Join-Path $resolvedInstallPath "GameShell65_Log_Install"
} else {
    # Case 2 or Case 3: Installation path provided - used ONLY for logs/temp
    $LogDirectory = Join-Path $InstallationPath "GameShell65_Log_Install"
    $resolvedInstallPath = $InstallationPath  # Used only for temp directory determination
}

# Final installation is ALWAYS in Arborescence_Principale
$mainTreeRoot = Get-MainArborescence
$finalInstallPath = Join-Path $mainTreeRoot "install\mega65rom"

# Set log file path
$LogFile = Join-Path $LogDirectory "win_install_mega65rom.log"

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
    $LogFile = Join-Path (Get-Location) "win_install_mega65rom.log"
}

# Initialize log file
try {
    # Create or clear the log file
    $logHeader = @"
================================================================================
GameShell65 - MEGA65 ROM Processing Log
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Script Path: $($MyInvocation.MyCommand.Path)
Installation Path (final): $finalInstallPath
Temp Directory Base: $resolvedInstallPath
Log Directory: $LogDirectory
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
    Write-ColoredOutput "=== GameShell65 - MEGA65 ROM Processor ===" "Magenta" "INFO" "MAIN"
    Write-ColoredOutput "Final installation directory: $finalInstallPath" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "Log directory: $LogDirectory" "Cyan" "INFO" "MAIN"
    Write-Log -Message "Script execution started" -Level "INFO" -Component "MAIN"
    Write-Log -Message "Parameters - InstallationPath: $InstallationPath, TempDirectory: $TempDirectory" -Level "INFO" -Component "MAIN"
    Write-Log -Message "Resolved paths - Final Install: $finalInstallPath, Base for temp: $resolvedInstallPath, Log: $LogDirectory" -Level "INFO" -Component "MAIN"
    
    # Get and validate temporary directory
    $tempDir = Get-TempDirectory -UserTempDir $TempDirectory -BaseInstallPath $resolvedInstallPath
    Write-ColoredOutput "Temporary directory: $tempDir" "Cyan" "INFO" "MAIN"
    
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
        $null = Invoke-WebRequest -Uri "https://www.zimmers.net" -Method Head -UseBasicParsing -TimeoutSec 10
        Write-ColoredOutput "Internet connection confirmed" "Green" "SUCCESS" "MAIN"
        Write-Log -Message "Internet connectivity confirmed" -Level "SUCCESS" -Component "MAIN"
    }
    catch {
        Write-ColoredOutput "ERROR: Internet connection required to download ROM files" "Red" "ERROR" "MAIN"
        Write-ColoredOutput "Details: $($_.Exception.Message)" "Red" "ERROR" "MAIN"
        Write-Log -Message "FATAL: Internet connection failed - $($_.Exception.Message)" -Level "ERROR" -Component "MAIN"
        exit 1
    }
    
    # Check if romdiff.exe is available
    Write-ColoredOutput "Checking for romdiff.exe..." "Yellow" "INFO" "MAIN"
    Write-Log -Message "Checking for romdiff.exe availability" -Level "INFO" -Component "MAIN"
    try {
        $romdiffPath = Get-Command "romdiff.exe" -ErrorAction Stop
        Write-ColoredOutput "Found romdiff.exe at: $($romdiffPath.Source)" "Green" "SUCCESS" "MAIN"
        Write-Log -Message "romdiff.exe found at: $($romdiffPath.Source)" -Level "SUCCESS" -Component "MAIN"
    }
    catch {
        Write-ColoredOutput "ERROR: romdiff.exe not found in PATH!" "Red" "ERROR" "MAIN"
        Write-ColoredOutput "Please ensure romdiff.exe is installed and available in the system PATH." "Red" "ERROR" "MAIN"
        Write-Log -Message "FATAL: romdiff.exe not found in PATH" -Level "ERROR" -Component "MAIN"
        exit 1
    }
    
    # Process MEGA65 ROM files
    Install-Mega65Rom $finalInstallPath $tempDir
    
    Write-ColoredOutput "`n=== MEGA65 ROM processing completed successfully! ===" "Green" "SUCCESS" "MAIN"
    Write-ColoredOutput "Only mega65.rom should remain in the mega65rom directory." "Green" "SUCCESS" "MAIN"
    
    $scriptEndTime = Get-Date
    $totalDuration = ($scriptEndTime - $Global:LogStartTime).TotalSeconds
    Write-Log -Message "Script completed successfully in $([math]::Round($totalDuration, 2)) seconds" -Level "SUCCESS" -Component "MAIN"
    Write-Log -Message "Log file location: $LogFile" -Level "INFO" -Component "MAIN"
}
catch {
    Write-ColoredOutput "`nFATAL ERROR: $($_.Exception.Message)" "Red" "ERROR" "MAIN"
    Write-ColoredOutput "MEGA65 ROM processing failed." "Red" "ERROR" "MAIN"
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