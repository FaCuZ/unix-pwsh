# -----------------------------------------------------------------------------
# This is the PowerShell profile script for Unix-Pwsh
# -----------------------------------------------------------------------------
# This script is designed to be run in PowerShell Core (pwsh) and is intended to set up a custom PowerShell profile for Unix-like environments.
# It includes functionality for loading environment variables, checking internet connectivity, and installing necessary modules and fonts.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Load environment variables from the .env file
# -----------------------------------------------------------------------------
# This script loads environment variables from a .env file located in the user's home directory.        

$baseDir = "$HOME\unix-pwsh"

$envFilePath = Join-Path -Path $baseDir -ChildPath ".env"

# Download the .env file if it does not exist
if (-not (Test-Path -Path $envFilePath)) {
    $envFileUrl = "https://raw.githubusercontent.com/FaCuZ/unix-pwsh/main/.env"
    try {
        Invoke-WebRequest -Uri $envFileUrl -OutFile $envFilePath -UseBasicParsing
        Write-Host "✅ Downloaded .env from $envFileUrl" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to download .env from $envFileUrl" -ForegroundColor Red
        exit
    }
}

# Transform the .env file into environment variables
if (Test-Path -Path $envFilePath) {
    Get-Content -Path $envFilePath | ForEach-Object {
        if ($_ -match "^\s*([^#][^=]+)=(.+)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            [System.Environment]::SetEnvironmentVariable($key, $value, [System.EnvironmentVariableTarget]::Process)
        }
    }
}

# Assign environment variables to PowerShell variables
$githubUser = $env:GITHUB_USER
$name = $env:USER_NAME
$githubRepo = $env:GITHUB_REPO
$githubBaseURL = "$env:GITHUB_BASE_URL/$githubUser/$githubRepo/$env:GITHUB_BASE_BRANCH"
$OhMyPoshConfigFileName = $env:OHMY_POSH_CONFIG_FILE_NAME
$OhMyPoshConfig = "$env:OHMY_POSH_CONFIG/$OhMyPoshConfigFileName"

$configPath = "$baseDir\pwsh_custom_config.yml"
$xConfigPath = "$baseDir\pwsh_full_custom_config.yml"
$promptColor = $env:PROMPT_COLOR 
$font = $env:FONT
$font_url = $env:FONT_URL 
$fontFileName = $env:FONT_FILE_NAME
$font_folder = $env:FONT_FOLDER 

$timeout = $env:TIMEOUT -as [int]
$autoUpdate = $env:AUTO_UPDATE -eq "true"
$noLogo = $env:NO_LOGO -eq "true"

# Validate that all required environment variables are set
if (-not $githubUser -or -not $name -or -not $githubRepo -or -not $githubBaseURL -or -not $OhMyPoshConfigFileName -or -not $OhMyPoshConfig -or -not $promptColor -or -not $font -or -not $font_url -or -not $fontFileName -or -not $font_folder -or -not $configPath) {
    Write-Host "❌ One or more required environment variables are not set." -ForegroundColor Red
    exit
}

# -----------------------------------------------------------------------------

# Check internet access
# Use wmi as there is no timeout in pwsh 5.0 and generally slow.
$pingResult = Get-CimInstance -ClassName Win32_PingStatus -Filter "Address = 'github.com' AND Timeout = $timeout" -Property StatusCode 2>$null
if ($pingResult.StatusCode -eq 0) {
    $canConnectToGitHub = $true
}
else {
    $canConnectToGitHub = $false
}

$modules = @( 
    # This is a list of modules that need to be imported / installed
    @{ Name = "Powershell-Yaml"; ConfigKey = "Powershell-Yaml_installed" },
    @{ Name = "Terminal-Icons"; ConfigKey = "Terminal-Icons_installed" },
    @{ Name = "PoshFunctions"; ConfigKey = "PoshFunctions_installed" }
)
$files = @("Microsoft.PowerShell_profile.ps1", "installer.ps1", "pwsh_helper.ps1", "functions.ps1", $OhMyPoshConfigFileName)

