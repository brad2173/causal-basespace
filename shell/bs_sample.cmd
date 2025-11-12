@REM Initialize Error Failure Boolean
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
set BASESPACE_API_KEY=2ddf8681de154d4d94e7b711aca134dc
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
        echo [DEBUG] ERROR: Failed to map network drive X:. Check network connectivity and permissions.
        echo [DEBUG] ERROR: Failed to map network drive X:. Check network connectivity and permissions. >> "%TEMP%\%LOG_FILE%"
    )
    if not exist "X:\" (
        echo [DEBUG] ERROR: X: drive still not found after mapping attempt.
        echo [DEBUG] ERROR: X: drive still not found after mapping attempt. >> "%TEMP%\%LOG_FILE%"
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
            echo [ERROR] Failed to create directory: %%D
            echo [ERROR] Failed to create directory: %%D >> "%LOG_FILE%"
            goto END
        )
    )
)
echo [STEP] All required directories validated and ready.



REM PowerShell command to download executable
echo [STEP] Downloading BaseSpace CLI executable...

start /wait powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://launch.basespace.illumina.com/CLI/latest/amd64-windows/bs.exe' -OutFile '%TEMP%\bs.exe'"
if %ERRORLEVEL% NEQ 0 (
    echo [%DATE% %TIME%] ERROR: Failed to download bs.exe >> "%LOG_FILE%"
    goto END
)
set BASESPACE_CLI=%TEMP%\bs.exe



