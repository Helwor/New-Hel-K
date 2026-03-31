@echo off
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
> temp.ps1 echo $d = (gi 'New-Hel-K-main').FullName
>> temp.ps1 echo gci 'New-Hel-K-main' -File -Recurse ^| ForEach-Object {
>> temp.ps1 echo     $f = $_.FullName
>> temp.ps1 echo     $r = $f.Substring($d.Length+1)
>> temp.ps1 echo     $t = $r
>> temp.ps1 echo     if (Test-Path $t) {
>> temp.ps1 echo         $c1 = [System.IO.File]::ReadAllText($f) -replace "`r`n?", "`n"
>> temp.ps1 echo         $c2 = [System.IO.File]::ReadAllText($t) -replace "`r`n?", "`n"
>> temp.ps1 echo         if ($c1 -ne $c2) {
>> temp.ps1 echo             $n = 1
>> temp.ps1 echo             while (Test-Path ($t + '.backup' + $n)) { $n++ }
>> temp.ps1 echo             $backup = $t + '.backup' + $n
>> temp.ps1 echo             mv $t $backup
>> temp.ps1 echo             cp $f $t
>> temp.ps1 echo             Write-Host 'UPDATED: ' $r ' (created backup' $n ')' -ForegroundColor Yellow
>> temp.ps1 echo         }
>> temp.ps1 echo     } else {
>> temp.ps1 echo         $dir = [IO.Path]::GetDirectoryName($t)
>> temp.ps1 echo         if ($dir -ne '' -and !(Test-Path $dir)) { md $dir }
>> temp.ps1 echo         cp $f $t
>> temp.ps1 echo         Write-Host 'NEW: ' $r -ForegroundColor Green
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

set retry=0
:delete_loop
timeout /t 1 /nobreak >nul
rmdir /s /q New-Hel-K-main 2>nul
if exist New-Hel-K-main (
    set /a retry+=1
    if %retry% lss 3 goto delete_loop
    echo Warning: Could not delete New-Hel-K-main folder. Please remove manually.
)

echo Done!
pause