@echo off
setlocal EnableExtensions
title ChaiDesk - fix Windows clock
rem ---------------------------------------------------------------------------
rem  ChaiDesk: make this PC keep the right time. Run once, as administrator.
rem  Safe on a live POS (changes only Windows time settings); the clock may jump
rem  to the correct time while it runs, so run it at a quiet moment.
rem  ChaiDesk's "Fix clock" button (3.4.8+) does the same from inside the app.
rem
rem  What it does (settings from Microsoft's Windows Time documentation):
rem   1. Windows Time service always on (by default a shop PC only checks the
rem      time on Sundays at 1 AM, and skips it if the PC is off then)
rem   2. Allow correcting any offset (default refuses more than 15 hours),
rem      sync every hour (default is once a week), turn off Secure Time
rem      Seeding (it can make the clock jump)
rem   3. Time servers: time.google.com, time.cloudflare.com, pool.ntp.org
rem   4. Test that time sync gets through (UDP port 123)
rem   5. Sync now. Only if the test failed: set the clock from a web page's
rem      Date header, and every hour from an HTTPS-only scheduled task
rem  Results are shown on screen only (no file is written as administrator).
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

set "W32=HKLM\SYSTEM\CurrentControlSet\Services\W32Time"

echo Clock before: %date% %time%

echo 1/6 Windows Time service: always running (not just Sundays 1 AM)
rem Microsoft KB 2385818: on a workgroup PC the service stops itself after every boot even when set to
rem Automatic, and Windows only syncs from a Sunday 1:00 AM task. Removing the trigger keeps it running.
sc triggerinfo w32time delete >nul
sc config w32time start= auto >nul
sc query w32time | find "RUNNING" >nul || (
  w32tm /register >nul
  net start w32time >nul
)

echo 2/6 Correct any offset, sync hourly, no Secure Time Seeding
reg add "%W32%\Config" /v MaxPosPhaseCorrection /t REG_DWORD /d 0xFFFFFFFF /f >nul
reg add "%W32%\Config" /v MaxNegPhaseCorrection /t REG_DWORD /d 0xFFFFFFFF /f >nul
reg add "%W32%\Config" /v UtilizeSslTimeData /t REG_DWORD /d 0 /f >nul
reg add "%W32%\TimeProviders\NtpClient" /v SpecialPollInterval /t REG_DWORD /d 3600 /f >nul

echo 3/6 Time servers: time.google.com, time.cloudflare.com, pool.ntp.org
w32tm /config /manualpeerlist:"time.google.com,0x9 time.cloudflare.com,0x9 pool.ntp.org,0x9" /syncfromflags:manual /update >nul
net stop w32time >nul 2>&1
net start w32time >nul

echo 4/6 Testing time sync (UDP port 123)...
for /f "delims=" %%L in ('w32tm /stripchart /computer:time.google.com /dataonly /samples:3 2^>^&1 ^| findstr /r /c:"[+-][0-9][0-9]*\.[0-9]*s"') do set "NTPOK=1"
if not defined NTPOK goto ntp_blocked

echo     OK: time sync gets through.
echo 5/6 Syncing now
w32tm /resync /force
schtasks /delete /tn "ChaiDesk clock" /f >nul 2>&1
goto finish

:ntp_blocked
echo     BLOCKED: time sync (UDP 123) does not get through from this PC.
echo 5/6 Setting the clock from the web, and every hour from an HTTPS-only task
rem The commands are passed inline (encoded); no script file is left for a SYSTEM task to run.
powershell -NoProfile -NonInteractive -EncodedCommand WwBOAGUAdAAuAFMAZQByAHYAaQBjAGUAUABvAGkAbgB0AE0AYQBuAGEAZwBlAHIAXQA6ADoAUwBlAGMAdQByAGkAdAB5AFAAcgBvAHQAbwBjAG8AbAAgAD0AIAAiAFQAbABzADEAMgAiAAoAdAByAHkAIAB7ACAAJAByACAAPQAgAEkAbgB2AG8AawBlAC0AVwBlAGIAUgBlAHEAdQBlAHMAdAAgAC0AVQBzAGUAQgBhAHMAaQBjAFAAYQByAHMAaQBuAGcAIAAtAE0AZQB0AGgAbwBkACAASABlAGEAZAAgAC0AVQByAGkAIAAiAGgAdAB0AHAAcwA6AC8ALwB3AHcAdwAuAGcAbwBvAGcAbABlAC4AYwBvAG0AIgAgAC0AVABpAG0AZQBvAHUAdABTAGUAYwAgADIAMAAgAH0AIABjAGEAdABjAGgAIAB7ACAAJAByACAAPQAgAEkAbgB2AG8AawBlAC0AVwBlAGIAUgBlAHEAdQBlAHMAdAAgAC0AVQBzAGUAQgBhAHMAaQBjAFAAYQByAHMAaQBuAGcAIAAtAE0AZQB0AGgAbwBkACAASABlAGEAZAAgAC0AVQByAGkAIAAiAGgAdAB0AHAAOgAvAC8AdwB3AHcALgBtAHMAZgB0AGMAbwBuAG4AZQBjAHQAdABlAHMAdAAuAGMAbwBtAC8AYwBvAG4AbgBlAGMAdAB0AGUAcwB0AC4AdAB4AHQAIgAgAC0AVABpAG0AZQBvAHUAdABTAGUAYwAgADIAMAAgAH0ACgBTAGUAdAAtAEQAYQB0AGUAIAAtAEQAYQB0AGUAIAAoAFsARABhAHQAZQBUAGkAbQBlAF0AOgA6AFAAYQByAHMAZQAoACQAcgAuAEgAZQBhAGQAZQByAHMAWwAiAEQAYQB0AGUAIgBdACkALgBUAG8ATABvAGMAYQBsAFQAaQBtAGUAKAApACkAIAB8ACAATwB1AHQALQBOAHUAbABsAAoAIgBDAGwAbwBjAGsAIABzAGUAdAAgAGYAcgBvAG0AIAB0AGgAZQAgAHcAZQBiADoAIAAiACAAKwAgACgARwBlAHQALQBEAGEAdABlACkA
powershell -NoProfile -NonInteractive -EncodedCommand JABhACAAPQAgAE4AZQB3AC0AUwBjAGgAZQBkAHUAbABlAGQAVABhAHMAawBBAGMAdABpAG8AbgAgAC0ARQB4AGUAYwB1AHQAZQAgACIAcABvAHcAZQByAHMAaABlAGwAbAAuAGUAeABlACIAIAAtAEEAcgBnAHUAbQBlAG4AdAAgACIALQBOAG8AUAByAG8AZgBpAGwAZQAgAC0ATgBvAG4ASQBuAHQAZQByAGEAYwB0AGkAdgBlACAALQBXAGkAbgBkAG8AdwBTAHQAeQBsAGUAIABIAGkAZABkAGUAbgAgAC0ARQBuAGMAbwBkAGUAZABDAG8AbQBtAGEAbgBkACAAVwB3AEIATwBBAEcAVQBBAGQAQQBBAHUAQQBGAE0AQQBaAFEAQgB5AEEASABZAEEAYQBRAEIAagBBAEcAVQBBAFUAQQBCAHYAQQBHAGsAQQBiAGcAQgAwAEEARQAwAEEAWQBRAEIAdQBBAEcARQBBAFoAdwBCAGwAQQBIAEkAQQBYAFEAQQA2AEEARABvAEEAVQB3AEIAbABBAEcATQBBAGQAUQBCAHkAQQBHAGsAQQBkAEEAQgA1AEEARgBBAEEAYwBnAEIAdgBBAEgAUQBBAGIAdwBCAGoAQQBHADgAQQBiAEEAQQBnAEEARAAwAEEASQBBAEEAaQBBAEYAUQBBAGIAQQBCAHoAQQBEAEUAQQBNAGcAQQBpAEEAQQBvAEEASgBBAEIAeQBBAEMAQQBBAFAAUQBBAGcAQQBFAGsAQQBiAGcAQgAyAEEARwA4AEEAYQB3AEIAbABBAEMAMABBAFYAdwBCAGwAQQBHAEkAQQBVAGcAQgBsAEEASABFAEEAZABRAEIAbABBAEgATQBBAGQAQQBBAGcAQQBDADAAQQBWAFEAQgB6AEEARwBVAEEAUQBnAEIAaABBAEgATQBBAGEAUQBCAGoAQQBGAEEAQQBZAFEAQgB5AEEASABNAEEAYQBRAEIAdQBBAEcAYwBBAEkAQQBBAHQAQQBFADAAQQBaAFEAQgAwAEEARwBnAEEAYgB3AEIAawBBAEMAQQBBAFMAQQBCAGwAQQBHAEUAQQBaAEEAQQBnAEEAQwAwAEEAVgBRAEIAeQBBAEcAawBBAEkAQQBBAGkAQQBHAGcAQQBkAEEAQgAwAEEASABBAEEAYwB3AEEANgBBAEMAOABBAEwAdwBCADMAQQBIAGMAQQBkAHcAQQB1AEEARwBjAEEAYgB3AEIAdgBBAEcAYwBBAGIAQQBCAGwAQQBDADQAQQBZAHcAQgB2AEEARwAwAEEASQBnAEEAZwBBAEMAMABBAFYAQQBCAHAAQQBHADAAQQBaAFEAQgB2AEEASABVAEEAZABBAEIAVABBAEcAVQBBAFkAdwBBAGcAQQBEAEkAQQBNAEEAQQBLAEEARgBNAEEAWgBRAEIAMABBAEMAMABBAFIAQQBCAGgAQQBIAFEAQQBaAFEAQQBnAEEAQwAwAEEAUgBBAEIAaABBAEgAUQBBAFoAUQBBAGcAQQBDAGcAQQBXAHcAQgBFAEEARwBFAEEAZABBAEIAbABBAEYAUQBBAGEAUQBCAHQAQQBHAFUAQQBYAFEAQQA2AEEARABvAEEAVQBBAEIAaABBAEgASQBBAGMAdwBCAGwAQQBDAGcAQQBKAEEAQgB5AEEAQwA0AEEAUwBBAEIAbABBAEcARQBBAFoAQQBCAGwAQQBIAEkAQQBjAHcAQgBiAEEAQwBJAEEAUgBBAEIAaABBAEgAUQBBAFoAUQBBAGkAQQBGADAAQQBLAFEAQQB1AEEARgBRAEEAYgB3AEIATQBBAEcAOABBAFkAdwBCAGgAQQBHAHcAQQBWAEEAQgBwAEEARwAwAEEAWgBRAEEAbwBBAEMAawBBAEsAUQBBAGcAQQBIAHcAQQBJAEEAQgBQAEEASABVAEEAZABBAEEAdABBAEUANABBAGQAUQBCAHMAQQBHAHcAQQAiAAoAJAB0ACAAPQAgAE4AZQB3AC0AUwBjAGgAZQBkAHUAbABlAGQAVABhAHMAawBUAHIAaQBnAGcAZQByACAALQBPAG4AYwBlACAALQBBAHQAIAAoAEcAZQB0AC0ARABhAHQAZQApACAALQBSAGUAcABlAHQAaQB0AGkAbwBuAEkAbgB0AGUAcgB2AGEAbAAgACgATgBlAHcALQBUAGkAbQBlAFMAcABhAG4AIAAtAEgAbwB1AHIAcwAgADEAKQAKAFIAZQBnAGkAcwB0AGUAcgAtAFMAYwBoAGUAZAB1AGwAZQBkAFQAYQBzAGsAIAAtAFQAYQBzAGsATgBhAG0AZQAgACIAQwBoAGEAaQBEAGUAcwBrACAAYwBsAG8AYwBrACIAIAAtAEEAYwB0AGkAbwBuACAAJABhACAALQBUAHIAaQBnAGcAZQByACAAJAB0ACAALQBVAHMAZQByACAAIgBTAFkAUwBUAEUATQAiACAALQBSAHUAbgBMAGUAdgBlAGwAIABIAGkAZwBoAGUAcwB0ACAALQBGAG8AcgBjAGUAIAB8ACAATwB1AHQALQBOAHUAbABsAAoAIgBIAG8AdQByAGwAeQAgAHQAYQBzAGsAIABDAGgAYQBpAEQAZQBzAGsAIABjAGwAbwBjAGsAIABjAHIAZQBhAHQAZQBkACIA

:finish
echo 6/6 Result
w32tm /query /status
echo Clock after: %date% %time%
echo.
echo  Done. Check the time in the corner of the screen.
echo  If anything failed, send a photo of this window to support.
echo.
if not defined QUIET pause
exit /b 0
