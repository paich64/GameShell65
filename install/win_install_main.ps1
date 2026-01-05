#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory=$true)]
    [string]$InstallationPath,
    
    [Parameter(Mandatory=$false)]
    [string]$TempDirectory = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ScriptsPath = "."
)

# Configuration
$ErrorActionPreference = "Continue"  # Continue execution even if one script fails
$ProgressPreference = "SilentlyContinue"

# Initialize logging
$LogDirectory = Join-Path (Get-Location) "log"
$LogFile = Join-Path $LogDirectory "installGameShell65.log"

# Create the log directory if it doesn't exist
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
    $LogFile = Join-Path (Get-Location) "installGameShell65.log"
}

$Global:LogStartTime = Get-Date

# EXHAUSTIVE LIST OF INSTALLATION SCRIPTS TO EXECUTE IN ORDER
$InstallationScripts = @(
    "installGameShell65_7zip.ps1",
    "installGameShell65_nodejs.ps1",
    "installGameShell65_jdk.ps1", 
    "installGameShell65_kickass.ps1",
    "installGameShell65_git.ps1",
    "installGameShell65_m65tools.ps1",
    "installGameShell65_MinGW-w64.ps1",
    "installGameShell65_vice.ps1", 
    "installGameShell65_xemu.ps1",
    "installGameShell65_repo.ps1",
    "installGameShell65_cygwindll.ps1",
    "installGameShell65_mega65rom.ps1",
    "update_makefile.ps1"
)

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
        Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
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
            "DarkGray" { $LogLevel = "DEBUG" }
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

# Function to refresh PATH environment variable from registry
function Update-EnvironmentPath {
    Write-FunctionLog -FunctionName "Update-EnvironmentPath" -Action "ENTER"
    
    Write-ColoredOutput "    [INFO] Refreshing PATH environment variable..." "Yellow" "INFO" "Update-EnvironmentPath"
    
    try {
        # Get machine and user PATH from registry
        $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        
        Write-Log -Message "Retrieved machine PATH length: $($machinePath.Length) chars" -Level "DEBUG" -Component "Update-EnvironmentPath"
        Write-Log -Message "Retrieved user PATH length: $($userPath.Length) chars" -Level "DEBUG" -Component "Update-EnvironmentPath"
        
        # Combine machine and user PATH
        $combinedPath = @()
        if ($machinePath) { $combinedPath += $machinePath -split ";" }
        if ($userPath) { $combinedPath += $userPath -split ";" }
        
        # Remove empty entries and duplicates, preserve order
        $cleanPath = @()
        foreach ($path in $combinedPath) {
            $trimmedPath = $path.Trim()
            if ($trimmedPath -and $cleanPath -notcontains $trimmedPath) {
                $cleanPath += $trimmedPath
            }
        }
        
        # Update current session PATH
        $env:PATH = $cleanPath -join ";"
        
        Write-ColoredOutput "    [OK] PATH refreshed successfully" "Green" "SUCCESS" "Update-EnvironmentPath"
        Write-Log -Message "PATH refreshed - Final PATH length: $($env:PATH.Length) chars" -Level "SUCCESS" -Component "Update-EnvironmentPath"
        Write-FunctionLog -FunctionName "Update-EnvironmentPath" -Action "EXIT" -Details "Success"
        return $true
    }
    catch {
        Write-ColoredOutput "    [WARNING] Could not refresh PATH: $($_.Exception.Message)" "Yellow" "WARNING" "Update-EnvironmentPath"
        Write-Log -Message "PATH refresh failed: $($_.Exception.Message)" -Level "ERROR" -Component "Update-EnvironmentPath"
        Write-FunctionLog -FunctionName "Update-EnvironmentPath" -Action "ERROR" -Details $_.Exception.Message
        return $false
    }
}

# Function to format execution time
function Format-ExecutionTime {
    param([TimeSpan]$TimeSpan)
    
    if ($TimeSpan.TotalHours -ge 1) {
        return "{0:hh\:mm\:ss}" -f $TimeSpan
    } elseif ($TimeSpan.TotalMinutes -ge 1) {
        return "{0:mm\:ss}" -f $TimeSpan
    } else {
        return "{0:ss}s" -f $TimeSpan
    }
}

# Function to validate script exists and has correct parameters
function Test-InstallationScript {
    param([string]$ScriptPath)
    
    Write-FunctionLog -FunctionName "Test-InstallationScript" -Action "ENTER" -Details "ScriptPath: $ScriptPath"
    
    if (-not (Test-Path $ScriptPath)) {
        Write-ColoredOutput "    [FAIL] Script file not found: $ScriptPath" "Red" "ERROR" "Test-InstallationScript"
        Write-Log -Message "Script validation failed - File not found: $ScriptPath" -Level "ERROR" -Component "Test-InstallationScript"
        Write-FunctionLog -FunctionName "Test-InstallationScript" -Action "EXIT" -Details "File not found"
        return $false
    }
    
    try {
        $scriptContent = Get-Content -Path $ScriptPath -Raw
        Write-Log -Message "Script content loaded - Size: $($scriptContent.Length) chars" -Level "DEBUG" -Component "Test-InstallationScript"
        
        # Check if script has the expected parameters
        $hasInstallationPath = $scriptContent -match '\[Parameter\([^\]]*Mandatory\s*=\s*\$true[^\]]*\)\]\s*\[string\]\$InstallationPath'
        
        if ($hasInstallationPath) {
            Write-ColoredOutput "    [OK] Script validated successfully" "Green" "SUCCESS" "Test-InstallationScript"
            Write-Log -Message "Script validation successful - InstallationPath parameter found" -Level "SUCCESS" -Component "Test-InstallationScript"
            Write-FunctionLog -FunctionName "Test-InstallationScript" -Action "EXIT" -Details "Validation successful"
            return $true
        } else {
            Write-ColoredOutput "    [FAIL] InstallationPath parameter not found or not mandatory" "Red" "ERROR" "Test-InstallationScript"
            Write-Log -Message "Script validation failed - InstallationPath parameter missing or not mandatory" -Level "ERROR" -Component "Test-InstallationScript"
            Write-FunctionLog -FunctionName "Test-InstallationScript" -Action "EXIT" -Details "Parameter validation failed"
            return $false
        }
    }
    catch {
        Write-ColoredOutput "    [ERROR] Error analyzing script: $($_.Exception.Message)" "Red" "ERROR" "Test-InstallationScript"
        Write-Log -Message "Script analysis error: $($_.Exception.Message)" -Level "ERROR" -Component "Test-InstallationScript"
        Write-FunctionLog -FunctionName "Test-InstallationScript" -Action "ERROR" -Details $_.Exception.Message
        return $false
    }
}

