
@REM === ERROR HANDLER ===
:error_handler
echo [FAILURE] %FAILURE_MESSAGE%
echo [FAILURE] %FAILURE_MESSAGE% >> "%LOG_FILE%"
exit /b 1


@echo Task Name: ${ops_task_name}
@echo Task Instance: ${ops_task_id}
@echo.

@echo off
REM === SANITIZE DATE FOR FILE NAMES ===
for /f "tokens=2-4 delims=/ " %%a in ("%DATE%") do set LOGDATE=%%b%%c%%a

REM === SANITIZE TIME FOR FILE NAMES ===
for /f "tokens=1-3 delims=: " %%a in ("%TIME%") do set LOGTIME=%%a%%b%%c


set PROJECT_NAME=CAUSAL
set RESEARCHNAME=%PROJECT_NAME%
set BASESPACE_API_KEY=${UAC_CRED_PASSWORD}
set LOG_FILE=basespace_%LOGDATE%_%LOGTIME%.log
set CONSOLE_LOG="X:\BaseSpace\shell\console.log"


REM === INSTALLATION ====
echo [STEP] Starting installation and network drive mapping...

REM Only map X: if it does not already exist
if not exist "X:\" (
    echo [DEBUG] Attempting to map network drive X: to \\i110filesmb.hs.it.vumc.io\CAUSAL-DataExport
    echo [DEBUG] Attempting to map network drive X: to \\i110filesmb.hs.it.vumc.io\CAUSAL-DataExport >> "%TEMP%\%LOG_FILE%"
    net use x: \\i110filesmb.hs.it.vumc.io\CAUSAL-DataExport
    if %ERRORLEVEL% NEQ 0 (
        set FAILURE_MESSAGE=Failed to map network drive X:. Check network connectivity and permissions.
        goto error_handler
    )
    if not exist "X:\" (
        set FAILURE_MESSAGE=X: drive still not found after mapping attempt. Network drive mapping failed.
        goto error_handler
    )
)

REM === ESTABLISH ALL PATHS ===
set WORKING_DIR=X:\Basespace\%RESEARCHNAME%
set COMPLETED_DIR=%WORKING_DIR%\Completed
set LOG_DIR=%WORKING_DIR%\Log
set LOG_FILE=%LOG_DIR%\basespace_%LOGDATE%_%LOGTIME%.log
set EXPECTED_SAMPLES=%CONFIG_DIR%\expected_samples.csv
set BASESPACE_PROFILE=%USERPROFILE%\.basespace

REM === VALIDATE AND CREATE DIRECTORIES ===
echo [STEP] Validating and creating required directories...
for %%D in ("%WORKING_DIR%" "%COMPLETED_DIR%" "%LOG_DIR%") do (
    if not exist %%D (
        echo [INFO] Creating directory: %%D
        mkdir %%D
        if not exist %%D (
            set FAILURE_MESSAGE=Failed to create directory: %%D. Check permissions or disk space.
            goto error_handler
        )
    )
)
echo [STEP] All required directories validated and ready.



REM PowerShell command to download executable
echo [STEP] Downloading BaseSpace CLI executable...

start /wait powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://launch.basespace.illumina.com/CLI/latest/amd64-windows/bs.exe' -OutFile '%TEMP%\bs.exe'"
if %ERRORLEVEL% NEQ 0 (
    set FAILURE_MESSAGE=Failed to download BaseSpace CLI executable (bs.exe). Check internet connection and permissions.
    goto error_handler
)
set BASESPACE_CLI=%TEMP%\bs.exe



REM Establish the executable (example: check version)
echo [STEP] Checking BaseSpace CLI version...
REM Establish the executable (example: check version)
powershell -Command "& '%BASESPACE_CLI%' --version"
if %ERRORLEVEL% NEQ 0 (
    set FAILURE_MESSAGE=BaseSpace CLI (bs.exe) failed to run. The executable may be corrupt or missing dependencies.
    goto error_handler
)

REM === ENVIRONMENT SETUP ===

echo [STEP] Generating BaseSpace config file with API key...
mkdir "%USERPROFILE%\.basespace"
echo apiServer   = https://api.basespace.illumina.com > "%USERPROFILE%\.basespace\default.cfg"
echo accessToken = %BASESPACE_API_KEY% >> "%USERPROFILE%\.basespace\default.cfg"
echo [STEP] BaseSpace config file generated at %USERPROFILE%\.basespace\default.cfg
echo [STEP] Contents of default.cfg:
type "%USERPROFILE%\.basespace\default.cfg"

REM === LOG FUNCTION ===
echo [STEP] Preparing logging function...
REM Windows batch does not have functions, so use echo and >> for logging

REM === 1. List available projects ===
echo [STEP] Listing available projects...
REM Run the command and save JSON output to a file
powershell -Command "& '%BASESPACE_CLI%' list project /format:json /log:%LOG_FILE% > %TEMP%/projects.json"
if %ERRORLEVEL% NEQ 0 (
    set FAILURE_MESSAGE=Failed to list projects with BaseSpace CLI. Check API key, network, or CLI installation.
    goto error_handler
)

REM Extract all project IDs as a space-separated string
FOR /F "usebackq delims=" %%A IN (`powershell -Command "Get-Content \"%TEMP%\projects.json\" | ConvertFrom-Json | ForEach-Object { $_.Id } | ForEach-Object { Write-Host -NoNewline $_' ' }"`) DO SET "PROJECT_IDS=%%A"

REM Now iterate over each ID
setlocal enabledelayedexpansion
FOR %%I IN (%PROJECT_IDS%) DO (
    REM Query biosamples and check if any records exist before saving JSON
    echo [STEP] Processing biosamples for project %%I...
    for /f "delims=" %%S in ('powershell -Command "$samples = & '%BASESPACE_CLI%' biosamples list /project-id %%I /format:json /log:%LOG_FILE% | ConvertFrom-Json; if ($samples -eq $null) { Write-Host 0 } elseif ($samples -is [array]) { if ($samples.Length -gt 0) { Write-Host 1 } else { Write-Host 0 } } else { Write-Host 1 }"') do set HAS_SAMPLES=%%S
    if "!HAS_SAMPLES!"=="1" (
        echo [STEP] Biosamples found for project %%I. Saving JSON...
        powershell -Command "$samples = & '%BASESPACE_CLI%' biosamples list /project-id %%I /format:json | ConvertFrom-Json; $samples | ConvertTo-Json -Compress | Set-Content -Encoding UTF8 '%TEMP%\\%%I_samples.json'"
        if not exist "%WORKING_DIR%\\%%I" (
            echo [STEP] Creating project directory: %WORKING_DIR%\%%I
            mkdir "%WORKING_DIR%\\%%I"
        )
        echo "%BASESPACE_CLI%" project download -i %%I -o "%WORKING_DIR%\\%%I" /log:%LOG_FILE% /no-progress-bars
        "%BASESPACE_CLI%" project download -i %%I -o "%WORKING_DIR%\\%%I" /log:%LOG_FILE% /no-progress-bars
        @REM echo [STEP] Listing sample names for project %%I...
        @REM for /f "delims=" %%N in ('powershell -Command "Get-Content \"%TEMP%\\%%I_samples.json\" | ConvertFrom-Json | ForEach-Object { if ($_.BioSampleName) { $_.BioSampleName } }"') do (
        @REM     echo Sample Name: %%N
        @REM )
    ) else (
        echo [STEP] No biosamples found for project %%I. Skipping.
    )
)
