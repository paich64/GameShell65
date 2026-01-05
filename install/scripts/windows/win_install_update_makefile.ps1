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

# Global variables for paths (will be initialized after detecting base path)
$Global:BaseRootPath = ""
$Global:LogDirectory = ""
$Global:LogFile = ""
$Global:TempWorkDirectory = ""
$Global:MakefilePath = ""

$Global:LogStartTime = Get-Date
$Global:ModificationsSummary = @()
$Global:ScriptSucceeded = $false

# Function to detect Arborescence_Principale from script location
function Get-BaseRootPath {
    param([string]$ProvidedInstallationPath)
    
    try {
        if ($ProvidedInstallationPath -ne "") {
            # Installation path provided as parameter
            if (-not (Test-Path $ProvidedInstallationPath)) {
                throw "Provided installation path does not exist: $ProvidedInstallationPath"
            }
            Write-Host "Using provided installation path: $ProvidedInstallationPath" -ForegroundColor Cyan
            return $ProvidedInstallationPath
        }
        else {
            # Detect from script location: script is in Arborescence_Principale\install\scripts\windows
            $scriptPath = $PSCommandPath
            if (-not $scriptPath) {
                $scriptPath = $MyInvocation.MyCommand.Path
            }
            
            $scriptDir = Split-Path -Parent $scriptPath
            
            # Go up 3 levels: windows -> scripts -> install -> Arborescence_Principale
            $installDir = Split-Path -Parent $scriptDir  # scripts
            $installDir = Split-Path -Parent $installDir  # install
            $rootDir = Split-Path -Parent $installDir     # Arborescence_Principale
            
            if (-not (Test-Path $rootDir)) {
                throw "Could not detect base root path from script location: $scriptPath"
            }
            
            Write-Host "Auto-detected base root path: $rootDir" -ForegroundColor Cyan
            return $rootDir
        }
    }
    catch {
        throw "Error detecting base root path: $($_.Exception.Message)"
    }
}

