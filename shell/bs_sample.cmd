REM === PARSE --basespace-api-key ARGUMENT IF PROVIDED ===
REM Display full command line for debugging
@echo off
set BASESPACE_API_KEY=
:parse_args
if "%~1"=="" goto end_parse_args
if /i "%~1"=="--basespace-api-key" (
    set BASESPACE_API_KEY=%~2
    shift
    shift
    goto parse_args
)
shift
goto parse_args
:end_parse_args

If "%BASESPACE_API_KEY%"=="" (
    echo ERROR: --basespace-api-key argument is required.
    goto END
)

@set ERRORLEVEL=


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
set LOG_FILE=basespace_%LOGDATE%_%LOGTIME%.log
set CONSOLE_LOG="X:\BaseSpace\shell\console.log"


REM === INSTALLATION ====
echo.
echo [STEP] Starting installation and network drive mapping...
echo.

REM Only map X: if it does not already exist
if not exist "X:\" (
    echo [DEBUG] Attempting to map network drive X: to \\i110filesmb.hs.it.vumc.io\CAUSAL-DataExport
    echo [DEBUG] Attempting to map network drive X: to \\i110filesmb.hs.it.vumc.io\CAUSAL-DataExport >> "%TEMP%\%LOG_FILE%"
    net use x: \\i110filesmb.hs.it.vumc.io\CAUSAL-DataExport
    if %ERRORLEVEL% NEQ 0 (
        echo [DEBUG] ERROR: Failed to map network drive X:. Check network connectivity and permissions.
        echo [DEBUG] ERROR: Failed to map network drive X:. Check network connectivity and permissions. >> "%TEMP%\%LOG_FILE%"
        echo.
    )
    if not exist "X:\" (
        echo [DEBUG] ERROR: X: drive still not found after mapping attempt.
        echo [DEBUG] ERROR: X: drive still not found after mapping attempt. >> "%TEMP%\%LOG_FILE%"
        echo.
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
echo.
echo [STEP] Validating and creating required directories...
echo.
for %%D in ("%WORKING_DIR%" "%COMPLETED_DIR%" "%LOG_DIR%") do (
    if not exist %%D (
        echo [INFO] Creating directory: %%D
        mkdir %%D
        if not exist %%D (
            echo [ERROR] Failed to create directory: %%D
            echo [ERROR] Failed to create directory: %%D >> "%LOG_FILE%"
            echo.
            goto END
        )
        echo.
    )
)
echo [STEP] All required directories validated and ready.
echo.


REM PowerShell command to download executable
echo.
echo [STEP] Downloading BaseSpace CLI executable...
echo.

start /wait powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://launch.basespace.illumina.com/CLI/latest/amd64-windows/bs.exe' -OutFile '%TEMP%\bs.exe'"
if %ERRORLEVEL% NEQ 0 (
    echo [%DATE% %TIME%] ERROR: Failed to download bs.exe >> "%LOG_FILE%"
    echo.
    goto END
)
set BASESPACE_CLI=%TEMP%\bs.exe



REM Establish the executable (example: check version)
echo.
echo [STEP] Checking BaseSpace CLI version...
echo.
REM Establish the executable (example: check version)
powershell -Command "& '%BASESPACE_CLI%' --version"
if %ERRORLEVEL% NEQ 0 (
    echo [%DATE% %TIME%] ERROR: bs.exe failed to run. >> "%LOG_FILE%"
    echo.
    goto END
)

REM === ENVIRONMENT SETUP ===

echo.
echo [STEP] Generating BaseSpace config file with API key...
echo.
REM If .basespace directory exists, delete it and its contents first
if exist "%USERPROFILE%\.basespace" (
    echo [STEP] Removing existing .basespace directory...
    rmdir /s /q "%USERPROFILE%\.basespace"
)

mkdir "%USERPROFILE%\.basespace"
echo apiServer   = https://api.basespace.illumina.com > "%USERPROFILE%\.basespace\default.cfg"
echo accessToken = %BASESPACE_API_KEY% >> "%USERPROFILE%\.basespace\default.cfg"
echo [STEP] BaseSpace config file generated at %USERPROFILE%\.basespace\default.cfg
echo.

REM === LOG FUNCTION ===
echo [STEP] Preparing logging function...
echo.
REM Windows batch does not have functions, so use echo and >> for logging

REM === 1. List available projects ===
echo.
echo [STEP] Listing available projects...
echo.
REM Run the command and save JSON output to a file
powershell -Command "& '%BASESPACE_CLI%' list project /format:json /log:%LOG_FILE% > %TEMP%/projects.json"
if %ERRORLEVEL% NEQ 0 (
    echo [%DATE% %TIME%] ERROR: bs.exe failed to run. >> "%LOG_FILE%"
    echo.
    goto END
)