# Function to analyze post-installation environment dynamically
function Get-PostInstallationEnvironment {
    param([string]$InstallationPath)
    
    Write-FunctionLog -FunctionName "Get-PostInstallationEnvironment" -Action "ENTER" -Details "InstallationPath: $InstallationPath"
    
    Write-ColoredOutput "Analyzing post-installation environment..." "Yellow" "INFO" "Get-PostInstallationEnvironment"
    Write-Log -Message "Starting post-installation environment analysis" -Level "INFO" -Component "Get-PostInstallationEnvironment"
    
    $environmentInfo = @{
        EnvironmentVariables = @()
        PathDirectories = @()
        DirectoriesCreated = @()
    }
    
    try {
        # Get all current environment variables and filter those pointing to our installation path
        $allEnvVars = [Environment]::GetEnvironmentVariables("Machine")
        Write-Log -Message "Retrieved $($allEnvVars.Count) machine environment variables" -Level "DEBUG" -Component "Get-PostInstallationEnvironment"
        
        foreach ($envVar in $allEnvVars.GetEnumerator()) {
            if (-not [string]::IsNullOrWhiteSpace($envVar.Value) -and 
                $envVar.Value.ToString().StartsWith($InstallationPath, [StringComparison]::OrdinalIgnoreCase)) {
                $environmentInfo.EnvironmentVariables += @{
                    Name = $envVar.Key
                    Value = $envVar.Value
                }
                Write-Log -Message "Found related environment variable: $($envVar.Key) = $($envVar.Value)" -Level "DEBUG" -Component "Get-PostInstallationEnvironment"
            }
        }
        
        # Analyze PATH to find directories that were added within our installation path
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        $pathDirs = $currentPath -split ";" | Where-Object { 
            -not [string]::IsNullOrWhiteSpace($_) -and 
            $_.StartsWith($InstallationPath, [StringComparison]::OrdinalIgnoreCase)
        }
        $environmentInfo.PathDirectories = $pathDirs | Sort-Object -Unique
        Write-Log -Message "Found $($environmentInfo.PathDirectories.Count) PATH directories related to installation" -Level "DEBUG" -Component "Get-PostInstallationEnvironment"
        
        # Discover all directories created under the installation path
        if (Test-Path $InstallationPath) {
            $allDirs = Get-ChildItem -Path $InstallationPath -Directory -Recurse -ErrorAction SilentlyContinue
            $environmentInfo.DirectoriesCreated = $allDirs | ForEach-Object { $_.FullName } | Sort-Object -Unique
            Write-Log -Message "Found $($environmentInfo.DirectoriesCreated.Count) directories under installation path" -Level "DEBUG" -Component "Get-PostInstallationEnvironment"
        }
        
        Write-Log -Message "Environment analysis completed successfully" -Level "SUCCESS" -Component "Get-PostInstallationEnvironment"
        Write-FunctionLog -FunctionName "Get-PostInstallationEnvironment" -Action "EXIT" -Details "Success"
        return $environmentInfo
    }
    catch {
        Write-ColoredOutput "Warning: Could not fully analyze environment: $($_.Exception.Message)" "Yellow" "WARNING" "Get-PostInstallationEnvironment"
        Write-Log -Message "Environment analysis warning: $($_.Exception.Message)" -Level "WARNING" -Component "Get-PostInstallationEnvironment"
        Write-FunctionLog -FunctionName "Get-PostInstallationEnvironment" -Action "ERROR" -Details $_.Exception.Message
        return $environmentInfo
    }
}

