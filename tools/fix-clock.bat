@echo off
setlocal EnableExtensions
title ChaiDesk - fix Windows clock
rem ---------------------------------------------------------------------------
rem  ChaiDesk: make this PC keep the right time. Run once, as administrator.
rem  Safe on a live POS (changes only Windows time settings); the clock may jump
rem  to the correct time while it runs, so run it at a quiet moment.
rem
rem  What it does (settings from Microsoft's Windows Time documentation):
rem   1. Windows Time service on, starting automatically
rem   2. Allow correcting any offset (default refuses more than 15 hours),
rem      sync every hour (default is once a week), turn off Secure Time
rem      Seeding (it can make the clock jump)
rem   3. Time servers: time.google.com, time.cloudflare.com, pool.ntp.org
rem   4. Test that time sync gets through (UDP port 123)
rem   5. Sync now. Only if the test failed: set the clock from a web page's
rem      Date header (HTTPS, else HTTP) hourly, from an admin-only folder
rem  A report is saved to %PUBLIC%\chaidesk-clock-fix.txt
rem ---------------------------------------------------------------------------

set "QUIET="
if /i "%~1"=="/quiet" set "QUIET=1"

net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo  Please right-click this file and choose "Run as administrator".
  echo.
  if not defined QUIET pause
  exit /b 1
)

set "LOG=%PUBLIC%\chaidesk-clock-fix.txt"
set "W32=HKLM\SYSTEM\CurrentControlSet\Services\W32Time"
set "HTTPTIME=http://www.msftconnecttest.com/connecttest.txt"

echo ChaiDesk clock fix - %COMPUTERNAME% > "%LOG%"
call :say "Clock before: %date% %time%"

call :say "1/6 Windows Time service: automatic and running"
sc config w32time start= auto >>"%LOG%" 2>&1
sc query w32time | find "RUNNING" >nul || (
  w32tm /register >>"%LOG%" 2>&1
  net start w32time >>"%LOG%" 2>&1
)

call :say "2/6 Correct any offset, sync hourly, no Secure Time Seeding"
reg add "%W32%\Config" /v MaxPosPhaseCorrection /t REG_DWORD /d 0xFFFFFFFF /f >>"%LOG%" 2>&1
reg add "%W32%\Config" /v MaxNegPhaseCorrection /t REG_DWORD /d 0xFFFFFFFF /f >>"%LOG%" 2>&1
reg add "%W32%\Config" /v UtilizeSslTimeData /t REG_DWORD /d 0 /f >>"%LOG%" 2>&1
reg add "%W32%\TimeProviders\NtpClient" /v SpecialPollInterval /t REG_DWORD /d 3600 /f >>"%LOG%" 2>&1

call :say "3/6 Time servers: time.google.com, time.cloudflare.com, pool.ntp.org"
w32tm /config /manualpeerlist:"time.google.com,0x9 time.cloudflare.com,0x9 pool.ntp.org,0x9" /syncfromflags:manual /update >>"%LOG%" 2>&1
net stop w32time >>"%LOG%" 2>&1
net start w32time >>"%LOG%" 2>&1

call :say "4/6 Testing time sync (UDP port 123)..."
w32tm /stripchart /computer:time.google.com /dataonly /samples:3 > "%TEMP%\chaidesk-ntp.txt" 2>&1
type "%TEMP%\chaidesk-ntp.txt" >> "%LOG%"
findstr /r /c:"[+-][0-9][0-9]*\.[0-9]*s" "%TEMP%\chaidesk-ntp.txt" >nul
if errorlevel 1 goto ntp_blocked

call :say "    OK: time sync gets through."
call :say "5/6 Syncing now"
w32tm /resync /force >>"%LOG%" 2>&1
schtasks /delete /tn "ChaiDesk clock" /f >nul 2>&1
goto finish

:ntp_blocked
call :say "    BLOCKED: time sync (UDP 123) does not get through from this PC."
call :say "5/6 Setting the clock from the web instead, and every hour from now on"
rem A scheduled task command is limited to 261 characters, so the clock step lives in its own file,
rem in a folder only Administrators and SYSTEM can write (the task runs it as SYSTEM).
set "PSDIR=%ProgramData%\ChaiDesk"
set "PS1=%PSDIR%\set-clock.ps1"
if not exist "%PSDIR%" mkdir "%PSDIR%"
icacls "%PSDIR%" /setowner *S-1-5-32-544 /T /C >>"%LOG%" 2>&1
icacls "%PSDIR%" /inheritance:r /grant:r *S-1-5-32-544:(OI)(CI)F *S-1-5-18:(OI)(CI)F /T /C >>"%LOG%" 2>&1
> "%PS1%" echo [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
>>"%PS1%" echo try { $r = Invoke-WebRequest -UseBasicParsing -Method Head -Uri 'https://www.google.com' -TimeoutSec 20 } catch { $r = Invoke-WebRequest -UseBasicParsing -Method Head -Uri '%HTTPTIME%' -TimeoutSec 20 }
>>"%PS1%" echo Set-Date -Date ([DateTime]::Parse($r.Headers['Date']).ToLocalTime()) ^| Out-Null
>>"%PS1%" echo 'Clock set from web: ' + (Get-Date)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" >>"%LOG%" 2>&1
if errorlevel 1 call :say "    Could not reach %HTTPTIME% - check the internet and run this again."
schtasks /create /tn "ChaiDesk clock" /sc hourly /ru SYSTEM /rl HIGHEST /f /tr "powershell -NoProfile -ExecutionPolicy Bypass -File \"%PS1%\"" >>"%LOG%" 2>&1
if errorlevel 1 (call :say "    Could not create the hourly task.") else (call :say "    Hourly task ChaiDesk clock created.")

:finish
call :say "6/6 Result"
w32tm /query /status >>"%LOG%" 2>&1
call :say "Clock after: %date% %time%"
echo.
echo  Done. Check the time in the corner of the screen.
echo  Report saved to %LOG%
echo  Send a photo of this window, or that file, to support if anything failed.
echo.
if not defined QUIET pause
exit /b 0

:say
echo %~1
>>"%LOG%" echo %~1
exit /b 0