REM Extract all project IDs as a space-separated string
FOR /F "usebackq delims=" %%A IN (`powershell -Command "Get-Content \"%TEMP%\projects.json\" | ConvertFrom-Json | ForEach-Object { $_.Id } | ForEach-Object { Write-Host -NoNewline $_' ' }"`) DO SET "PROJECT_IDS=%%A"

REM Now iterate over each ID
setlocal enabledelayedexpansion
REM Store initial sample folder count for each project
set "TOTAL_INITIAL=0"
set "TOTAL_FINAL=0"

FOR %%I IN (%PROJECT_IDS%) DO (
    REM Count initial sample folders in project directory (if exists)
    set "INITIAL_COUNT=0"
    if exist "%WORKING_DIR%\%%I" (
        for /f %%C in ('dir /b /ad "%WORKING_DIR%\%%I" ^| find /c /v ""') do set "INITIAL_COUNT=%%C"
    )
    echo [INFO] Project %%I: Starting sample folder count: !INITIAL_COUNT!
    echo.
    set /a TOTAL_INITIAL+=!INITIAL_COUNT!


    REM Query biosamples and check if any records exist before saving JSON
    echo [STEP] Processing biosamples for project %%I...
    echo.
    for /f "delims=" %%S in ('powershell -Command "$samples = & '%BASESPACE_CLI%' biosamples list /project-id %%I /format:json /log:%LOG_FILE% | ConvertFrom-Json; if ($samples -eq $null) { Write-Host 0 } elseif ($samples -is [array]) { if ($samples.Length -gt 0) { Write-Host 1 } else { Write-Host 0 } } else { Write-Host 1 }"') do set HAS_SAMPLES=%%S
    if "!HAS_SAMPLES!"=="1" (
        echo [STEP] Biosamples found for project %%I. Saving JSON...
        echo.
        powershell -Command "$samples = & '%BASESPACE_CLI%' biosamples list /project-id %%I /format:json | ConvertFrom-Json; $samples | ConvertTo-Json -Compress | Set-Content -Encoding UTF8 '%TEMP%\\%%I_samples.json'"
        if not exist "%WORKING_DIR%\%%I" (
            echo [STEP] Creating project directory: %WORKING_DIR%\%%I
            echo.
            mkdir "%WORKING_DIR%\%%I"
        )
        echo "%BASESPACE_CLI%" project download -i %%I -o "%WORKING_DIR%\%%I" /log:%LOG_FILE% /no-progress-bars
        "%BASESPACE_CLI%" project download -i %%I -o "%WORKING_DIR%\%%I" /log:%LOG_FILE% /no-progress-bars
        echo.
    ) else (
        echo [STEP] No biosamples found for project %%I. Skipping.
        echo.
    )

    REM Count final sample folders in project directory
    set "FINAL_COUNT=0"
    if exist "%WORKING_DIR%\%%I" (
        for /f %%C in ('dir /b /ad "%WORKING_DIR%\%%I" ^| find /c /v ""') do set "FINAL_COUNT=%%C"
    )
    echo [INFO] Project %%I: Ending sample folder count: !FINAL_COUNT!
    set /a TOTAL_FINAL+=!FINAL_COUNT!
    REM Show difference for this project
    set /a DIFF=FINAL_COUNT-INITIAL_COUNT
    echo [INFO] Project %%I: Sample folder count difference: !DIFF!
    echo.
)

REM Show total difference across all projects
set /a TOTAL_DIFF=TOTAL_FINAL-TOTAL_INITIAL
echo [INFO] All Projects: Total sample folder count difference: !TOTAL_DIFF!
echo.
REM === DISCONNECT X: DRIVE IF CONNECTED ===
echo [STEP] Checking for existing X: drive mapping...
echo.
net use x: >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [STEP] Disconnecting X: drive...
    echo.
    net use x: /delete >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        echo [INFO] X: drive disconnected successfully.
        echo.
    ) else (
        echo [WARN] Failed to disconnect X: drive or it was not mapped.
        echo.
    )
) else (
    echo [INFO] X: drive is not currently mapped.
    echo.
)
REM === CLEANUP: REMOVE BASESPACE CLI FROM TEMP ===
if exist "%BASESPACE_CLI%" (
    echo [STEP] Removing BaseSpace CLI executable from TEMP...
    echo.
    del /f /q "%BASESPACE_CLI%"
    if exist "%BASESPACE_CLI%" (
        echo [WARN] Failed to delete %BASESPACE_CLI%.
        echo.
    ) else (
        echo [INFO] BaseSpace CLI executable removed from TEMP.
        echo.
    )
)

REM === CLEANUP: REMOVE BASESPACE CONFIG FILE ===
if exist "%USERPROFILE%\.basespace\default.cfg" (
    echo [STEP] Removing BaseSpace config file...
    del /f /q "%USERPROFILE%\.basespace\default.cfg"
    if exist "%USERPROFILE%\.basespace\default.cfg" (
        echo [WARN] Failed to delete %USERPROFILE%\.basespace\default.cfg.
    ) else (
        echo [INFO] BaseSpace config file removed.
    )
)