# Message to tell the user what to do after installation
$infoMessage = @"
To fully utilize the custom Unix-pwsh profile, please follow these steps:
1. Set Windows Terminal as the default terminal.
2. Choose PowerShell Core as the preferred startup profile in Windows Terminal.
3. Go to Settings > Defaults > Appearance > Font and select the Nerd Font.

These steps are necessary to ensure the pwsh profile works as intended.
If you have further questions, on how to set the above, don't hesitate to ask me, by filing an issue on my repository, after you tried searching the web for yourself.
"@

$scriptBlock = {
    param($githubUser, $files, $baseDir, $canConnectToGitHub, $githubBaseURL)
    Invoke-Expression (Invoke-WebRequest -Uri "$githubBaseURL/pwsh_helper.ps1" -UseBasicParsing).Content
    BackgroundTasks
}

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# Function for calling the update Powershell Script
function Run-UpdatePowershell {
    if ($autoUpdate) {        
        . Invoke-Expression (Invoke-WebRequest -Uri "$githubBaseURL/pwsh_helper.ps1" -UseBasicParsing).Content
        Update-Powershell
    } 
}

# ----------------------------------------------------------------------------

if (-not $noLogo) {
    Write-Host ""
    Write-Host "Welcome $name ⚡" -ForegroundColor $promptColor
    Write-Host ""
}

# Function to check if all the $files exist or not.
$allFilesExist = $files | ForEach-Object { Join-Path -Path $baseDir -ChildPath $_ } | Test-Path -PathType Leaf -ErrorAction SilentlyContinue | ForEach-Object { $_ -eq $true }
if ($allFilesExist -contains $false) {
    $injectionMethod = "remote"
}
else {
    $injectionMethod = "local"
    $OhMyPoshConfig = Join-Path -Path $baseDir -ChildPath $OhMyPoshConfigFileName
}

# Check for dependencies and if not chainload the installer.
if (Test-Path -Path $xConfigPath) {
    # Check if the Master config file exists, if so skip every other check.
    # Write-Host "✅ Successfully initialized Pwsh`n" -ForegroundColor Green
    Import-Module Terminal-Icons
    # foreach ($module in $modules) {
    #     # As the master config exists, we assume that all modules are installed.
    #     Import-Module $module.Name
    # }
}
else {
    # If there is no internet connection, we cannot install anything.
    if (-not $global:canConnectToGitHub) {
        Write-Host "❌ Skipping initialization due to GitHub not responding within 4 second." -ForegroundColor Red
        exit
    }
    . Invoke-Expression (Invoke-WebRequest -Uri "$githubBaseURL/installer.ps1" -UseBasicParsing).Content
    Install-NuGet
    Test-Pwsh 
    Test-CreateProfile
    Install-Config
}

# Try to import MS PowerToys WinGetCommandNotFound
Import-Module -Name Microsoft.WinGet.CommandNotFound > $null 2>&1
if (-not $?) { Install-Module -Name Microsoft.WinGet.CommandNotFound }

# Inject OhMyPosh
oh-my-posh init pwsh --config $OhMyPoshConfig | Invoke-Expression


# ----------------------------------------------------------
# Deferred loading
# Source: https://fsackur.github.io/2023/11/20/Deferred-profile-loading-for-better-performance/
# ----------------------------------------------------------

# Check if psVersion is lower than 7.x, then load the functions **without** deferred loading
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if ($injectionMethod -eq "local") {
        . "$baseDir\functions.ps1"
        # Execute the background tasks
        Start-Job -ScriptBlock $scriptBlock -ArgumentList $githubUser, $files, $baseDir, $canConnectToGitHub, $githubBaseURL
    }
    else {
        if ($global:canConnectToGitHub) {
            #Load Functions
            . Invoke-Expression (Invoke-WebRequest -Uri "$githubBaseURL/functions.ps1" -UseBasicParsing).Content
            # Update PowerShell in the background
            Start-Job -ScriptBlock $scriptBlock -ArgumentList $githubUser, $files, $baseDir, $canConnectToGitHub, $githubBaseURL
        }
        else {
            Write-Host "❌ Skipping initialization due to GitHub not responding within 1 second." -ForegroundColor Red
        }
    }
}