# Function to initialize all paths based on base root path
function Initialize-Paths {
    param([string]$BaseRoot)
    
    try {
        # Set global base path
        $Global:BaseRootPath = $BaseRoot
        
        # Initialize log directory and file
        $Global:LogDirectory = Join-Path $BaseRoot "install\GameShell65_Log_Install"
        $Global:LogFile = Join-Path $Global:LogDirectory "win_install_update_makefile.log"
        
        # Initialize temp directory
        $Global:TempWorkDirectory = Join-Path $BaseRoot "install\GameShell65_temp_Install\makefileUpdate"
        
        # Initialize makefile path
        $Global:MakefilePath = Join-Path $BaseRoot "makefile"
        
        # Create directories if they don't exist
        if (-not (Test-Path $Global:LogDirectory)) {
            New-Item -ItemType Directory -Path $Global:LogDirectory -Force | Out-Null
            Write-Host "Created log directory: $Global:LogDirectory" -ForegroundColor Yellow
        }
        
        if (-not (Test-Path $Global:TempWorkDirectory)) {
            New-Item -ItemType Directory -Path $Global:TempWorkDirectory -Force | Out-Null
            Write-Host "Created temp directory: $Global:TempWorkDirectory" -ForegroundColor Yellow
        }
        
        Write-Host "Paths initialized successfully" -ForegroundColor Green
        Write-Host "  Base Root: $Global:BaseRootPath" -ForegroundColor Cyan
        Write-Host "  Log Dir: $Global:LogDirectory" -ForegroundColor Cyan
        Write-Host "  Temp Dir: $Global:TempWorkDirectory" -ForegroundColor Cyan
        Write-Host "  Makefile: $Global:MakefilePath" -ForegroundColor Cyan
    }
    catch {
        throw "Error initializing paths: $($_.Exception.Message)"
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
        Add-Content -Path $Global:LogFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
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

# Function to validate installation path
function Test-InstallationPath {
    param([string]$Path)
    
    Write-FunctionLog -FunctionName "Test-InstallationPath" -Action "ENTER" -Details "Path: $Path"
    
    try {
        if (-not (Test-Path $Path)) {
            throw "Makefile path does not exist: $Path"
        }
        
        Write-ColoredOutput "Makefile path validated successfully" "Green" "SUCCESS" "Test-InstallationPath"
        Write-Log -Message "Makefile validation successful - makefile found at $Path" -Level "SUCCESS" -Component "Test-InstallationPath"
        Write-FunctionLog -FunctionName "Test-InstallationPath" -Action "EXIT" -Details "Validation successful"
        
        return $Path
    }
    catch {
        Write-Log -Message "Makefile validation failed: $($_.Exception.Message)" -Level "ERROR" -Component "Test-InstallationPath"
        Write-FunctionLog -FunctionName "Test-InstallationPath" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to backup makefile
function Backup-Makefile {
    param(
        [string]$MakefilePath
    )
    
    Write-FunctionLog -FunctionName "Backup-Makefile" -Action "ENTER" -Details "MakefilePath: $MakefilePath"
    
    try {
        $backupPath = $MakefilePath + ".ori"
        
        # Check if backup already exists
        if (Test-Path $backupPath) {
            Write-ColoredOutput "Backup file already exists: $backupPath" "Yellow" "WARNING" "Backup-Makefile"
            Write-Log -Message "Backup file already exists, will not overwrite: $backupPath" -Level "WARNING" -Component "Backup-Makefile"
        }
        else {
            Copy-Item -Path $MakefilePath -Destination $backupPath -Force
            Write-ColoredOutput "Makefile backed up to: $backupPath" "Green" "SUCCESS" "Backup-Makefile"
            Write-Log -Message "Makefile backup created successfully: $backupPath" -Level "SUCCESS" -Component "Backup-Makefile"
        }
        
        Write-FunctionLog -FunctionName "Backup-Makefile" -Action "EXIT" -Details "Backup completed"
        return $backupPath
    }
    catch {
        Write-Log -Message "Makefile backup failed: $($_.Exception.Message)" -Level "ERROR" -Component "Backup-Makefile"
        Write-FunctionLog -FunctionName "Backup-Makefile" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to find tool file in directory
function Find-ToolFile {
    param(
        [string]$SearchPath,
        [string]$FilePattern,
        [string]$ToolName
    )
    
    Write-FunctionLog -FunctionName "Find-ToolFile" -Action "ENTER" -Details "SearchPath: $SearchPath, Pattern: $FilePattern, Tool: $ToolName"
    
    try {
        if (-not (Test-Path $SearchPath)) {
            Write-Log -Message "${ToolName} - Search path does not exist - $SearchPath" -Level "WARNING" -Component "Find-ToolFile"
            Write-FunctionLog -FunctionName "Find-ToolFile" -Action "EXIT" -Details "Path not found"
            return $null
        }
        
        Write-Log -Message "${ToolName} - Searching for $FilePattern in $SearchPath" -Level "DEBUG" -Component "Find-ToolFile"
        
        # Search for files matching pattern
        $foundFiles = Get-ChildItem -Path $SearchPath -Filter $FilePattern -File -ErrorAction SilentlyContinue
        
        if ($foundFiles.Count -eq 0) {
            Write-Log -Message "${ToolName} - No files matching pattern '$FilePattern' found in $SearchPath" -Level "WARNING" -Component "Find-ToolFile"
            Write-FunctionLog -FunctionName "Find-ToolFile" -Action "EXIT" -Details "No files found"
            return $null
        }
        
        # If multiple files found, take the first one and warn
        if ($foundFiles.Count -gt 1) {
            Write-Log -Message "${ToolName} - Multiple files found matching '$FilePattern', using first one - $($foundFiles[0].Name)" -Level "WARNING" -Component "Find-ToolFile"
            $foundFiles | ForEach-Object { 
                Write-Log -Message "${ToolName} - Found file - $($_.FullName)" -Level "DEBUG" -Component "Find-ToolFile" 
            }
        }
        
        $selectedFile = $foundFiles[0]
        Write-Log -Message "${ToolName} - Selected file - $($selectedFile.FullName)" -Level "SUCCESS" -Component "Find-ToolFile"
        Write-FunctionLog -FunctionName "Find-ToolFile" -Action "EXIT" -Details "File found: $($selectedFile.Name)"
        
        return $selectedFile.FullName
    }
    catch {
        Write-Log -Message "${ToolName} - Error searching for file - $($_.Exception.Message)" -Level "ERROR" -Component "Find-ToolFile"
        Write-FunctionLog -FunctionName "Find-ToolFile" -Action "ERROR" -Details $_.Exception.Message
        return $null
    }
}

# Function to discover tool paths
function Get-ToolPaths {
    param([string]$BaseRootPath)
    
    Write-FunctionLog -FunctionName "Get-ToolPaths" -Action "ENTER" -Details "BaseRootPath: $BaseRootPath"
    
    Write-ColoredOutput "Discovering tool paths..." "Yellow" "INFO" "Get-ToolPaths"
    
    try {
        # Define tool search configurations
        $toolConfigs = @{
            "KICK" = @{
                SearchPath = Join-Path $BaseRootPath "install\PCTOOLS\kickass"
                FilePattern = "*.jar"
                Description = "KickAssembler JAR file"
            }
            "C1541" = @{
                SearchPath = Join-Path $BaseRootPath "install\PCTOOLS\vice\bin"
                FilePattern = "c1541.exe"
                Description = "VICE C1541 executable"
            }
            "XEMU" = @{
                SearchPath = Join-Path $BaseRootPath "install\xemu"
                FilePattern = "xmega65.exe"
                Description = "XEMU executable"
            }
            "MEGA65_FTP" = @{
                SearchPath = Join-Path $BaseRootPath "install\PCTOOLS\m65tools"
                FilePattern = "mega65_ftp.exe"
                Description = "MEGA65 FTP executable"
            }
            "EMEGA65_FTP" = @{
                SearchPath = Join-Path $BaseRootPath "install\PCTOOLS\m65tools"
                FilePattern = "mega65_ftp.exe"
                Description = "MEGA65 FTP executable (same as MEGA65_FTP)"
            }
            "ETHERLOAD" = @{
                SearchPath = Join-Path $BaseRootPath "install\PCTOOLS\m65tools"
                FilePattern = "etherload.exe"
                Description = "Etherload executable"
            }
        }
        
        $toolPaths = @{}
        
        foreach ($toolName in $toolConfigs.Keys) {
            $config = $toolConfigs[$toolName]
            Write-ColoredOutput "Searching for $toolName ($($config.Description))..." "Cyan" "INFO" "Get-ToolPaths"
            
            $foundPath = Find-ToolFile -SearchPath $config.SearchPath -FilePattern $config.FilePattern -ToolName $toolName
            
            if ($foundPath) {
                # Convert to relative path from the makefile directory (base root)
                $makefileDir = Split-Path -Parent $Global:MakefilePath
                try {
                    $relativePath = [System.IO.Path]::GetRelativePath($makefileDir, $foundPath)
                    # Ensure forward slashes for Makefile compatibility
                    $relativePath = $relativePath.Replace('\', '/')
                    $toolPaths[$toolName] = $relativePath
                    Write-ColoredOutput "$toolName found: $relativePath" "Green" "SUCCESS" "Get-ToolPaths"
                    Write-Log -Message "${toolName} - Found at $foundPath, relative path - $relativePath" -Level "SUCCESS" -Component "Get-ToolPaths"
                }
                catch {
                    # Fallback to absolute path if relative path calculation fails
                    $absolutePath = $foundPath.Replace('\', '/')
                    $toolPaths[$toolName] = $absolutePath
                    Write-ColoredOutput "$toolName found: $absolutePath (absolute path)" "Green" "SUCCESS" "Get-ToolPaths"
                    Write-Log -Message "${toolName} - Using absolute path - $absolutePath (relative path calculation failed)" -Level "WARNING" -Component "Get-ToolPaths"
                }
            }
            else {
                Write-ColoredOutput "$toolName not found in expected location" "Red" "ERROR" "Get-ToolPaths"
                Write-Log -Message "${toolName} - File not found in $($config.SearchPath) with pattern $($config.FilePattern) - no modification will be made" -Level "WARNING" -Component "Get-ToolPaths"
            }
        }
        
        Write-FunctionLog -FunctionName "Get-ToolPaths" -Action "EXIT" -Details "$($toolPaths.Keys.Count) tools found"
        return $toolPaths
    }
    catch {
        Write-Log -Message "Error discovering tool paths: $($_.Exception.Message)" -Level "ERROR" -Component "Get-ToolPaths"
        Write-FunctionLog -FunctionName "Get-ToolPaths" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to parse and modify makefile
function Update-Makefile {
    param(
        [string]$MakefilePath,
        [hashtable]$ToolPaths
    )
    
    Write-FunctionLog -FunctionName "Update-Makefile" -Action "ENTER" -Details "MakefilePath: $MakefilePath"
    
    Write-ColoredOutput "Reading and updating Makefile..." "Yellow" "INFO" "Update-Makefile"
    
    try {
        # Read the entire makefile
        $makefileContent = Get-Content -Path $MakefilePath -Encoding UTF8
        $updatedContent = @()
        $inWindowsSection = $false
        $modificationsCount = 0
        
        Write-Log -Message "Original makefile read successfully, $($makefileContent.Count) lines" -Level "SUCCESS" -Component "Update-Makefile"
        
        for ($i = 0; $i -lt $makefileContent.Count; $i++) {
            $line = $makefileContent[$i]
            $originalLine = $line
            
            # Detect start of windows section
            if ($line -match '^\s*ifeq\s*\(\s*\$\(windows\)\s*,\s*1\s*\)\s*$') {
                $inWindowsSection = $true
                Write-Log -Message "Found start of Windows section at line $($i + 1)" -Level "DEBUG" -Component "Update-Makefile"
            }
            # Detect end of windows section
            elseif ($inWindowsSection -and $line -match '^\s*else\s*$') {
                $inWindowsSection = $false
                Write-Log -Message "Found end of Windows section at line $($i + 1)" -Level "DEBUG" -Component "Update-Makefile"
            }
            # Process variable assignments in windows section
            elseif ($inWindowsSection -and $line -match '^\s*(\w+)\s*=\s*(.+)\s*$') {
                $variableName = $matches[1].Trim()
                $currentValue = $matches[2].Trim()
                
                # Skip MEGATOOL as per requirements
                if ($variableName -eq "MEGATOOL") {
                    Write-Log -Message "$variableName - Skipped as per requirements (current value - $currentValue)" -Level "INFO" -Component "Update-Makefile"
                }
                # Update other variables if we found a path for them
                elseif ($ToolPaths.ContainsKey($variableName)) {
                    $newValue = $ToolPaths[$variableName]
                    $line = "`t$variableName=$newValue"
                    Write-Log -Message "$variableName - BEFORE - $currentValue" -Level "INFO" -Component "Update-Makefile"
                    Write-Log -Message "$variableName - AFTER - $newValue" -Level "INFO" -Component "Update-Makefile"
                    Write-ColoredOutput "$variableName updated: $currentValue -> $newValue" "Green" "SUCCESS" "Update-Makefile"
                    
                    # Track modification for summary
                    $Global:ModificationsSummary += @{
                        Variable = $variableName
                        Before = $currentValue
                        After = $newValue
                        Status = "MODIFIED"
                    }
                    $modificationsCount++
                }
                # Variable found but no path discovered
                elseif (@("KICK", "C1541", "XEMU", "MEGA65_FTP", "EMEGA65_FTP", "ETHERLOAD") -contains $variableName) {
                    Write-Log -Message "$variableName - No corresponding file found, keeping original value - $currentValue" -Level "WARNING" -Component "Update-Makefile"
                    $Global:ModificationsSummary += @{
                        Variable = $variableName
                        Before = $currentValue
                        After = $currentValue
                        Status = "NOT_FOUND"
                    }
                }
            }
            
            # Add the line (modified or original) to updated content
            $updatedContent += $line
        }
        
        # Write the updated content back to the makefile
        $updatedContent | Out-File -FilePath $MakefilePath -Encoding UTF8 -Force
        
        Write-ColoredOutput "Makefile updated successfully" "Green" "SUCCESS" "Update-Makefile"
        Write-Log -Message "Makefile update completed - $modificationsCount modifications made" -Level "SUCCESS" -Component "Update-Makefile"
        Write-FunctionLog -FunctionName "Update-Makefile" -Action "EXIT" -Details "$modificationsCount modifications made"
        
        return $modificationsCount
    }
    catch {
        Write-Log -Message "Error updating makefile: $($_.Exception.Message)" -Level "ERROR" -Component "Update-Makefile"
        Write-FunctionLog -FunctionName "Update-Makefile" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Function to write modifications summary
function Write-ModificationsSummary {
    Write-FunctionLog -FunctionName "Write-ModificationsSummary" -Action "ENTER"
    
    try {
        Write-Log -Message "=================================================================================" -Level "INFO" -Component "SUMMARY"
        Write-Log -Message "MAKEFILE MODIFICATIONS SUMMARY" -Level "INFO" -Component "SUMMARY"
        Write-Log -Message "=================================================================================" -Level "INFO" -Component "SUMMARY"
        
        $modifiedCount = 0
        $notFoundCount = 0
        $skippedCount = 0
        
        foreach ($modification in $Global:ModificationsSummary) {
            $variable = $modification.Variable
            $before = $modification.Before
            $after = $modification.After
            $status = $modification.Status
            
            switch ($status) {
                "MODIFIED" {
                    Write-Log -Message "$variable - MODIFIED - '$before' -> '$after'" -Level "SUCCESS" -Component "SUMMARY"
                    $modifiedCount++
                }
                "NOT_FOUND" {
                    Write-Log -Message "$variable - NOT FOUND - Kept original value '$before'" -Level "WARNING" -Component "SUMMARY"
                    $notFoundCount++
                }
            }
        }
        
        # Count MEGATOOL as skipped
        $skippedCount = 1  # MEGATOOL is always skipped
        
        Write-Log -Message "=================================================================================" -Level "INFO" -Component "SUMMARY"
        Write-Log -Message "SUMMARY STATISTICS" -Level "INFO" -Component "SUMMARY"
        Write-Log -Message "- Variables modified - $modifiedCount" -Level "INFO" -Component "SUMMARY"
        Write-Log -Message "- Variables not found - $notFoundCount" -Level "INFO" -Component "SUMMARY"
        Write-Log -Message "- Variables skipped - $skippedCount (MEGATOOL)" -Level "INFO" -Component "SUMMARY"
        Write-Log -Message "- Total variables processed - $($modifiedCount + $notFoundCount + $skippedCount)" -Level "INFO" -Component "SUMMARY"
        Write-Log -Message "=================================================================================" -Level "INFO" -Component "SUMMARY"
        
        Write-ColoredOutput "`nModifications Summary:" "Magenta" "INFO" "SUMMARY"
        Write-ColoredOutput "- Variables modified: $modifiedCount" "Green" "SUCCESS" "SUMMARY"
        Write-ColoredOutput "- Variables not found: $notFoundCount" "Yellow" "WARNING" "SUMMARY"
        Write-ColoredOutput "- Variables skipped: $skippedCount (MEGATOOL)" "Cyan" "INFO" "SUMMARY"
        
        Write-FunctionLog -FunctionName "Write-ModificationsSummary" -Action "EXIT" -Details "Summary written"
    }
    catch {
        Write-Log -Message "Error writing modifications summary: $($_.Exception.Message)" -Level "ERROR" -Component "SUMMARY"
        Write-FunctionLog -FunctionName "Write-ModificationsSummary" -Action "ERROR" -Details $_.Exception.Message
    }
}

# Function to update makefile configuration
function Update-MakefileConfiguration {
    param(
        [string]$BaseRootPath
    )
    
    Write-FunctionLog -FunctionName "Update-MakefileConfiguration" -Action "ENTER" -Details "BaseRootPath: $BaseRootPath"
    
    Write-ColoredOutput "`n=== Makefile Configuration Update ===" "Magenta" "INFO" "Update-MakefileConfiguration"
    
    try {
        # Validate installation and get makefile path
        $makefilePath = Test-InstallationPath $Global:MakefilePath
        
        # Backup the makefile
        $backupPath = Backup-Makefile $makefilePath
        
        # Discover tool paths
        $toolPaths = Get-ToolPaths $BaseRootPath
        
        if ($toolPaths.Keys.Count -eq 0) {
            Write-ColoredOutput "No tools found - makefile will not be modified" "Yellow" "WARNING" "Update-MakefileConfiguration"
            Write-Log -Message "No tools found for modification" -Level "WARNING" -Component "Update-MakefileConfiguration"
        }
        else {
            # Update the makefile
            $modificationsCount = Update-Makefile $makefilePath $toolPaths
            
            Write-ColoredOutput "Makefile configuration update completed!" "Green" "SUCCESS" "Update-MakefileConfiguration"
            Write-ColoredOutput "Backup created: $backupPath" "Cyan" "INFO" "Update-MakefileConfiguration"
            Write-ColoredOutput "Modifications made: $modificationsCount" "Green" "SUCCESS" "Update-MakefileConfiguration"
        }
        
        Write-FunctionLog -FunctionName "Update-MakefileConfiguration" -Action "EXIT" -Details "Configuration update completed"
        
    }
    catch {
        Write-ColoredOutput "Error during makefile configuration update: $($_.Exception.Message)" "Red" "ERROR" "Update-MakefileConfiguration"
        Write-FunctionLog -FunctionName "Update-MakefileConfiguration" -Action "ERROR" -Details $_.Exception.Message
        throw
    }
}

# Main script
try {
    Write-Host "=== GameShell65 - Makefile Configuration Updater ===" -ForegroundColor Magenta
    
    # Detect base root path and initialize all paths
    $baseRoot = Get-BaseRootPath $InstallationPath
    Initialize-Paths $baseRoot
    
    # Initialize log file
    try {
        # Create or clear the log file
        $logHeader = @"
================================================================================
GameShell65 - Makefile Configuration Update Log
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Script Path: $($MyInvocation.MyCommand.Path)
Base Root Path: $Global:BaseRootPath
Makefile Path: $Global:MakefilePath
Log Directory: $Global:LogDirectory
Temp Directory: $Global:TempWorkDirectory
Provided InstallationPath Parameter: $InstallationPath
Provided TempDirectory Parameter: $TempDirectory
PowerShell Version: $($PSVersionTable.PSVersion)
OS Version: $([System.Environment]::OSVersion.VersionString)
User: $([System.Environment]::UserName)
Computer: $([System.Environment]::MachineName)
================================================================================

"@
        $logHeader | Out-File -FilePath $Global:LogFile -Encoding UTF8 -Force
        Write-Log -Message "Log file initialized" -Level "INFO" -Component "INIT"
    }
    catch {
        Write-Host "Warning: Could not initialize log file: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    Write-ColoredOutput "Base root directory: $Global:BaseRootPath" "Cyan" "INFO" "MAIN"
    Write-Log -Message "Script execution started" -Level "INFO" -Component "MAIN"
    Write-Log -Message "Parameters - InstallationPath: $InstallationPath, TempDirectory: $TempDirectory" -Level "INFO" -Component "MAIN"
    
    # Check if script is running as administrator
    Write-Log -Message "Checking administrator privileges" -Level "INFO" -Component "MAIN"
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-ColoredOutput "ERROR: This script must be run as administrator!" "Red" "ERROR" "MAIN"
        Write-Log -Message "FATAL: Script not running as administrator" -Level "ERROR" -Component "MAIN"
        exit 1
    }
    Write-Log -Message "Administrator privileges confirmed" -Level "SUCCESS" -Component "MAIN"
    
    # Update makefile configuration
    Update-MakefileConfiguration $Global:BaseRootPath
    
    # Write summary
    Write-ModificationsSummary
    
    # Mark script as succeeded
    $Global:ScriptSucceeded = $true
    
    Write-ColoredOutput "`n=== Configuration update completed successfully! ===" "Green" "SUCCESS" "MAIN"
    Write-ColoredOutput "Check the log file for detailed modification information: $Global:LogFile" "Cyan" "INFO" "MAIN"
    
    $scriptEndTime = Get-Date
    $totalDuration = ($scriptEndTime - $Global:LogStartTime).TotalSeconds
    Write-Log -Message "Script completed successfully in $([math]::Round($totalDuration, 2)) seconds" -Level "SUCCESS" -Component "MAIN"
    Write-Log -Message "Log file location: $Global:LogFile" -Level "INFO" -Component "MAIN"
}
catch {
    Write-ColoredOutput "`nFATAL ERROR: $($_.Exception.Message)" "Red" "ERROR" "MAIN"
    Write-ColoredOutput "Configuration update failed." "Red" "ERROR" "MAIN"
    Write-Log -Message "FATAL ERROR: $($_.Exception.Message)" -Level "ERROR" -Component "MAIN"
    Write-Log -Message "Full exception: $($_.Exception | Out-String)" -Level "ERROR" -Component "MAIN"
    
    $scriptEndTime = Get-Date
    $totalDuration = ($scriptEndTime - $Global:LogStartTime).TotalSeconds
    Write-Log -Message "Script failed after $([math]::Round($totalDuration, 2)) seconds" -Level "ERROR" -Component "MAIN"
    
    exit 1
}
finally {
    # Clean up temporary directory only on success
    try {
        if ($Global:TempWorkDirectory -and (Test-Path $Global:TempWorkDirectory)) {
            if ($Global:ScriptSucceeded) {
                Remove-Item -Path $Global:TempWorkDirectory -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log -Message "Temporary directory cleaned up: $Global:TempWorkDirectory" -Level "INFO" -Component "CLEANUP"
                Write-Host "Temporary directory removed: $Global:TempWorkDirectory" -ForegroundColor Cyan
            }
            else {
                Write-Log -Message "Temporary directory preserved for debugging (script failed): $Global:TempWorkDirectory" -Level "WARNING" -Component "CLEANUP"
                Write-Host "Temporary directory preserved for debugging: $Global:TempWorkDirectory" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Log -Message "Warning: Could not process temporary directory cleanup: $($_.Exception.Message)" -Level "WARNING" -Component "CLEANUP"
        Write-Host "Warning: Could not process temporary directory cleanup: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Final log entry
    Write-Log -Message "Script execution ended" -Level "INFO" -Component "MAIN"
    Write-Log -Message "================================================================================`n" -Level "INFO" -Component "MAIN"
}