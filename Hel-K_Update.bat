@echo off
if /I "%~1"=="__run__" goto :run
setlocal
cd /d "%~dp0"
set "TEMPCOPY=%TEMP%\Hel-K_Update_%RANDOM%.bat"
copy /y "%~f0" "%TEMPCOPY%" >nul
call "%TEMPCOPY%" __run__ & del "%TEMPCOPY%" >nul 2>&1 & exit /b

:run
REM Tout ce qui suit s'execute depuis la copie temporaire ci-dessus.
REM Le fichier .bat original (celui que l'utilisateur a lance) peut donc
REM etre ecrase sans probleme par la mise a jour, meme s'il s'agit de
REM ce script lui-meme : cmd.exe ne lit plus jamais ce fichier-la.
echo Downloading Hel-K...
REM Create multi line command files
> temp.ps1 echo $web = New-Object Net.WebClient
>> temp.ps1 echo [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
>> temp.ps1 echo $web.DownloadFile('https://github.com/Helwor/New-Hel-K/archive/main.zip', 'luaui.zip')
>> temp.ps1 echo $shell = New-Object -ComObject Shell.Application
>> temp.ps1 echo $shell.Namespace((Get-Location).Path).CopyHere($shell.Namespace((Get-Item 'luaui.zip').FullName).Items(), 16)
>> temp.ps1 echo Start-Sleep 2
>> temp.ps1 echo Remove-Item 'luaui.zip'
powershell -ExecutionPolicy Bypass -File temp.ps1
del temp.ps1
if errorlevel 1 (
    echo Download failed. Aborting.
    pause
    exit /b 1
)
if exist New-Hel-K-main\.gitignore del New-Hel-K-main\.gitignore
if not exist New-Hel-K-main (
    echo Failed to extract package. Aborting.
    pause
    exit /b 1
)
> temp.ps1 echo if (Test-Path 'helk_manifest.txt') {
>> temp.ps1 echo $manifest = gc 'helk_manifest.txt'
>> temp.ps1 echo     Write-Host 'Checking removed files...'
>> temp.ps1 echo     $newDir = 'New-Hel-K-main'
>> temp.ps1 echo     $newFiles = @{}
>> temp.ps1 echo     gci $newDir -File -Recurse ^| ForEach-Object { $r = $_.FullName.Substring((gi $newDir).FullName.Length+1); $newFiles[$r] = 1 }
>> temp.ps1 echo     foreach ($f in $manifest) {
>> temp.ps1 echo         if (!$newFiles.ContainsKey($f) -and (Test-Path $f)) {
>> temp.ps1 echo             $n = 1
>> temp.ps1 echo             $fullPath = (Resolve-Path $f).Path
>> temp.ps1 echo             $newFullPath = $fullPath + '.removed' + $n
>> temp.ps1 echo             while (Test-Path $newFullPath) { $n++; $newFullPath = $fullPath + '.removed' + $n }
>> temp.ps1 echo             Move-Item -Path $fullPath -Destination $newFullPath
>> temp.ps1 echo             Write-Host 'REMOVED: ' $f -ForegroundColor Red
>> temp.ps1 echo         }
>> temp.ps1 echo     }
>> temp.ps1 echo }
powershell -ExecutionPolicy Bypass -File temp.ps1
del temp.ps1
echo Checking existing files...
> temp.ps1 echo [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
>> temp.ps1 echo $owner = 'Helwor'
>> temp.ps1 echo $repo = 'New-Hel-K'
>> temp.ps1 echo $ghHeaders = @{ 'User-Agent' = 'PowerShell' }
>> temp.ps1 echo if ($env:GITHUB_TOKEN) { $ghHeaders['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
>> temp.ps1 echo function Get-LastCommitInfo($relPath) {
>> temp.ps1 echo     $ghPath = $relPath -replace '\\','/'
>> temp.ps1 echo     $uri = "https://api.github.com/repos/$owner/$repo/commits?path=" + [uri]::EscapeDataString($ghPath) + "&per_page=1&sha=main"
>> temp.ps1 echo     try {
>> temp.ps1 echo         $c = @(Invoke-RestMethod -Uri $uri -Headers $ghHeaders)
>> temp.ps1 echo         if ($c.Count -gt 0) {
>> temp.ps1 echo             $msg = ($c[0].commit.message -split "`n")[0]
>> temp.ps1 echo             $sha = $($c[0].sha.Substring(0,7))
>> temp.ps1 echo             $date = $c[0].commit.author.date
>> temp.ps1 echo             $date = $date -replace 'T',' '
>> temp.ps1 echo             $date = $date -replace 'Z',''
>> temp.ps1 echo             return "$date - $msg ($sha)"
>> temp.ps1 echo         } else {
>> temp.ps1 echo             return 'no commit found for this file'
>> temp.ps1 echo         }
>> temp.ps1 echo     } catch {
>> temp.ps1 echo         return 'commit info unavailable (rate limit or network error)'
>> temp.ps1 echo     }
>> temp.ps1 echo }
>> temp.ps1 echo function Show-CommitsSince($relPath, $localDate) {
>> temp.ps1 echo     $ghPath = $relPath -replace '\\','/'
>> temp.ps1 echo     $uri = "https://api.github.com/repos/$owner/$repo/commits?path=" + [uri]::EscapeDataString($ghPath) + "&per_page=30&sha=main"
>> temp.ps1 echo     try {
>> temp.ps1 echo         $raw = Invoke-RestMethod -Uri $uri -Headers $ghHeaders
>> temp.ps1 echo         if ($null -eq $raw) { $c = @() } elseif ($raw -is [array]) { $c = $raw } else { $c = @($raw) }
>> temp.ps1 echo         if ($c.Count -eq 0) {
>> temp.ps1 echo             Write-Host '    No commit found for this file' -ForegroundColor Cyan
>> temp.ps1 echo             return
>> temp.ps1 echo         }
>> temp.ps1 echo         $localUtc = $localDate.ToUniversalTime()
>> temp.ps1 echo         $newer = @($c ^| Where-Object { [datetime]$_.commit.author.date -gt $localUtc })
>> temp.ps1 echo         if ($newer.Count -gt 0) {
>> temp.ps1 echo             Write-Host "    $($newer.Count) commit(s) since your local version:" -ForegroundColor Cyan
>> temp.ps1 echo             foreach ($item in $newer) {
>> temp.ps1 echo                 $msg = ($item.commit.message -split "`n")[0]
>> temp.ps1 echo                 $sha = $($item.sha.Substring(0,7))
>> temp.ps1 echo                 $date = $($item.commit.author.date)
>> temp.ps1 echo                 $date = $date -replace 'T',' '
>> temp.ps1 echo                 $date = $date -replace 'Z',''
>> temp.ps1 echo                 Write-Host "      $date - $msg ($sha)" -ForegroundColor Cyan
>> temp.ps1 echo             }
>> temp.ps1 echo         } else {
>> temp.ps1 echo             $msg = ($c[0].commit.message -split "`n")[0]
>> temp.ps1 echo             $sha = $($c[0].sha.Substring(0,7))
>> temp.ps1 echo             $date = $($c[0].commit.author.date)
>> temp.ps1 echo             $date = $date -replace 'T',' '
>> temp.ps1 echo             $date = $date -replace 'Z',''
>> temp.ps1 echo             Write-Host "    Local file modified by user, set back to last commit:" -ForegroundColor Cyan
>> temp.ps1 echo             Write-Host "      $date - $msg ($sha)" -ForegroundColor Cyan
>> temp.ps1 echo         }
>> temp.ps1 echo     } catch {
>> temp.ps1 echo         Write-Host '    commit info unavailable (rate limit or network error)' -ForegroundColor Cyan
>> temp.ps1 echo     }
>> temp.ps1 echo }
>> temp.ps1 echo $d = (gi 'New-Hel-K-main').FullName
>> temp.ps1 echo gci 'New-Hel-K-main' -File -Recurse ^| ForEach-Object {
>> temp.ps1 echo     $f = $_.FullName
>> temp.ps1 echo     $r = $f.Substring($d.Length+1)
>> temp.ps1 echo     $t = $r
>> temp.ps1 echo     if (Test-Path $t) {
>> temp.ps1 echo         $c1 = [System.IO.File]::ReadAllText($f) -replace "`r`n?", "`n"
>> temp.ps1 echo         $c2 = [System.IO.File]::ReadAllText($t) -replace "`r`n?", "`n"
>> temp.ps1 echo         if ($c1 -ne $c2) {
>> temp.ps1 echo             $localDate = (Get-Item $t).LastWriteTime
>> temp.ps1 echo             $n = 1
>> temp.ps1 echo             while (Test-Path ($t + '.backup' + $n)) { $n++ }
>> temp.ps1 echo             $backup = $t + '.backup' + $n
>> temp.ps1 echo             mv $t $backup
>> temp.ps1 echo             cp $f $t
>> temp.ps1 echo             Write-Host 'UPDATED: ' $r ' (created backup' $n ')' -ForegroundColor Yellow
>> temp.ps1 echo             Show-CommitsSince $r $localDate
>> temp.ps1 echo         }
>> temp.ps1 echo     } else {
>> temp.ps1 echo         $dir = [IO.Path]::GetDirectoryName($t)
>> temp.ps1 echo         if ($dir -ne '' -and !(Test-Path $dir)) { md $dir }
>> temp.ps1 echo         cp $f $t
>> temp.ps1 echo         Write-Host 'NEW: ' $r -ForegroundColor Green
>> temp.ps1 echo         Write-Host '    Last commit: ' (Get-LastCommitInfo $r) -ForegroundColor Cyan
>> temp.ps1 echo     }
>> temp.ps1 echo }
powershell -ExecutionPolicy Bypass -File temp.ps1
del temp.ps1
> temp.ps1 echo $newDir = 'New-Hel-K-main'
>> temp.ps1 echo (gci $newDir -File -Recurse ^| ForEach-Object {
>> temp.ps1 echo     $_.FullName.Substring((gi $newDir).FullName.Length+1)
>> temp.ps1 echo }) ^| Out-File -Encoding utf8 'helk_manifest.txt'
powershell -ExecutionPolicy Bypass -File temp.ps1
del temp.ps1
for /l %%i in (1,1,3) do (
    if exist New-Hel-K-main (
        timeout /t 1 /nobreak >nul
        rmdir /s /q New-Hel-K-main 2>nul
    )
)
if exist New-Hel-K-main (
    echo Warning: Could not delete New-Hel-K-main folder. Please remove manually.
)
echo Done!
pause
exit /b