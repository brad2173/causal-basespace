@echo off
set LOG_FILE=bs_sample.log
REM === DEBUG: Print key environment variables and paths ===
echo [DEBUG] TEMP=%TEMP% 1>&2
echo [DEBUG] USERPROFILE=%USERPROFILE% 1>&2
echo [DEBUG] Current Directory: %CD% 1>&2

REM === PARSE --basespace-api-key ARGUMENT IF PROVIDED ===
REM Display full command line for debugging



set BASESPACE_API_KEY=
set WORKFLOW_ID=
set OVERWRITE_BSCLI=true
:parse_args
if "%~1"=="" goto end_parse_args
if /i "%~1"=="--basespace-api-key" (
    set BASESPACE_API_KEY=%~2
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--workflow-id" (
    set WORKFLOW_ID=%~2
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--overwrite-bscli" (
    set OVERWRITE_BSCLI=%~2
    shift
    shift
    goto parse_args
)
shift
goto parse_args
:end_parse_args


if "%BASESPACE_API_KEY%"=="" (
    echo ERROR: --basespace-api-key argument is required. 1>&2
    goto END
)

REM === SANITIZE DATE FOR FILE NAMES ===
for /f "tokens=2-4 delims=/ " %%a in ("%DATE%") do set LOGDATE=%%b%%c%%a

REM === SANITIZE TIME FOR FILE NAMES ===
for /f "tokens=1-3 delims=: " %%a in ("%TIME%") do set LOGTIME=%%a%%b%%c


set PROJECT_NAME=CAUSAL
set RESEARCHNAME=%PROJECT_NAME%
echo [DEBUG] WORKING_DIR will be: X:\BaseSpace\%RESEARCHNAME% 1>&2


REM === Always set the download URL before any logic ===
set "BS_DOWNLOAD_URL=https://launch.basespace.illumina.com/CLI/latest/amd64-windows/bs.exe"
echo [DEBUG] Set BS_DOWNLOAD_URL to: %BS_DOWNLOAD_URL% 1>&2

REM === INSTALLATION ====

REM Only map X: if it does not already exist
echo [DEBUG] Checking if X: drive exists... 1>&2
if not exist "X:\" (
    echo [DEBUG] Attempting to map X: to \\i110filesmb.hs.it.vumc.io\CAUSAL-DataExport 1>&2
    net use x: \\i110filesmb.hs.it.vumc.io\CAUSAL-DataExport > "%TEMP%\netuse_x_output.log" 2>&1
    if "%ERRORLEVEL%" NEQ "0" (
        echo     ERROR: Failed to map network drive X:. Check network connectivity and permissions. 1>&2
        echo     ERROR: Failed to map network drive X:. Check network connectivity and permissions. >> "%TEMP%\%LOG_FILE%"
        echo.
    )
    echo [DEBUG] Checking if X: drive exists after mapping... 1>&2
    if not exist "X:\" (
        echo     ERROR: X: drive still not found after mapping attempt. 1>&2
        echo     ERROR: X: drive still not found after mapping attempt. >> "%TEMP%\%LOG_FILE%"
        echo.
    )
)



REM === COLLECT FOLDER SIZE BEFORE EXPORT (after X: is mapped, before bs.exe is run) ===
setlocal enabledelayedexpansion
set "TMP_SIZE_BEFORE_GB="
if exist "X:\" (
    for /f %%S in ('powershell -Command "$size = (Get-ChildItem -Path '\\i110filesmb.hs.it.vumc.io\CAUSAL-DataExport' -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB; [math]::Round($size,2)"') do set "TMP_SIZE_BEFORE_GB=%%S"
    if "!TMP_SIZE_BEFORE_GB!"=="" set "TMP_SIZE_BEFORE_GB=0"
) else (
    echo [ERROR] X: drive is not mapped. Cannot determine folder size before export. 1>&2
    set "TMP_SIZE_BEFORE_GB=0"
)
endlocal & set "SIZE_BEFORE_GB=%TMP_SIZE_BEFORE_GB%"

REM === CAPTURE JOB START TIME ===
set "JOB_START=%DATE% %TIME%"



REM === ESTABLISH ALL PATHS ===
set WORKING_DIR=X:\BaseSpace\%RESEARCHNAME%
set COMPLETED_DIR=%WORKING_DIR%\Completed
set LOG_DIR=%WORKING_DIR%\Log

set EXPECTED_SAMPLES=%CONFIG_DIR%\expected_samples.csv

REM === VALIDATE AND CREATE DIRECTORIES ===