# Function to execute a single installation script
function Invoke-InstallationScript {
    param(
        [string]$ScriptPath,
        [string]$InstallationPath,
        [string]$TempDirectory
    )
    
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
    $startTime = Get-Date
    
    # Determine the path of the individual log file
    $scriptLogFileName = "$scriptName.log"
    $scriptLogPath = Join-Path $LogDirectory $scriptLogFileName
    
    Write-FunctionLog -FunctionName "Invoke-InstallationScript" -Action "ENTER" -Details "Script: $scriptName, Path: $ScriptPath"
    
    Write-ColoredOutput "`n=== Executing: $scriptName ===" "Magenta" "INFO" "Invoke-InstallationScript"
    Write-ColoredOutput "Script: $ScriptPath" "Cyan" "INFO" "Invoke-InstallationScript"
    Write-ColoredOutput "Started at: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Cyan" "INFO" "Invoke-InstallationScript"
    Write-ColoredOutput "Individual log file: $scriptLogPath" "Cyan" "INFO" "Invoke-InstallationScript"
    Write-Log -Message "Starting script execution: $scriptName" -Level "INFO" -Component "Invoke-InstallationScript"
    Write-Log -Message "Script path: $ScriptPath" -Level "DEBUG" -Component "Invoke-InstallationScript"
    Write-Log -Message "Installation path: $InstallationPath" -Level "DEBUG" -Component "Invoke-InstallationScript"
    Write-Log -Message "Temp directory: $TempDirectory" -Level "DEBUG" -Component "Invoke-InstallationScript"
    Write-Log -Message "Individual log file: $scriptLogPath" -Level "INFO" -Component "Invoke-InstallationScript"
    
    # Refresh PATH before executing each script
    Write-Log -Message "Refreshing PATH before script execution" -Level "DEBUG" -Component "Invoke-InstallationScript"
    Update-EnvironmentPath | Out-Null
    
    try {
        # Prepare arguments
        $argumentString = "-InstallationPath `"$InstallationPath`""
        if (-not [string]::IsNullOrWhiteSpace($TempDirectory)) {
            $argumentString += " -TempDirectory `"$TempDirectory`""
        }
        
        Write-Log -Message "Arguments prepared: $argumentString" -Level "DEBUG" -Component "Invoke-InstallationScript"
        
        # Use Start-Process to capture exit codes properly
        $processArgs = @{
            FilePath = "powershell.exe"
            ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"") + $argumentString.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
            WorkingDirectory = (Split-Path $ScriptPath -Parent)
            NoNewWindow = $true
            Wait = $true
            PassThru = $true
        }
        
        Write-Log -Message "Starting PowerShell process with arguments: $($processArgs.ArgumentList -join ' ')" -Level "DEBUG" -Component "Invoke-InstallationScript"
        $process = Start-Process @processArgs
        
        $endTime = Get-Date
        $executionTime = $endTime - $startTime
        
        Write-Log -Message "Process completed with exit code: $($process.ExitCode)" -Level "INFO" -Component "Invoke-InstallationScript"
        Write-Log -Message "Execution time: $(Format-ExecutionTime $executionTime)" -Level "INFO" -Component "Invoke-InstallationScript"
        
        # Check if the individual log file exists after execution
        $logFileExists = Test-Path $scriptLogPath
        $logFileSize = 0
        if ($logFileExists) {
            $logFileSize = (Get-Item $scriptLogPath).Length
            Write-Log -Message "Individual log file created: $scriptLogPath (Size: $logFileSize bytes)" -Level "INFO" -Component "Invoke-InstallationScript"
        } else {
            Write-Log -Message "Individual log file not found: $scriptLogPath" -Level "WARNING" -Component "Invoke-InstallationScript"
        }
        
        if ($process.ExitCode -eq 0) {
            Write-ColoredOutput "[SUCCESS] $scriptName completed successfully" "Green" "SUCCESS" "Invoke-InstallationScript"
            Write-ColoredOutput "  Execution time: $(Format-ExecutionTime $executionTime)" "Green" "SUCCESS" "Invoke-InstallationScript"
            
            # Display individual log file information
            if ($logFileExists) {
                Write-ColoredOutput "  Individual log file: $scriptLogPath" "Green" "SUCCESS" "Invoke-InstallationScript"
                Write-ColoredOutput "  Log file size: $([math]::Round($logFileSize / 1KB, 2)) KB" "Green" "SUCCESS" "Invoke-InstallationScript"
            } else {
                Write-ColoredOutput "  Warning: Individual log file not found at $scriptLogPath" "Yellow" "WARNING" "Invoke-InstallationScript"
            }
            
            # Refresh PATH again after successful installation
            Write-ColoredOutput "  Refreshing PATH after installation..." "Yellow" "INFO" "Invoke-InstallationScript"
            Write-Log -Message "Refreshing PATH after successful installation" -Level "DEBUG" -Component "Invoke-InstallationScript"
            Update-EnvironmentPath | Out-Null
            
            $result = @{
                ScriptName = $scriptName
                ScriptPath = $ScriptPath
                Success = $true
                StartTime = $startTime
                EndTime = $endTime
                ExecutionTime = $executionTime
                ErrorMessage = $null
                ExitCode = $process.ExitCode
                LogFile = $scriptLogPath
                LogFileExists = $logFileExists
                LogFileSize = $logFileSize
            }
            
            Write-Log -Message "Script execution successful: $scriptName" -Level "SUCCESS" -Component "Invoke-InstallationScript"
            Write-FunctionLog -FunctionName "Invoke-InstallationScript" -Action "EXIT" -Details "Success - Exit code: $($process.ExitCode), Log: $scriptLogPath"
            return $result
        } else {
            Write-ColoredOutput "[FAILED] $scriptName failed with exit code $($process.ExitCode)" "Red" "ERROR" "Invoke-InstallationScript"
            Write-ColoredOutput "  Execution time: $(Format-ExecutionTime $executionTime)" "Yellow" "WARNING" "Invoke-InstallationScript"
            
            # Display individual log file information even in case of failure
            if ($logFileExists) {
                Write-ColoredOutput "  Individual log file: $scriptLogPath" "Yellow" "WARNING" "Invoke-InstallationScript"
                Write-ColoredOutput "  Log file size: $([math]::Round($logFileSize / 1KB, 2)) KB" "Yellow" "WARNING" "Invoke-InstallationScript"
                Write-ColoredOutput "  Check the individual log file for detailed error information." "Yellow" "WARNING" "Invoke-InstallationScript"
            } else {
                Write-ColoredOutput "  Warning: Individual log file not found at $scriptLogPath" "Yellow" "WARNING" "Invoke-InstallationScript"
            }
            
            $result = @{
                ScriptName = $scriptName
                ScriptPath = $ScriptPath
                Success = $false
                StartTime = $startTime
                EndTime = $endTime
                ExecutionTime = $executionTime
                ErrorMessage = "Script exited with code $($process.ExitCode)"
                ExitCode = $process.ExitCode
                LogFile = $scriptLogPath
                LogFileExists = $logFileExists
                LogFileSize = $logFileSize
            }
            
            Write-Log -Message "Script execution failed: $scriptName - Exit code: $($process.ExitCode)" -Level "ERROR" -Component "Invoke-InstallationScript"
            Write-FunctionLog -FunctionName "Invoke-InstallationScript" -Action "EXIT" -Details "Failed - Exit code: $($process.ExitCode), Log: $scriptLogPath"
            return $result
        }
    }
    catch {
        $endTime = Get-Date
        $executionTime = $endTime - $startTime
        
        Write-ColoredOutput "[ERROR] $scriptName failed with exception" "Red" "ERROR" "Invoke-InstallationScript"
        Write-ColoredOutput "  Error: $($_.Exception.Message)" "Red" "ERROR" "Invoke-InstallationScript"
        Write-ColoredOutput "  Execution time: $(Format-ExecutionTime $executionTime)" "Yellow" "WARNING" "Invoke-InstallationScript"
        
        # Check log file even in case of exception
        $logFileExists = Test-Path $scriptLogPath
        $logFileSize = 0
        if ($logFileExists) {
            $logFileSize = (Get-Item $scriptLogPath).Length
            Write-ColoredOutput "  Individual log file: $scriptLogPath" "Yellow" "WARNING" "Invoke-InstallationScript"
            Write-ColoredOutput "  Log file size: $([math]::Round($logFileSize / 1KB, 2)) KB" "Yellow" "WARNING" "Invoke-InstallationScript"
            Write-ColoredOutput "  Check the individual log file for detailed error information." "Yellow" "WARNING" "Invoke-InstallationScript"
        } else {
            Write-ColoredOutput "  Warning: Individual log file not found at $scriptLogPath" "Yellow" "WARNING" "Invoke-InstallationScript"
        }
        
        # SECURE RETURN WITH ALL REQUIRED PROPERTIES
        $result = @{
            ScriptName = $scriptName
            ScriptPath = $ScriptPath
            Success = $false
            StartTime = $startTime
            EndTime = $endTime
            ExecutionTime = $executionTime
            ErrorMessage = $_.Exception.Message
            ExitCode = 1
            LogFile = $scriptLogPath
            LogFileExists = $logFileExists
            LogFileSize = $logFileSize
        }
        
        Write-Log -Message "Script execution exception: $scriptName - $($_.Exception.Message)" -Level "ERROR" -Component "Invoke-InstallationScript"
        Write-Log -Message "Full exception details: $($_.Exception | Out-String)" -Level "ERROR" -Component "Invoke-InstallationScript"
        Write-FunctionLog -FunctionName "Invoke-InstallationScript" -Action "ERROR" -Details "$($_.Exception.Message), Log: $scriptLogPath"
        return $result
    }
}