REM Establish the executable (example: check version)
echo [STEP] Checking BaseSpace CLI version...
REM Establish the executable (example: check version)
powershell -Command "& '%BASESPACE_CLI%' --version"
if %ERRORLEVEL% NEQ 0 (
    echo [%DATE% %TIME%] ERROR: bs.exe failed to run. >> "%LOG_FILE%"
    goto END
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
    echo [%DATE% %TIME%] ERROR: bs.exe failed to run. >> "%LOG_FILE%"
    goto END
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

@REM REM Ensure LOCAL_DIR exists before writing sample_list.txt
@REM if not exist "%LOCAL_DIR%" (
@REM     echo [ERROR] LOCAL_DIR not found: %LOCAL_DIR%
@REM     echo [ERROR] LOCAL_DIR not found: %LOCAL_DIR% >> "%LOG_FILE%"
@REM     mkdir "%LOCAL_DIR%"
@REM )
@REM echo [STEP] Step 119
@REM REM Ensure LOG_FILE directory exists before writing
@REM for %%I in ("%LOG_FILE%") do (
@REM     set "_LOGDIR=%%~dpI"
@REM     if not exist "%_LOGDIR%" (
@REM         echo [ERROR] LOG directory not found: %_LOGDIR%
@REM         echo [ERROR] LOG directory not found: %_LOGDIR% >> "%LOG_FILE%"
@REM         mkdir "%_LOGDIR%"
@REM     )
@REM )
@REM echo [STEP] Step 129
@REM echo [%LOGDATE% %TIME%] Listing samples in BaseSpace project %PROJECT_ID%... >> "%LOG_FILE%"
@REM REM Run biosample list with correct flag and filter output to only BioSampleName and Id
@REM "%BASESPACE_CLI%" biosample list /project-id %PROJECT_ID% | findstr /R /C:"^[|]" | findstr /V /C:"ContainerName" /C:"ContainerPosition" /C:"Status" > "%LOCAL_DIR%\sample_list.txt"
@REM if %ERRORLEVEL% NEQ 0 (
@REM     echo [%LOGDATE% %TIME%] ERROR: Failed to list samples. >> "%LOG_FILE%"
@REM     goto END
@REM )
@REM echo [%LOGDATE% %TIME%] Sample list saved to %LOCAL_DIR%\sample_list.txt >> "%LOG_FILE%"


@REM REM Format sample_list.txt into a clean ASCII table for review/reprocessing
@REM powershell -Command "$lines = Get-Content '%LOCAL_DIR%\sample_list.txt' | Where-Object { $_.Trim() -ne '' }; $splitLines = $lines | ForEach-Object { ($_ -split '\|') }; $maxCols = ($splitLines | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum; $widths = @(for ($i=0; $i -lt $maxCols; $i++) { ($splitLines | ForEach-Object { if ($i -lt $_.Count) { ([string]$_[$i]).Trim() } else { '' } }) | Measure-Object -Property Length -Maximum | Select-Object -ExpandProperty Maximum }); $formatLine = { param($arr) ($arr | ForEach-Object { ([string]$_).Trim().PadRight($widths[$arr.IndexOf($_)]) }) -join ' | ' }; $asciiTable = $splitLines | ForEach-Object { (& $formatLine $_) + \"`r\" }; $asciiTable | Set-Content -NoNewline '%LOCAL_DIR%\\sample_list_ascii.txt'"
@REM echo [%LOGDATE% %TIME%] Formatted ASCII table saved to %LOCAL_DIR%\sample_list_ascii.txt >> "%LOG_FILE%"


@REM echo [STEP] Step 155

@REM REM === 2. Download new/updated content ===
@REM echo [STEP] Downloading new or updated content...
@REM echo [%LOGDATE% %TIME%] Starting download from BaseSpace project %PROJECT_ID%... >> "%LOG_FILE%"
@REM "%BASESPACE_CLI%" project download -i %PROJECT_ID% "%LOCAL_DIR%" >> "%LOG_FILE%"
@REM if %ERRORLEVEL% NEQ 0 (
@REM     echo [%LOGDATE% %TIME%] ERROR: Failed to download project data. >> "%LOG_FILE%"
@REM     goto END
@REM )


@REM echo [STEP] Step 167

@REM REM === 3. Validate download ===
@REM echo [STEP] Validating downloaded files...
@REM echo [%LOGDATE% %TIME%] Validating downloaded files... >> "%LOG_FILE%"

@REM REM 3a. Check for CLI errors
@REM echo [STEP] Checking for CLI errors in log...
@REM findstr /i "error" "%LOG_FILE%" >nul
@REM if %ERRORLEVEL% EQU 0 (
@REM     echo [%LOGDATE% %TIME%] ERROR: Download encountered errors. Aborting further actions. >> "%LOG_FILE%"
@REM     goto END
@REM )

@REM REM 3b. Verify MD5 checksums
@REM echo [STEP] Verifying MD5 checksums...
@REM set MD5_ERRORS=0
@REM for /R "%LOCAL_DIR%" %%F in (*.md5sum) do (
@REM     certutil -hashfile "%%~dpnF" MD5 | findstr /i /v "MD5" >nul
@REM     if %ERRORLEVEL% NEQ 0 (
@REM         echo [%LOGDATE% %TIME%] ERROR: MD5 checksum failed for %%F >> "%LOG_FILE%"
@REM         set MD5_ERRORS=1
@REM     )
@REM )
@REM if %MD5_ERRORS% NEQ 0 (
@REM     echo [%LOGDATE% %TIME%] ERROR: One or more MD5 checks failed. Aborting further actions. >> "%LOG_FILE%"
@REM     goto END
@REM )

@REM REM 3c. Compare file counts and sizes (optional)
@REM echo [STEP] Comparing file counts and sizes...
@REM REM Ensure LOCAL_DIR exists before writing downloaded_count.txt
@REM if not exist "%LOCAL_DIR%" (
@REM     mkdir "%LOCAL_DIR%"
@REM )
@REM dir /b /s "%LOCAL_DIR%" | find /c /v "" > "%LOCAL_DIR%\downloaded_count.txt"
@REM set /p DOWNLOADED_COUNT=<"%LOCAL_DIR%\downloaded_count.txt"
@REM for /f %%A in ('find /c /v "" ^< "%LOCAL_DIR%\sample_list.txt"') do set EXPECTED_COUNT=%%A
@REM echo [%LOGDATE% %TIME%] Downloaded file count: %DOWNLOADED_COUNT%, Expected: %EXPECTED_COUNT% >> "%LOG_FILE%"
@REM if %DOWNLOADED_COUNT% LSS %EXPECTED_COUNT% (
@REM     echo [%LOGDATE% %TIME%] WARNING: Fewer files downloaded than expected. >> "%LOG_FILE%"
@REM )

@REM REM 3d. Confirm expected sample IDs (optional)
@REM echo [STEP] Confirming expected sample IDs...
@REM if exist "%EXPECTED_SAMPLES%" (
@REM     for /f "delims=" %%S in (%EXPECTED_SAMPLES%) do (
@REM         findstr /c:"%%S" "%LOCAL_DIR%\sample_list.txt" >nul
@REM         if %ERRORLEVEL% NEQ 0 (
@REM             echo [%LOGDATE% %TIME%] WARNING: Expected sample %%S not found in download. >> "%LOG_FILE%"
@REM         )
@REM     )
@REM )

@REM REM === 4. Move downloaded samples to completed directory ===
@REM echo [STEP] Moving downloaded samples to completed directory...
@REM REM Ensure COMPLETED_DIR exists before moving files
@REM if not exist "%COMPLETED_DIR%" (
@REM     echo [ERROR] COMPLETED_DIR not found: %COMPLETED_DIR%
@REM     echo [ERROR] COMPLETED_DIR not found: %COMPLETED_DIR% >> "%LOG_FILE%"
@REM     mkdir "%COMPLETED_DIR%"
@REM )
@REM echo [%LOGDATE% %TIME%] Moving downloaded samples to completed directory... >> "%LOG_FILE%"
@REM if not exist "%COMPLETED_DIR%" (
@REM     mkdir "%COMPLETED_DIR%"
@REM )
@REM xcopy "%LOCAL_DIR%\*" "%COMPLETED_DIR%\" /E /Y
@REM echo [%LOGDATE% %TIME%] Move process complete. >> "%LOG_FILE%"

@REM echo [DEBUG] Starting network drive mapping...
@REM echo [DEBUG] Starting network drive mapping... >> "%LOG_FILE%"
@REM REM === 4. Delete content from BaseSpace (after validation) ===
@REM echo [STEP] (Optional) Deleting content from BaseSpace...
@REM echo [DEBUG] Network drive mapped.
@REM echo [DEBUG] Network drive mapped. >> "%LOG_FILE%"
@REM REM echo [%DATE% %TIME%] Deleting samples from BaseSpace project %PROJECT_ID%... >> "%LOG_FILE%"
@REM REM for /f "tokens=1" %%I in (%LOCAL_DIR%\sample_list.txt) do (
@REM echo [DEBUG] Setting up working directory...
@REM echo [DEBUG] Setting up working directory... >> "%LOG_FILE%"
@REM REM     echo [%DATE% %TIME%] Deleting sample %%I from BaseSpace... >> "%LOG_FILE%"
@REM REM     rem bs biosample delete -i %%I >> "%LOG_FILE%"
@REM REM )
@REM REM echo [%DATE% %TIME%] Deletion process complete. >> "%LOG_FILE%"
@REM echo [DEBUG] Working directory ready: %WORKING_DIR%
@REM echo [DEBUG] Working directory ready: %WORKING_DIR% >> "%LOG_FILE%"

@REM REM === 5. Log completion ===
@REM echo [STEP] Logging completion of daily sync...
@REM echo [%LOGDATE% %TIME%] BaseSpace daily sync completed successfully. >> "%LOG_FILE%"

@REM :END




@REM @echo offREM =============================
@REM REM BaseSpace Project Metadata Query
@REM REM =============================

@REM REM 1. List Project Metadata
@REM REM This command retrieves general metadata for the project, including name, owner, and creation date.
@REM "%BASESPACE_CLI%" project get --id 468727260

@REM REM 2. Count Number of Biosamples in Project
@REM REM This command lists all biosamples and counts the number of samples in the project.
@REM "%BASESPACE_CLI%" biosample list --project-id 468727260 > biosamples.json
@REM findstr /R /C:"\"Id\":" biosamples.json | find /c /v ""

@REM REM 3. List All Biosamples (with attributes)
@REM REM This command displays all biosamples and their metadata.
@REM "%BASESPACE_CLI%" biosample list --project-id 468727260

@REM REM 4. Count Number of FASTQ Files in Project
@REM REM This command lists all FASTQ files and counts them.
@REM "%BASESPACE_CLI%" file list --project-id 468727260 --extension .fastq.gz > fastq_files.json
@REM findstr /R /C:"\"Id\":" fastq_files.json | find /c /v ""

@REM REM 5. Count Number of BAM Files in Project
@REM REM This command lists all BAM files and counts them.
@REM "%BASESPACE_CLI%" file list --project-id 468727260 --extension .bam > bam_files.json
@REM findstr /R /C:"\"Id\":" bam_files.json | find /c /v ""

@REM REM 6. List All Files with Metadata
@REM REM This command lists all files in the project, including metadata such as name, type, size, and biosample association.
@REM "%BASESPACE_CLI%" file list --project-id 468727260

@REM REM 7. Show Available Metadata Fields for Biosamples
@REM REM This command displays all metadata fields for biosamples in JSON format.
@REM "%BASESPACE_CLI%" biosample list --project-id 468727260 --output-format json | more

@REM REM 8. Show Available Metadata Fields for Files
@REM REM This command displays all metadata fields for files in JSON format.
@REM "%BASESPACE_CLI%" file list --project-id 468727260 --output-format json | more

@REM REM =============================
@REM REM Summary of Metadata Options
@REM REM =============================
@REM REM The bs CLI offers:
@REM REM - Project metadata (bs project get)
@REM REM - Biosample metadata (bs biosample list)
@REM REM - File metadata (bs file list)
@REM REM - Filtering by file extension (--extension)
@REM REM - Output formats (--output-format json for parsing)
@REM REM - Association between files and biosamples

@REM REM =============================
@REM REM PowerShell Alternative for Counting
@REM REM =============================
@REM REM If you prefer PowerShell for counting:
@REM REM (bs biosample list --project-id 468727260 | Select-String '"Id":').Count
@REM REM (bs file list --project-id 468727260 --extension .fastq.gz | Select-String '"Id":').Count
@REM REM (bs file list --project-id 468727260 --extension .bam | Select-String '"Id":').Count

@REM REM =============================
@REM REM End of Script
@REM REM =============================



@REM REM Remove the downloaded executable from working directory
@REM if exist "%WORKING_DIR%\bs.exe" (
@REM rem     del "%WORKING_DIR%\bs.exe"
@REM )

@REM REM rmdir /s /q "%USERPROFILE%\.basespace"
@REM set BASESPACE_API_KEY=
@REM exit /b