REM Validate/Create Directories (inline, no helper)
echo [DEBUG] Validating/creating directories: %WORKING_DIR%, %COMPLETED_DIR%, %LOG_DIR% 1>&2
for %%D in ("%WORKING_DIR%" "%COMPLETED_DIR%" "%LOG_DIR%") do (
    if not exist %%D (
        mkdir %%D
        if not exist %%D (
            echo     [ERROR] Failed to create directory: %%D 1>&2
            echo     [ERROR] Failed to create directory: %%D >> "%LOG_FILE%"
            echo.
            goto END
        )
    )
)


echo [DEBUG] Downloading bs.exe to %TEMP%\bs.exe 1>&2

REM === Determine if we should download bs.exe or use existing ===
if /i "%OVERWRITE_BSCLI%"=="false" (
    REM Use existing bs.exe in PATH
    echo [DEBUG] OVERWRITE_BSCLI is false. Using existing bs.exe in PATH. 1>&2
    where bs.exe > "%TEMP%\bs_where.log" 2>&1
    set BASESPACE_CLI=
    for /f "usebackq delims=" %%B in ("%TEMP%\bs_where.log") do if not defined BASESPACE_CLI set BASESPACE_CLI=%%B
    if not defined BASESPACE_CLI (
        echo [ERROR] Could not find bs.exe in PATH. Please ensure it is installed and available. 1>&2
        goto END
    )
    echo [DEBUG] Using existing bs.exe at: %BASESPACE_CLI% 1>&2
) else (
    echo [DEBUG] OVERWRITE_BSCLI is true. Will download bs.exe to %TEMP%\bs.exe 1>&2
    set "BS_DOWNLOAD_URL=https://launch.basespace.illumina.com/CLI/latest/amd64-windows/bs.exe"
    if exist "%TEMP%\bs.exe" (
        echo [DEBUG] %TEMP%\bs.exe already exists. Attempting to delete... 1>&2
        del /f /q "%TEMP%\bs.exe"
        if exist "%TEMP%\bs.exe" (
            echo [ERROR] Could not delete %TEMP%\bs.exe. It may be in use by another process. 1>&2
            echo [ERROR] Please close any process using %TEMP%\bs.exe and try again. 1>&2
            goto END
        )
    )
    echo [DEBUG] Downloading bs.exe using PowerShell... 1>&2
    echo [DEBUG] PowerShell command: [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%BS_DOWNLOAD_URL%' -OutFile '%TEMP%\bs.exe' -ErrorAction Stop -Verbose 1>&2
    echo [DEBUG] Download URL: %BS_DOWNLOAD_URL% 1>&2
    echo [LOG] Download URL: %BS_DOWNLOAD_URL% 1>&2
    powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Write-Host 'Starting download from: %BS_DOWNLOAD_URL%'; Invoke-WebRequest -Uri '%BS_DOWNLOAD_URL%' -OutFile '%TEMP%\\bs.exe' -ErrorAction Stop -Verbose; Write-Host 'Download complete.' } catch { Write-Host 'DOWNLOAD_ERROR'; Write-Host $_.Exception.Message; Write-Host $_.ScriptStackTrace; exit 1 }" 1>&2
    set DL_ERRORLEVEL=%ERRORLEVEL%
    echo [DEBUG] Checking if %TEMP%\bs.exe exists after download... 1>&2
    if exist "%TEMP%\bs.exe" (
        echo [DEBUG] %TEMP%\bs.exe exists after download. 1>&2
    ) else (
        echo [ERROR] %TEMP%\bs.exe does NOT exist after download! 1>&2
    )
    set BASESPACE_CLI=%TEMP%\bs.exe
)
REM Check for download success outside the parenthesized block to ensure variable is set
if not exist "%BASESPACE_CLI%" (
    echo [ERROR] %BASESPACE_CLI% does not exist after download attempt! 1>&2
    echo [ERROR] TEMP=%TEMP% 1>&2
    echo [ERROR] Download may have failed or TEMP path is invalid. 1>&2
    goto END
)
if "%DL_ERRORLEVEL%" NEQ "0" (
    echo     [%DATE% %TIME%] ERROR: Failed to download bs.exe 1>&2
    echo. 1>&2
    goto END
)
)



REM Establish the executable (example: check version)
REM Suppress BaseSpaceCLI version output
powershell -Command "& '%BASESPACE_CLI%' --version" >nul 2>&1
if "%ERRORLEVEL%" NEQ "0" (
    echo     [%DATE% %TIME%] ERROR: bs.exe failed to run. 1>&2
    echo. 1>&2
    goto END
)