# Function to debug results collection - CORRECTED VERSION FOR HASHTABLE
function Debug-ResultsCollection {
    param([array]$Results)
    
    Write-FunctionLog -FunctionName "Debug-ResultsCollection" -Action "ENTER" -Details "Results count: $($Results.Count)"
    
    Write-ColoredOutput "`n=== DEBUG: Results Collection ===" "Magenta" "DEBUG" "Debug-ResultsCollection"
    Write-ColoredOutput "Results Count: $($Results.Count)" "Cyan" "DEBUG" "Debug-ResultsCollection"
    Write-Log -Message "Debug results collection - Total results: $($Results.Count)" -Level "DEBUG" -Component "Debug-ResultsCollection"
    
    if ($Results.Count -gt 0) {
        for ($i = 0; $i -lt $Results.Count; $i++) {
            $result = $Results[$i]
            Write-ColoredOutput "Result [$i]:" "Yellow" "DEBUG" "Debug-ResultsCollection"
            Write-Log -Message "Analyzing result [$i]" -Level "DEBUG" -Component "Debug-ResultsCollection"
            
            if ($result -ne $null) {
                Write-ColoredOutput "  Type: $($result.GetType().FullName)" "Gray" "DEBUG" "Debug-ResultsCollection"
                Write-Log -Message "  Result [$i] type: $($result.GetType().FullName)" -Level "DEBUG" -Component "Debug-ResultsCollection"
                
                # FOR HASHTABLE, DISPLAY KEYS AND VALUES
                if ($result -is [System.Collections.Hashtable]) {
                    Write-ColoredOutput "  Hashtable Contents:" "Gray" "DEBUG" "Debug-ResultsCollection"
                    foreach ($key in $result.Keys) {
                        Write-ColoredOutput "    $key : $($result[$key])" "DarkGray" "DEBUG" "Debug-ResultsCollection"
                        Write-Log -Message "    Result [$i] $key : $($result[$key])" -Level "DEBUG" -Component "Debug-ResultsCollection"
                    }
                    
                    # Specific verifications FOR HASHTABLE
                    $hasStartTime = $result.ContainsKey('StartTime')
                    $hasEndTime = $result.ContainsKey('EndTime')
                    Write-ColoredOutput "  Has StartTime: $hasStartTime" "Green" "DEBUG" "Debug-ResultsCollection"
                    Write-ColoredOutput "  Has EndTime: $hasEndTime" "Green" "DEBUG" "Debug-ResultsCollection"
                    Write-Log -Message "  Result [$i] has StartTime: $hasStartTime, has EndTime: $hasEndTime" -Level "DEBUG" -Component "Debug-ResultsCollection"
                } else {
                    Write-ColoredOutput "  Properties:" "Gray" "DEBUG" "Debug-ResultsCollection"
                    $result.PSObject.Properties | ForEach-Object {
                        Write-ColoredOutput "    $($_.Name): $($_.Value)" "DarkGray" "DEBUG" "Debug-ResultsCollection"
                        Write-Log -Message "    Result [$i] property $($_.Name): $($_.Value)" -Level "DEBUG" -Component "Debug-ResultsCollection"
                    }
                }
            } else {
                Write-ColoredOutput "  [NULL OBJECT]" "Red" "ERROR" "Debug-ResultsCollection"
                Write-Log -Message "  Result [$i] is NULL" -Level "ERROR" -Component "Debug-ResultsCollection"
            }
        }
    } else {
        Write-ColoredOutput "  [EMPTY COLLECTION]" "Red" "WARNING" "Debug-ResultsCollection"
        Write-Log -Message "Results collection is empty" -Level "WARNING" -Component "Debug-ResultsCollection"
    }
    Write-ColoredOutput "=== END DEBUG ===" "Magenta" "DEBUG" "Debug-ResultsCollection"
    Write-FunctionLog -FunctionName "Debug-ResultsCollection" -Action "EXIT" -Details "Debug completed"
}