# ---------------------------------------------------------

$Deferred = {
    if ($injectionMethod -eq "local") {
        . "$baseDir\functions.ps1"
        # Execute the background tasks
        Start-Job -ScriptBlock $scriptBlock -ArgumentList $githubUser, $files, $baseDir, $canConnectToGitHub, $githubBaseURL
    }
    else {
        if ($global:canConnectToGitHub) {
            #Load Functions
            . Invoke-Expression (Invoke-WebRequest -Uri "$githubBaseURL/functions.ps1" -UseBasicParsing).Content
            # Update PowerShell in the background
            Start-Job -ScriptBlock $scriptBlock -ArgumentList $githubUser, $files, $baseDir, $canConnectToGitHub, $githubBaseURL
        }
        else {
            Write-Host "❌ Skipping initialization due to GitHub not responding within 1 second." -ForegroundColor Red
        }
    }
}


$GlobalState = [psmoduleinfo]::new($false)
$GlobalState.SessionState = $ExecutionContext.SessionState
# to run our code asynchronously
$Runspace = [runspacefactory]::CreateRunspace($Host)
$Powershell = [powershell]::Create($Runspace)
$Runspace.Open()
$Runspace.SessionStateProxy.PSVariable.Set('GlobalState', $GlobalState)
# ArgumentCompleters are set on the ExecutionContext, not the SessionState
# Note that $ExecutionContext is not an ExecutionContext, it's an EngineIntrinsics 😡
$Private = [Reflection.BindingFlags]'Instance, NonPublic'
$ContextField = [Management.Automation.EngineIntrinsics].GetField('_context', $Private)
$Context = $ContextField.GetValue($ExecutionContext)
# Get the ArgumentCompleters. If null, initialise them.
$ContextCACProperty = $Context.GetType().GetProperty('CustomArgumentCompleters', $Private)
$ContextNACProperty = $Context.GetType().GetProperty('NativeArgumentCompleters', $Private)
$CAC = $ContextCACProperty.GetValue($Context)
$NAC = $ContextNACProperty.GetValue($Context)
if ($null -eq $CAC) {
    $CAC = [Collections.Generic.Dictionary[string, scriptblock]]::new()
    $ContextCACProperty.SetValue($Context, $CAC)
}
if ($null -eq $NAC) {
    $NAC = [Collections.Generic.Dictionary[string, scriptblock]]::new()
    $ContextNACProperty.SetValue($Context, $NAC)
}
# Get the AutomationEngine and ExecutionContext of the runspace
$RSEngineField = $Runspace.GetType().GetField('_engine', $Private)
$RSEngine = $RSEngineField.GetValue($Runspace)
$EngineContextField = $RSEngine.GetType().GetFields($Private) | Where-Object { $_.FieldType.Name -eq 'ExecutionContext' }
$RSContext = $EngineContextField.GetValue($RSEngine)
# Set the runspace to use the global ArgumentCompleters
$ContextCACProperty.SetValue($RSContext, $CAC)
$ContextNACProperty.SetValue($RSContext, $NAC)
$Wrapper = {
    # Without a sleep, you get issues:
    #   - occasional crashes
    #   - prompt not rendered
    #   - no highlighting
    # Assumption: this is related to PSReadLine.
    # 20ms seems to be enough on my machine, but let's be generous - this is non-blocking
    Start-Sleep -Milliseconds 100
    . $GlobalState { . $Deferred; Remove-Variable Deferred }
}
$null = $Powershell.AddScript($Wrapper.ToString()).BeginInvoke()