REM === ENVIRONMENT SETUP ===

REM If .basespace directory exists, delete it and its contents first
echo [DEBUG] Checking for existing %USERPROFILE%\.basespace directory... 1>&2
if exist "%USERPROFILE%\.basespace" (
    rmdir /s /q "%USERPROFILE%\.basespace"
)

echo [DEBUG] Creating %USERPROFILE%\.basespace directory if it does not exist... 1>&2
mkdir "%USERPROFILE%\.basespace"
echo [DEBUG] Writing config to %USERPROFILE%\.basespace\default.cfg 1>&2
echo apiServer   = https://api.basespace.illumina.com > "%USERPROFILE%\.basespace\default.cfg"
echo accessToken = %BASESPACE_API_KEY% >> "%USERPROFILE%\.basespace\default.cfg"

REM === LOG FUNCTION ===
REM Windows batch does not have functions, so use echo and >> for logging

REM === 1. List available projects ===
REM Run the command and save JSON output to a file
powershell -Command "& '%BASESPACE_CLI%' list project /format:json /log:%LOG_FILE% > %TEMP%/projects.json"
if "%ERRORLEVEL%" NEQ "0" (
    echo     [%DATE% %TIME%] ERROR: bs.exe failed to run. >> "%LOG_FILE%"
    echo.
    goto END
)


REM  === 1b. Store Process ID in worfklow pidfile:

echo [DEBUG] Cleaning up any *_pid.log files in %TEMP% 1>&2
for %%F in ("%TEMP%\*_pid.log") do del /f /q "%%F"

for /f %%I in ('powershell -NoProfile -Command "Write-Output $PID"') do set PID=%%I

echo %PID% > %TEMP%\%WORKFLOW_ID%_pid.log
echo INFO: process_id_file - %TEMP%\%WORKFLOW_ID%_pid.log 1>&2
echo INFO: process_id - %PID% 1>&2




REM === 2. Iterate over each project and download samples if available ===
REM Extract all project IDs as a space-separated string
FOR /F "usebackq delims=" %%A IN (`powershell -Command "Get-Content \"%TEMP%\projects.json\" | ConvertFrom-Json | ForEach-Object { $_.Id } | ForEach-Object { Write-Host -NoNewline $_' ' }"`) DO SET "PROJECT_IDS=%%A"

REM Now iterate over each ID
setlocal enabledelayedexpansion
REM Store initial sample folder count for each project
set "TOTAL_INITIAL=0"
set "TOTAL_FINAL=0"

FOR %%I IN (%PROJECT_IDS%) DO (
    set "INITIAL_COUNT=0"
    if exist "%WORKING_DIR%\%%I" (
        for /f %%C in ('dir /b /ad "%WORKING_DIR%\%%I" ^| find /c /v ""') do set "INITIAL_COUNT=%%C"
    )
    set /a TOTAL_INITIAL+=!INITIAL_COUNT!

    for /f "delims=" %%S in ('powershell -Command "$samples = & '%BASESPACE_CLI%' biosamples list /project-id %%I /format:json /log:%LOG_FILE% | ConvertFrom-Json; if ($samples -eq $null) { Write-Host 0 } elseif ($samples -is [array]) { if ($samples.Length -gt 0) { Write-Host 1 } else { Write-Host 0 } } else { Write-Host 1 }"') do set HAS_SAMPLES=%%S
    if "!HAS_SAMPLES!"=="1" (
        powershell -Command "$samples = & '%BASESPACE_CLI%' biosamples list /project-id %%I /format:json | ConvertFrom-Json; $samples | ConvertTo-Json -Compress | Set-Content -Encoding UTF8 '%TEMP%\\%%I_samples.json'"
        if not exist "%WORKING_DIR%\%%I" (
            mkdir "%WORKING_DIR%\%%I"
        )
        "%BASESPACE_CLI%" project download -i %%I -o "%WORKING_DIR%\%%I" /log:%LOG_FILE% /no-progress-bars
    )

    set "FINAL_COUNT=0"
    if exist "%WORKING_DIR%\%%I" (
        for /f %%C in ('dir /b /ad "%WORKING_DIR%\%%I" ^| find /c /v ""') do set "FINAL_COUNT=%%C"
    )
    set /a TOTAL_FINAL+=!FINAL_COUNT!
    set /a DIFF=FINAL_COUNT-INITIAL_COUNT

    REM Only print debug info if there are any sample folders (initial or final > 0)
    if NOT "!INITIAL_COUNT!!FINAL_COUNT!"=="00" (
        echo ------------------------------------------------------------
    echo Project %%I
        echo ------------------------------------------------------------
    echo     Project %%I: Starting sample folder count: !INITIAL_COUNT!
    REM if "!HAS_SAMPLES!"=="1" echo     Biosamples found for project %%I. Saving JSON...
    echo     Project %%I: Ending sample folder count: !FINAL_COUNT!
    echo     Project %%I: Sample folder count difference: !DIFF!
        echo.
    )
)