# Function to generate final report - CORRECTED VERSION FOR HASHTABLE
function Write-InstallationReport {
    param(
        [array]$Results,
        [array]$ConfiguredScripts,
        [string]$InstallationPath
    )
    
    Write-FunctionLog -FunctionName "Write-InstallationReport" -Action "ENTER" -Details "Results: $($Results.Count), Scripts: $($ConfiguredScripts.Count)"
    
    # DEFENSIVE DATA HANDLING - HASHTABLE VERSION
    try {
        Write-ColoredOutput "`n[DEBUG] Starting report generation..." "Magenta" "DEBUG" "Write-InstallationReport"
        Write-ColoredOutput "[DEBUG] Results received: $($Results.Count) items" "Magenta" "DEBUG" "Write-InstallationReport"
        Write-Log -Message "Starting installation report generation" -Level "INFO" -Component "Write-InstallationReport"
        Write-Log -Message "Input data - Results: $($Results.Count), Configured scripts: $($ConfiguredScripts.Count)" -Level "DEBUG" -Component "Write-InstallationReport"
        
        if ($null -eq $Results -or $Results.Count -eq 0) {
            Write-ColoredOutput "[WARNING] No execution results available for report generation" "Yellow" "WARNING" "Write-InstallationReport"
            Write-Log -Message "No execution results available for report generation" -Level "WARNING" -Component "Write-InstallationReport"
            $totalExecutionTime = [TimeSpan]::Zero
            $successfulInstalls = @()
            $failedInstalls = @()
            $skippedInstalls = $ConfiguredScripts.Count
        }
        else {
            # CORRECTED FILTERING FOR HASHTABLE
            $validResults = @($Results | Where-Object { 
                $_ -ne $null -and 
                $_.ContainsKey("StartTime") -and       # CORRECTION FOR HASHTABLE
                $_.ContainsKey("EndTime") -and         # CORRECTION FOR HASHTABLE
                $_["StartTime"] -ne $null -and         # HASHTABLE ACCESS
                $_["EndTime"] -ne $null                # HASHTABLE ACCESS
            })
            
            Write-ColoredOutput "[DEBUG] Valid results with timing: $($validResults.Count)" "Magenta" "DEBUG" "Write-InstallationReport"
            Write-Log -Message "Valid results with timing data: $($validResults.Count)" -Level "DEBUG" -Component "Write-InstallationReport"
            
            if ($validResults.Count -gt 0) {
                # HASHTABLE ACCESS FOR CALCULATIONS
                $totalStartTime = ($validResults | ForEach-Object { $_["StartTime"] } | Measure-Object -Minimum).Minimum
                $totalEndTime = ($validResults | ForEach-Object { $_["EndTime"] } | Measure-Object -Maximum).Maximum
                $totalExecutionTime = $totalEndTime - $totalStartTime
                Write-ColoredOutput "[DEBUG] Total execution time calculated: $(Format-ExecutionTime $totalExecutionTime)" "Magenta" "DEBUG" "Write-InstallationReport"
                Write-Log -Message "Total execution time calculated: $(Format-ExecutionTime $totalExecutionTime)" -Level "INFO" -Component "Write-InstallationReport"
            }
            else {
                Write-ColoredOutput "[WARNING] No valid timing data found in results" "Yellow" "WARNING" "Write-InstallationReport"
                Write-Log -Message "No valid timing data found in results" -Level "WARNING" -Component "Write-InstallationReport"
                $totalExecutionTime = [TimeSpan]::Zero
            }
            
            # CORRECTED FILTERING FOR SUCCESS/FAILED
            $successfulInstalls = @($Results | Where-Object { $_ -ne $null -and $_["Success"] -eq $true })
            $failedInstalls = @($Results | Where-Object { $_ -ne $null -and $_["Success"] -eq $false })
            $skippedInstalls = $ConfiguredScripts.Count - $Results.Count
            
            Write-ColoredOutput "[DEBUG] Successful: $($successfulInstalls.Count), Failed: $($failedInstalls.Count), Skipped: $skippedInstalls" "Magenta" "DEBUG" "Write-InstallationReport"
            Write-Log -Message "Installation statistics - Successful: $($successfulInstalls.Count), Failed: $($failedInstalls.Count), Skipped: $skippedInstalls" -Level "INFO" -Component "Write-InstallationReport"
        }
    }
    catch {
        Write-ColoredOutput "[ERROR] Error in report calculation: $($_.Exception.Message)" "Red" "ERROR" "Write-InstallationReport"
        Write-ColoredOutput "[ERROR] Stack trace: $($_.ScriptStackTrace)" "Red" "ERROR" "Write-InstallationReport"
        Write-Log -Message "Error in report calculation: $($_.Exception.Message)" -Level "ERROR" -Component "Write-InstallationReport"
        Write-Log -Message "Full exception: $($_.Exception | Out-String)" -Level "ERROR" -Component "Write-InstallationReport"
        $totalExecutionTime = [TimeSpan]::Zero
        $successfulInstalls = @()
        $failedInstalls = @()
        $skippedInstalls = $ConfiguredScripts.Count
    }
    
    Write-ColoredOutput "`n" "White" "INFO" "Write-InstallationReport"
    Write-ColoredOutput "================================================================" "Cyan" "INFO" "Write-InstallationReport"
    Write-ColoredOutput "                    INSTALLATION REPORT                        " "Cyan" "INFO" "Write-InstallationReport"
    Write-ColoredOutput "================================================================" "Cyan" "INFO" "Write-InstallationReport"
    Write-Log -Message "Generating installation report" -Level "INFO" -Component "Write-InstallationReport"
    
    Write-ColoredOutput "`nSUMMARY:" "Yellow" "INFO" "Write-InstallationReport"
    Write-ColoredOutput "  Scripts configured: $($ConfiguredScripts.Count)" "White" "INFO" "Write-InstallationReport"
    Write-ColoredOutput "  Scripts executed: $($Results.Count)" "White" "INFO" "Write-InstallationReport"
    Write-ColoredOutput "  Scripts skipped: $skippedInstalls" "Yellow" "WARNING" "Write-InstallationReport"
    Write-ColoredOutput "  Successful installations: $($successfulInstalls.Count)" "Green" "SUCCESS" "Write-InstallationReport"
    Write-ColoredOutput "  Failed installations: $($failedInstalls.Count)" "Red" "ERROR" "Write-InstallationReport"
    Write-ColoredOutput "  Total execution time: $(Format-ExecutionTime $totalExecutionTime)" "White" "INFO" "Write-InstallationReport"
    Write-ColoredOutput "  Installation path: $InstallationPath" "White" "INFO" "Write-InstallationReport"
    
    Write-Log -Message "Report summary - Configured: $($ConfiguredScripts.Count), Executed: $($Results.Count), Skipped: $skippedInstalls, Successful: $($successfulInstalls.Count), Failed: $($failedInstalls.Count)" -Level "INFO" -Component "Write-InstallationReport"
    Write-Log -Message "Total execution time: $(Format-ExecutionTime $totalExecutionTime)" -Level "INFO" -Component "Write-InstallationReport"
    
    Write-ColoredOutput "`nCONFIGURED SCRIPTS EXECUTION STATUS:" "Yellow" "INFO" "Write-InstallationReport"
    for ($i = 0; $i -lt $ConfiguredScripts.Count; $i++) {
        $scriptName = $ConfiguredScripts[$i]
        $result = $Results | Where-Object { 
            $_ -ne $null -and 
            [System.IO.Path]::GetFileNameWithoutExtension($_["ScriptPath"]) -eq [System.IO.Path]::GetFileNameWithoutExtension($scriptName) 
        } | Select-Object -First 1
        
        if ($result) {
            $status = if ($result["Success"]) { "SUCCESS" } else { "FAILED" }
            $statusColor = if ($result["Success"]) { "Green" } else { "Red" }
            $statusLevel = if ($result["Success"]) { "SUCCESS" } else { "ERROR" }
            
            if ($result["ExecutionTime"]) {
                $duration = Format-ExecutionTime $result["ExecutionTime"]
            } else {
                $duration = "N/A"
            }
            Write-ColoredOutput "  $($i+1). [$status] $scriptName ($duration)" $statusColor $statusLevel "Write-InstallationReport"
            Write-Log -Message "Script $($i+1): [$status] $scriptName ($duration)" -Level $statusLevel -Component "Write-InstallationReport"
        } else {
            Write-ColoredOutput "  $($i+1). [SKIPPED] $scriptName (not found or invalid)" "Yellow" "WARNING" "Write-InstallationReport"
            Write-Log -Message "Script $($i+1): [SKIPPED] $scriptName (not found or invalid)" -Level "WARNING" -Component "Write-InstallationReport"
        }
    }
    
    if ($successfulInstalls.Count -gt 0) {
        Write-ColoredOutput "`nSUCCESSFUL INSTALLATIONS:" "Green" "SUCCESS" "Write-InstallationReport"
        Write-Log -Message "Listing successful installations:" -Level "INFO" -Component "Write-InstallationReport"
        foreach ($install in $successfulInstalls) {
            $duration = if ($install["ExecutionTime"]) { Format-ExecutionTime $install["ExecutionTime"] } else { "N/A" }
            Write-ColoredOutput "  [SUCCESS] $($install["ScriptName"]) ($duration)" "Green" "SUCCESS" "Write-InstallationReport"
            
            # Display individual log file information
            if ($install.ContainsKey("LogFile") -and $install["LogFileExists"]) {
                Write-ColoredOutput "    Log file: $($install["LogFile"]) ($([math]::Round($install["LogFileSize"] / 1KB, 2)) KB)" "Cyan" "INFO" "Write-InstallationReport"
                Write-Log -Message "  Successful: $($install["ScriptName"]) ($duration) - Log: $($install["LogFile"]) ($($install["LogFileSize"]) bytes)" -Level "SUCCESS" -Component "Write-InstallationReport"
            } else {
                Write-Log -Message "  Successful: $($install["ScriptName"]) ($duration) - No log file found" -Level "SUCCESS" -Component "Write-InstallationReport"
            }
        }
    }
    
    if ($failedInstalls.Count -gt 0) {
        Write-ColoredOutput "`nFAILED INSTALLATIONS:" "Red" "ERROR" "Write-InstallationReport"
        Write-Log -Message "Listing failed installations:" -Level "ERROR" -Component "Write-InstallationReport"
        foreach ($install in $failedInstalls) {
            $duration = if ($install["ExecutionTime"]) { Format-ExecutionTime $install["ExecutionTime"] } else { "N/A" }
            Write-ColoredOutput "  [FAILED] $($install["ScriptName"]) ($duration)" "Red" "ERROR" "Write-InstallationReport"
            Write-ColoredOutput "    Error: $($install["ErrorMessage"])" "Red" "ERROR" "Write-InstallationReport"
            Write-ColoredOutput "    Exit Code: $($install["ExitCode"])" "Red" "ERROR" "Write-InstallationReport"
            
            # Display individual log file information for failures
            if ($install.ContainsKey("LogFile")) {
                if ($install["LogFileExists"]) {
                    Write-ColoredOutput "    Log file: $($install["LogFile"]) ($([math]::Round($install["LogFileSize"] / 1KB, 2)) KB)" "Yellow" "WARNING" "Write-InstallationReport"
                    Write-ColoredOutput "    Check the log file above for detailed error information." "Yellow" "WARNING" "Write-InstallationReport"
                    Write-Log -Message "  Failed: $($install["ScriptName"]) ($duration) - Error: $($install["ErrorMessage"]) - Exit Code: $($install["ExitCode"]) - Log: $($install["LogFile"]) ($($install["LogFileSize"]) bytes)" -Level "ERROR" -Component "Write-InstallationReport"
                } else {
                    Write-ColoredOutput "    Expected log file: $($install["LogFile"]) (not found)" "Yellow" "WARNING" "Write-InstallationReport"
                    Write-Log -Message "  Failed: $($install["ScriptName"]) ($duration) - Error: $($install["ErrorMessage"]) - Exit Code: $($install["ExitCode"]) - Log file not found: $($install["LogFile"])" -Level "ERROR" -Component "Write-InstallationReport"
                }
            }
        }
        
        Write-ColoredOutput "`nTo retry failed installations individually:" "Yellow" "INFO" "Write-InstallationReport"
        Write-Log -Message "Retry commands for failed installations:" -Level "INFO" -Component "Write-InstallationReport"
        foreach ($install in $failedInstalls) {
            $retryCommand = "powershell -File `"$($install["ScriptPath"])`" -InstallationPath `"$InstallationPath`""
            Write-ColoredOutput "  $retryCommand" "Gray" "DEBUG" "Write-InstallationReport"
            Write-Log -Message "  Retry: $retryCommand" -Level "INFO" -Component "Write-InstallationReport"
        }
    }
    
    # Dynamic environment analysis - WITHOUT EXECUTABLES
    if ($successfulInstalls.Count -gt 0) {
        Write-Log -Message "Starting post-installation environment analysis" -Level "INFO" -Component "Write-InstallationReport"
        $envInfo = Get-PostInstallationEnvironment $InstallationPath
        
        Write-ColoredOutput "`nPOST-INSTALLATION ENVIRONMENT:" "Yellow" "INFO" "Write-InstallationReport"
        
        if ($envInfo.EnvironmentVariables.Count -gt 0) {
            Write-ColoredOutput "  Environment Variables Set:" "White" "INFO" "Write-InstallationReport"
            Write-Log -Message "Environment variables set: $($envInfo.EnvironmentVariables.Count)" -Level "INFO" -Component "Write-InstallationReport"
            foreach ($envVar in $envInfo.EnvironmentVariables) {
                Write-ColoredOutput "    $($envVar.Name) = $($envVar.Value)" "Gray" "DEBUG" "Write-InstallationReport"
                Write-Log -Message "  Env var: $($envVar.Name) = $($envVar.Value)" -Level "DEBUG" -Component "Write-InstallationReport"
            }
        }
        
        if ($envInfo.PathDirectories.Count -gt 0) {
            Write-ColoredOutput "  Directories Added to PATH:" "White" "INFO" "Write-InstallationReport"
            Write-Log -Message "PATH directories added: $($envInfo.PathDirectories.Count)" -Level "INFO" -Component "Write-InstallationReport"
            foreach ($pathDir in $envInfo.PathDirectories) {
                Write-ColoredOutput "    $pathDir" "Gray" "DEBUG" "Write-InstallationReport"
                Write-Log -Message "  PATH dir: $pathDir" -Level "DEBUG" -Component "Write-InstallationReport"
            }
        }
        
        Write-ColoredOutput "`nIMPORTANT: PATH has been refreshed during execution." "Green" "SUCCESS" "Write-InstallationReport"
        Write-Log -Message "PATH refresh completed during execution" -Level "SUCCESS" -Component "Write-InstallationReport"
    }
    
    Write-ColoredOutput "`n================================================================" "Cyan" "INFO" "Write-InstallationReport"
    Write-Log -Message "Installation report generation completed" -Level "SUCCESS" -Component "Write-InstallationReport"
    
    # Return overall success status
    $overallSuccess = $failedInstalls.Count -eq 0
    Write-Log -Message "Overall installation success: $overallSuccess" -Level "INFO" -Component "Write-InstallationReport"
    Write-FunctionLog -FunctionName "Write-InstallationReport" -Action "EXIT" -Details "Success: $overallSuccess"
    return $overallSuccess
}

