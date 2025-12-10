@echo off
echo Downloading Hel-K...

REM Force TLS 1.2 and deactivate SSL
powershell -Command "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.DownloadFile('https://github.com/Helwor/New-Hel-K/archive/main.zip','luaui.zip'); $shell=New-Object -ComObject Shell.Application; $shell.Namespace((Get-Location).Path).CopyHere($shell.Namespace((Get-Item 'luaui.zip').FullName).Items(),16); Start-Sleep 2; Remove-Item 'luaui.zip'"

REM delete .gitignore
if exist New-Hel-K-main\.gitignore del New-Hel-K-main\.gitignore


echo Checking existing files...
REM Check what to add and what to update
powershell -Command "$d=(gi 'New-Hel-K-main').FullName;gci 'New-Hel-K-main' -File -Recurse|?{$_.Name -ne '%~nx0'}|%%{$f=$_.FullName;$r=$f.Substring($d.Length+1);$t=$r;if(Test-Path $t){$c1=gc $f -Raw;$c2=gc $t -Raw;if($c1 -ne $c2){$n=1;while(Test-Path ($t+'.backup'+$n)){$n++};$backup=$t+'.backup'+$n;mv $t $backup;cp $f $t;Write-Host 'UPDATED: '$r' (created backup'$n')' -ForegroundColor Yellow}}else{$dir=[IO.Path]::GetDirectoryName($t);if($dir -ne '' -and !(Test-Path $dir)){md $dir};cp $f $t;Write-Host 'NEW: '+$r -ForegroundColor Green}}"

rem Check what to remove
powershell -Command "$new=(gi 'New-Hel-K-main').FullName;$cur=(gi '.').FullName;$exist=@{};gci $new -File -Recurse -Filter '*.lua'|%%{$r=$_.FullName.Replace($new+'\','');$exist[$r]=1};gci $cur -File -Recurse -Filter '*.lua'|?{$_.FullName -notlike '*New-Hel-K-main*' -and $_.Name -ne '%~nx0'}|%%{$f=$_.FullName;$r=$f.Replace($cur+'\','');if(!$exist.ContainsKey($r)){ren $f ($f+'.removed');Write-Host 'REMOVED: '$r -ForegroundColor Red}}"

rem Delete the temp dir
rmdir /s /q New-Hel-K-main
echo Done!

pause