REM Show total difference across all projects
set /a TOTAL_DIFF=TOTAL_FINAL-TOTAL_INITIAL
echo     All Projects: Total sample folder count difference: !TOTAL_DIFF!
echo.

REM === COLLECT FOLDER SIZE AFTER EXPORT (if new samples) ===


if "%TOTAL_DIFF%" NEQ "0" (
    setlocal enabledelayedexpansion
    set "TMP_SIZE_AFTER_GB="
    for /f %%S in ('powershell -Command "$size = (Get-ChildItem -Path '\\i110filesmb.hs.it.vumc.io\CAUSAL-DataExport' -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB; [math]::Round($size,2)"') do set "TMP_SIZE_AFTER_GB=%%S"
    if "!TMP_SIZE_AFTER_GB!"=="" set "TMP_SIZE_AFTER_GB=0"
    endlocal & set "SIZE_AFTER_GB=%TMP_SIZE_AFTER_GB%"
) else (
    set "SIZE_AFTER_GB=%SIZE_BEFORE_GB%"
)

REM === CALCULATE SIZE DIFFERENCE (GB) ===
REM Use PowerShell for decimal subtraction
for /f %%D in ('powershell -Command "[math]::Round([decimal]'%SIZE_AFTER_GB%' - [decimal]'%SIZE_BEFORE_GB%',2)"') do set "SIZE_DIFF_GB=%%D"

REM === CAPTURE JOB END TIME ===
set "JOB_END=%DATE% %TIME%"

REM === CALCULATE JOB DURATION (minutes, seconds) ===
for /f %%D in ('powershell -Command "$start = [datetime]::Parse('%JOB_START%'); $end = [datetime]::Parse('%JOB_END%'); $diff = $end - $start; '{0} minutes, {1} seconds' -f $diff.Minutes, $diff.Seconds"') do set "JOB_DURATION=%%D"

REM === CALCULATE JOB DURATION IN HOURS (decimal) ===
for /f %%H in ('powershell -Command "$start = [datetime]::Parse('%JOB_START%'); $end = [datetime]::Parse('%JOB_END%'); $diff = $end - $start; [math]::Round($diff.TotalHours,4)"') do set "JOB_DURATION_HOURS=%%H"

REM === CALCULATE TRANSFER RATE (GB/hour) ===
for /f %%R in ('powershell -Command "if ([decimal]'%JOB_DURATION_HOURS%' -eq 0) { 0 } else { [math]::Round(([decimal]'%SIZE_DIFF_GB%') / ([decimal]'%JOB_DURATION_HOURS%'),2) }"') do set "TRANSFER_RATE_GBPH=%%R"

REM === SUMMARY OUTPUT ===
echo ------------------------------------------------------------
echo Transfer Summary:
echo     Start Time: %JOB_START%
echo     End Time:   %JOB_END%
echo     GB Start:   %SIZE_BEFORE_GB%
echo     GB End:     %SIZE_AFTER_GB%
echo     GB Diff:    %SIZE_DIFF_GB%
echo     Duration:   %JOB_DURATION% (minutes, seconds) [%JOB_DURATION_HOURS% hours]
echo     Rate:       %TRANSFER_RATE_GBPH% GB/hour
echo ------------------------------------------------------------




REM === DISCONNECT X: DRIVE IF CONNECTED ===
net use x: >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    net use x: /delete >nul 2>&1
)



REM === CLEANUP: REMOVE BASESPACE CLI FROM TEMP ===
if /i "%OVERWRITE_BSCLI%"=="true" (
    if exist "%BASESPACE_CLI%" (
        del /f /q "%BASESPACE_CLI%"
    )
)

REM === CLEANUP: REMOVE BASESPACE CONFIG FILE ===
if exist "%USERPROFILE%\.basespace\default.cfg" (
    del /f /q "%USERPROFILE%\.basespace\default.cfg"
)

:END
exit /b