# Initialize log file
try {
    # Create or clear the log file
    $logHeader = @"
================================================================================
GameShell65 - Master Installation Log
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Script Path: $($MyInvocation.MyCommand.Path)
Installation Path: $InstallationPath
Temp Directory: $TempDirectory
Scripts Path: $ScriptsPath
PowerShell Version: $($PSVersionTable.PSVersion)
OS Version: $([System.Environment]::OSVersion.VersionString)
User: $([System.Environment]::UserName)
Computer: $([System.Environment]::MachineName)
================================================================================

"@
    $logHeader | Out-File -FilePath $LogFile -Encoding UTF8 -Force
    Write-Log -Message "Log file initialized" -Level "INFO" -Component "INIT"
    Write-Log -Message "Log file path: $LogFile" -Level "INFO" -Component "INIT"
}
catch {
    Write-Host "Warning: Could not initialize log file: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Main script
try {
    $overallStartTime = Get-Date
    
    Write-ColoredOutput "================================================================" "Magenta" "INFO" "MAIN"
    Write-ColoredOutput "               GameShell65 Master Installer                    " "Magenta" "INFO" "MAIN"
    Write-ColoredOutput "================================================================" "Magenta" "INFO" "MAIN"
    Write-ColoredOutput "Installation Path: $InstallationPath" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "Scripts Path: $ScriptsPath" "Cyan" "INFO" "MAIN"
    if (-not [string]::IsNullOrWhiteSpace($TempDirectory)) {
        Write-ColoredOutput "Temp Directory: $TempDirectory" "Cyan" "INFO" "MAIN"
    }
    Write-ColoredOutput "Started at: $($overallStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" "Cyan" "INFO" "MAIN"
    Write-ColoredOutput "Master log file: $LogFile" "Cyan" "INFO" "MAIN"
    
    Write-Log -Message "GameShell65 Master Installer started" -Level "INFO" -Component "MAIN"
    Write-Log -Message "Parameters - InstallationPath: $InstallationPath, TempDirectory: $TempDirectory, ScriptsPath: $ScriptsPath" -Level "INFO" -Component "MAIN"
    
    # Check if script is running as administrator
    Write-Log -Message "Checking administrator privileges" -Level "DEBUG" -Component "MAIN"
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-ColoredOutput "ERROR: This script must be run as administrator!" "Red" "ERROR" "MAIN"
        Write-Log -Message "FATAL: Script not running as administrator" -Level "ERROR" -Component "MAIN"
        exit 1
    }
    Write-Log -Message "Administrator privileges confirmed" -Level "SUCCESS" -Component "MAIN"
    
    # Validate installation path
    Write-Log -Message "Validating installation path" -Level "DEBUG" -Component "MAIN"
    if (-not [System.IO.Path]::IsPathRooted($InstallationPath)) {
        Write-ColoredOutput "ERROR: InstallationPath must be an absolute path!" "Red" "ERROR" "MAIN"
        Write-Log -Message "FATAL: InstallationPath is not an absolute path: $InstallationPath" -Level "ERROR" -Component "MAIN"
        exit 1
    }
    Write-Log -Message "Installation path validation successful: $InstallationPath" -Level "SUCCESS" -Component "MAIN"
    
    # Initial PATH refresh
    Write-ColoredOutput "`nRefreshing initial PATH..." "Yellow" "INFO" "MAIN"
    Write-Log -Message "Performing initial PATH refresh" -Level "INFO" -Component "MAIN"
    Update-EnvironmentPath | Out-Null
    
    # Display configured scripts
    Write-ColoredOutput "`nCONFIGURED INSTALLATION SCRIPTS ($($InstallationScripts.Count)):" "Yellow" "INFO" "MAIN"
    Write-Log -Message "Configured installation scripts: $($InstallationScripts.Count)" -Level "INFO" -Component "MAIN"
    for ($i = 0; $i -lt $InstallationScripts.Count; $i++) {
        Write-ColoredOutput "  $($i+1). $($InstallationScripts[$i])" "White" "INFO" "MAIN"
        Write-Log -Message "  Script $($i+1): $($InstallationScripts[$i])" -Level "INFO" -Component "MAIN"
    }
    
    # Validate each configured script
    Write-ColoredOutput "`nValidating configured scripts..." "Yellow" "INFO" "MAIN"
    Write-Log -Message "Starting script validation process" -Level "INFO" -Component "MAIN"
    $validScripts = @()
    foreach ($scriptName in $InstallationScripts) {
        $scriptPath = Join-Path $ScriptsPath $scriptName
        Write-ColoredOutput "  Checking: $scriptName" "Cyan" "INFO" "MAIN"
        Write-Log -Message "Validating script: $scriptName at path: $scriptPath" -Level "DEBUG" -Component "MAIN"
        
        if (Test-InstallationScript $scriptPath) {
            $validScripts += $scriptPath
            Write-Log -Message "Script validation successful: $scriptName" -Level "SUCCESS" -Component "MAIN"
        } else {
            Write-ColoredOutput "    Skipping $scriptName - Not found or invalid" "Yellow" "WARNING" "MAIN"
            Write-Log -Message "Script validation failed, skipping: $scriptName" -Level "WARNING" -Component "MAIN"
        }
    }
    
    if ($validScripts.Count -eq 0) {
        Write-ColoredOutput "ERROR: No valid installation scripts found!" "Red" "ERROR" "MAIN"
        Write-ColoredOutput "Make sure the following scripts exist in $($ScriptsPath):" "Yellow" "WARNING" "MAIN"
        Write-Log -Message "FATAL: No valid installation scripts found" -Level "ERROR" -Component "MAIN"
        Write-Log -Message "Scripts path: $ScriptsPath" -Level "ERROR" -Component "MAIN"
        foreach ($script in $InstallationScripts) {
            Write-ColoredOutput "  - $script" "Gray" "DEBUG" "MAIN"
            Write-Log -Message "  Expected script: $script" -Level "ERROR" -Component "MAIN"
        }
        exit 1
    }
    
    Write-ColoredOutput "`nWill execute $($validScripts.Count) of $($InstallationScripts.Count) configured scripts in sequential order" "Green" "SUCCESS" "MAIN"
    Write-Log -Message "Script validation completed - Valid scripts: $($validScripts.Count) of $($InstallationScripts.Count)" -Level "SUCCESS" -Component "MAIN"
    
    # Execute installation scripts sequentially in the configured order
    Write-Log -Message "Starting sequential script execution" -Level "INFO" -Component "MAIN"
    $results = @()
    foreach ($scriptPath in $validScripts) {
        Write-ColoredOutput "`n[DEBUG] About to execute: $scriptPath" "Magenta" "DEBUG" "MAIN"
        Write-Log -Message "Preparing to execute script: $scriptPath" -Level "INFO" -Component "MAIN"
        
        $result = Invoke-InstallationScript -ScriptPath $scriptPath -InstallationPath $InstallationPath -TempDirectory $TempDirectory
        
        # IMMEDIATE DEBUG AFTER EACH SCRIPT
        Write-ColoredOutput "[DEBUG] Script completed, analyzing result..." "Magenta" "DEBUG" "MAIN"
        if ($result -ne $null) {
            Write-ColoredOutput "  Result object created successfully" "Green" "SUCCESS" "MAIN"
            Write-ColoredOutput "  Type: $($result.GetType().FullName)" "Cyan" "DEBUG" "MAIN"
            Write-Log -Message "Script result created - Type: $($result.GetType().FullName)" -Level "DEBUG" -Component "MAIN"
            
            if ($result -is [System.Collections.Hashtable]) {
                Write-ColoredOutput "  Hashtable Keys: $($result.Keys -join ', ')" "Cyan" "DEBUG" "MAIN"
                Write-ColoredOutput "  Has StartTime: $($result.ContainsKey('StartTime'))" "Cyan" "DEBUG" "MAIN"
                Write-ColoredOutput "  Has EndTime: $($result.ContainsKey('EndTime'))" "Cyan" "DEBUG" "MAIN"
                Write-Log -Message "Hashtable result - Keys: $($result.Keys -join ', ')" -Level "DEBUG" -Component "MAIN"
                Write-Log -Message "Hashtable properties - StartTime: $($result.ContainsKey('StartTime')), EndTime: $($result.ContainsKey('EndTime'))" -Level "DEBUG" -Component "MAIN"
                if ($result.ContainsKey('StartTime')) {
                    Write-ColoredOutput "  StartTime value: $($result['StartTime'])" "Gray" "DEBUG" "MAIN"
                    Write-Log -Message "StartTime: $($result['StartTime'])" -Level "DEBUG" -Component "MAIN"
                }
                if ($result.ContainsKey('EndTime')) {
                    Write-ColoredOutput "  EndTime value: $($result['EndTime'])" "Gray" "DEBUG" "MAIN"
                    Write-Log -Message "EndTime: $($result['EndTime'])" -Level "DEBUG" -Component "MAIN"
                }
            }
        } else {
            Write-ColoredOutput "  Result is NULL!" "Red" "ERROR" "MAIN"
            Write-Log -Message "Script result is NULL" -Level "ERROR" -Component "MAIN"
        }
        
        $results += $result
        Write-ColoredOutput "  Added to collection. Total results: $($results.Count)" "Cyan" "DEBUG" "MAIN"
        Write-Log -Message "Result added to collection - Total results: $($results.Count)" -Level "DEBUG" -Component "MAIN"
    }
    
    # FINAL DEBUG COLLECTION
    Write-ColoredOutput "`n" "White" "INFO" "MAIN"
    Write-ColoredOutput "======================== FINAL DEBUG ========================" "Magenta" "DEBUG" "MAIN"
    Write-Log -Message "Starting final debug analysis" -Level "DEBUG" -Component "MAIN"
    Debug-ResultsCollection -Results $results
    Write-ColoredOutput "==========================================================" "Magenta" "DEBUG" "MAIN"
    
    # Generate final report
    Write-ColoredOutput "`nGenerating installation report..." "Yellow" "INFO" "MAIN"
    Write-Log -Message "Starting final installation report generation" -Level "INFO" -Component "MAIN"
    $overallSuccess = Write-InstallationReport -Results $results -ConfiguredScripts $InstallationScripts -InstallationPath $InstallationPath
    
    # Calculate total execution time
    $scriptEndTime = Get-Date
    $totalDuration = ($scriptEndTime - $Global:LogStartTime).TotalSeconds
    
    # Exit with appropriate code
    if ($overallSuccess) {
        Write-ColoredOutput "`nAll installations completed successfully!" "Green" "SUCCESS" "MAIN"
        Write-ColoredOutput "Master log file: $LogFile" "Green" "SUCCESS" "MAIN"
        Write-Log -Message "All installations completed successfully in $([math]::Round($totalDuration, 2)) seconds" -Level "SUCCESS" -Component "MAIN"
        Write-Log -Message "Log file location: $LogFile" -Level "INFO" -Component "MAIN"
        exit 0
    } else {
        Write-ColoredOutput "`nSome installations failed. Check the report above for details." "Red" "ERROR" "MAIN"
        Write-ColoredOutput "Master log file: $LogFile" "Red" "ERROR" "MAIN"
        Write-Log -Message "Some installations failed after $([math]::Round($totalDuration, 2)) seconds" -Level "ERROR" -Component "MAIN"
        Write-Log -Message "Log file location: $LogFile" -Level "INFO" -Component "MAIN"
        exit 1
    }
}
catch {
    Write-ColoredOutput "`nFATAL ERROR: $($_.Exception.Message)" "Red" "ERROR" "MAIN"
    Write-ColoredOutput "Stack Trace: $($_.ScriptStackTrace)" "Red" "ERROR" "MAIN"
    Write-ColoredOutput "Master installation failed." "Red" "ERROR" "MAIN"
    Write-ColoredOutput "Master log file: $LogFile" "Red" "ERROR" "MAIN"
    
    Write-Log -Message "FATAL ERROR: $($_.Exception.Message)" -Level "ERROR" -Component "MAIN"
    Write-Log -Message "Full exception: $($_.Exception | Out-String)" -Level "ERROR" -Component "MAIN"
    
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