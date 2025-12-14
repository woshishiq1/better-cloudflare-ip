chcp 65001 > nul
@echo off
cd "%~dp0"
setlocal enabledelayedexpansion
cls
goto notice
:notice
echo If the download of the following files fails, you can manually visit the URL to download and save them to the same directory

echo https://www.baipiao.eu.org/cloudflare/colo Save as colo.txt
echo https://www.baipiao.eu.org/cloudflare/url Save as url.txt
echo https://www.baipiao.eu.org/cloudflare/ips-v4 Save as ips-v4.txt
echo https://www.baipiao.eu.org/cloudflare/ips-v6 Save as ips-v6.txt
goto datacheck

:datacheck
if not exist "colo.txt" echo Download data center information from server colo.txt&curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/colo -o colo.txt&goto datacheck
if not exist "url.txt" echo Download the speed test file address from the server url.txt&curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/url -o url.txt&goto datacheck
if not exist "ips-v4.txt" echo Download IPV4 data from server ips-v4.txt&curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/ips-v4 -o ips-v4.txt&goto datacheck
if not exist "ips-v6.txt" echo Download IPV6 data from server ips-v6.txt&curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/ips-v6 -o ips-v6.txt&goto datacheck
set /a n=0
for /f "tokens=1 delims=/" %%i in (url.txt) do (
if !n! EQU 0 set domain=%%i&set /a n+=1
)
set /a n=0
for /f "delims=" %%i in (url.txt) do (
if !n! EQU 0 set url=%%i&set /a n+=1
)
set file=!url:%domain%/=!
cls
goto main

:main
title CF preferred IP
set /a menu=0
echo 1. IPV4 preferred(TLS)&echo 2. IPV4 preferred&echo 3. IPV6 preferred(TLS)&echo 4. IPV6 preferred&echo 5. Single IP speed measurement(TLS)&echo 6. Single IP speed measurement&echo 7. Empty the cache&echo 8. update data&echo 0. quit&echo.
set /p menu=Please select menu(default%menu%):
if %menu%==0 exit
if %menu%==1 title IPV4 preferred(TLS)&set ips=ipv4&set filename=ips-v4.txt&set tls=1&goto bettercloudflareip
if %menu%==2 title IPV4 preferred&set ips=ipv4&set filename=ips-v4.txt&set tls=0&goto bettercloudflareip
if %menu%==3 title IPV6 preferred(TLS)&set ips=ipv6&set filename=ips-v6.txt&set tls=1&goto bettercloudflareip
if %menu%==4 title IIPV6 preferred&set ips=ipv6&set filename=ips-v6.txt&set tls=0&goto bettercloudflareip
if %menu%==5 title Single IP speed measurement(TLS)&call :singlehttps&goto main
if %menu%==6 title Single IP speed measurement&call :singlehttp&goto main
if %menu%==7 del rtt.txt data.txt CR.txt CRLF.txt cut.txt speed.txt > nul 2>&1&RD /S /Q rtt > nul 2>&1&cls&echo 缓存已经清空&goto main
if %menu%==8 del colo.txt url.txt ips-v4.txt ips-v6.txt > nul 2>&1&cls&goto notice
cls
goto main

:singlehttps
set /a port=443
set /p ip=Please enter the IP that needs to be tested:
set /p port=Please enter the port that needs to be tested(default%port%):
echo is measuring speed !ip! port !port!
for /f "delims=" %%i in ('curl --resolve !domain!:!port!:!ip! "https://!domain!:!port!/!file!" -o nul --connect-timeout 5 --max-time 15 -w %%{speed_download}') do (
set /a speed_download=%%i/1024
cls&echo !ip! average speed !speed_download! kB/s
)
goto :eof

:singlehttp
set /a port=80
set /p ip=Please enter the IP that needs to be tested:
set /p port=Please enter the port that needs to be tested(default%port%):
echo is measuring speed !ip! port !port!
for /f "delims=" %%i in ('echo !ip! ^| find /c /v ":"') do (
set /a ipmode=%%i
)
if !ipmode! EQU 0 (
for /f "delims=" %%i in ('curl -x [!ip!]:!port! "http://!domain!:!port!/!file!" -o nul --connect-timeout 5 --max-time 15 -w %%{speed_download}') do (
set /a speed_download=%%i/1024
cls&echo !ip! average speed !speed_download! kB/s
)
) else (
for /f "delims=" %%i in ('curl -x !ip!:!port! "http://!domain!:!port!/!file!" -o nul --connect-timeout 5 --max-time 15 -w %%{speed_download}') do (
set /a speed_download=%%i/1024
cls&echo !ip! average speed !speed_download! kB/s
)
)
goto :eof

:bettercloudflareip
set /a tasknum=10
set /a bandwidth=1
set /p bandwidth=Please set the desired bandwidth size(default minimum%bandwidth%,unit Mbps):
set /p tasknum=Please set the number of RTT test processes(default%tasknum%,Max 50):
if %bandwidth% EQU 0 (set /a bandwidth=1)
if %tasknum% EQU 0 (set /a tasknum=10&echo The number of processes cannot be 0, it is automatically set to the default value)
if %tasknum% GTR 50 (set /a tasknum=50&echo Exceeded the maximum process limit, automatically set to the maximum)
set /a speed=bandwidth*128
set /a startH=%time:~0,2%
if %time:~3,1% EQU 0 (set /a startM=%time:~4,1%) else (set /a startM=%time:~3,2%)
if %time:~6,1% EQU 0 (set /a startS=%time:~7,1%) else (set /a startS=%time:~6,2%)
call :start
exit

:start
del rtt.txt data.txt CR.txt CRLF.txt cut.txt speed.txt > nul 2>&1
RD /S /Q rtt > nul 2>&1
if not exist "RTT.bat" echo current program is incomplete&echo Please download the Release version again: https://github.com/hoseinnikkhah/better-cloudflare-ip-english/releases&pause > nul&exit
if not exist "CR2CRLF.exe" echo current program is incomplete&echo Please download the Release version again: https://github.com/hoseinnikkhah/better-cloudflare-ip-english/releases&pause > nul&exit
set /a n=0
if !ips! EQU ipv4 (echo is generating !ips!&goto getv4) else (echo is generating !ips!&goto getv6)

:getv4
for /f "delims=" %%i in (%filename%) do (
set !random!_%%i=randomsort
)
for /f "tokens=2,3,4 delims=_.=" %%i in ('set ^| findstr =randomsort ^| sort /m 10240') do (
call :randomcidrv4
if not defined %%i.%%j.%%k.!cidr! set %%i.%%j.%%k.!cidr!=anycastip&set /a n+=1
if !n! EQU 100 goto rtt
)
goto getv4

:getv6
for /f "delims=" %%i in (%filename%) do (
set !random!_%%i=randomsort
)
for /f "tokens=2,3,4 delims=_:=" %%i in ('set ^| findstr =randomsort ^| sort /m 10240') do (
call :randomcidrv6
if not defined %%i:%%j:%%k:!cidr! set %%i:%%j:%%k:!cidr!=anycastip&set /a n+=1
if !n! EQU 100 goto rtt
)
goto getv6

:randomcidrv4
set /a cidr=%random%%%256
goto :eof

:randomcidrv6
set str=0123456789abcdef
set /a r=%random%%%16
set cidr=!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!:!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!:!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!:!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!:!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
set /a r=%random%%%16
set cidr=!cidr!!str:~%r%,1!
goto :eof

:rtt
del rtt.txt > nul 2>&1
mkdir rtt
for /f "tokens=1 delims==" %%i in ('set ^| findstr =randomsort') do (
set %%i=
)
for /f "delims=" %%i in ('set ^| findstr =anycastip ^| find /c /v ""') do (
set /a ipnum=%%i
)
if !tasknum! EQU 0 set /a tasknum=1
if !ipnum! LSS !tasknum! set /a tasknum=ipnum
set /a n=1
for /f "tokens=1 delims==" %%i in ('set ^| findstr =anycastip') do (
echo %%i >> rtt/!n!.txt
if !n! EQU !tasknum! (set /a n=1) else (set /a n=n+1)
)
set /a n=1
for /f "tokens=1 delims==" %%i in ('set ^| findstr =anycastip') do (
set %%i=
)
title RTT testing
goto rtttest

:rtttest
start /b rtt.bat !n! !ips! !tls! !domain! > nul
if !n! EQU !tasknum! (goto rttstatus) else (set /a n=n+1&goto rtttest)

:rttstatus
for /f "delims=" %%i in ('dir rtt /o:-s /b^| findstr txt^| find /c /v ""') do (
set /a status=%%i
if !status! NEQ 0 (echo %time:~0,8% Wait for the end of the RTT test, the number of remaining processes !status!&timeout /T 1 /NOBREAK > nul&goto rttstatus) else (echo %time:~0,8% RTT test completed)
)
for /f "delims=" %%i in ('dir rtt /o:-s /b^| findstr log^| find /c /v ""') do (
set /a status=%%i
if !status! NEQ 0 (
copy rtt\*.log rtt.txt>nul
) else (
echo All current IPs have RTT packet loss
echo Continue with new RTT test
goto start
)
)
echo IP address to be tested
for /f "tokens=1,2 delims= " %%i in ('sort rtt.txt') do (
echo %%j       delay %%i ms
)
title start speed test
set /a a=0
for /f "tokens=1,2 delims= " %%i in ('sort rtt.txt') do (
del CRLF.txt cut.txt speed.txt > nul 2>&1
set avgms=%%i
set anycast=%%j
echo testing !anycast!
if !tls! EQU 1 (
curl --resolve !domain!:443:!anycast! https://!domain!/!file! -o nul --connect-timeout 1 --max-time 10 > CR.txt 2>&1
) else (
if !ips! EQU ipv4 (
curl -x !anycast!:80 http://!domain!/!file! -o nul --connect-timeout 1 --max-time 10 > CR.txt 2>&1
) else (
curl -x [!anycast!]:80 http://!domain!/!file! -o nul --connect-timeout 1 --max-time 10 > CR.txt 2>&1
)
)
findstr "0:" CR.txt >> CRLF.txt
CR2CRLF CRLF.txt > nul
for /f "delims=" %%i in (CRLF.txt) do (
set s=%%i
set s=!s:~73,5!
echo !s%! >> cut.txt
)
if not exist "cut.txt" echo 0 > cut.txt
for /f "delims=" %%i in ('findstr /v "k M" cut.txt') do (
set x=%%i
set x=!x:~0,5!
set /a x=!x%!/1024
echo !x! >> speed.txt
)
for /f "delims=" %%i in ('findstr "k" cut.txt') do (
set x=%%i
set x=!x:~0,4!
set /a x=!x%!
echo !x! >> speed.txt
)
for /f "delims=" %%i in ('findstr "M" cut.txt') do (
set x=%%i
set x=!x:~0,2!
set y=%%i
set y=!y:~3,1!
set /a x=!x%!*1024
set /a y=!y%!*1024/10
set /a z=x+y
echo !z! >> speed.txt
)
set /a max=0
for /f "tokens=1,2" %%i in ('type "speed.txt"') do (
if %%i GEQ !max! set /a max=%%i
)
echo !anycast! peak speed !max! kB/s
if !max! GEQ !speed! goto end
)
goto start

:end
echo !anycast!|clip
set /a realbandwidth=max/128
set /a stopH=%time:~0,2%
if %time:~3,1% EQU 0 (set /a stopM=%time:~4,1%) else (set /a stopM=%time:~3,2%)
if %time:~6,1% EQU 0 (set /a stopS=%time:~7,1%) else (set /a stopS=%time:~6,2%)
set /a starttime=%startH%*3600+%startM%*60+%startS%
set /a stoptime=%stopH%*3600+%stopM%*60+%stopS%
if %starttime% GTR %stoptime% (set /a alltime=86400-%starttime%+%stoptime%) else (set /a alltime=%stoptime%-%starttime%)
echo Get details from server
if !tls! EQU 1 (
curl --resolve !domain!:443:!anycast! --retry 1 -s https://!domain!/cdn-cgi/trace -o data.txt --connect-timeout 2 --max-time 3
) else (
if !ips! EQU ipv4 (
curl -x !anycast!:80 --retry 1 -s http://!domain!/cdn-cgi/trace -o data.txt --connect-timeout 2 --max-time 3
) else (
curl -x [!anycast!]:80 --retry 1 -s http://!domain!/cdn-cgi/trace -o data.txt --connect-timeout 2 --max-time 3
)
)
cls
if not exist "data.txt" (
set publicip=get timeout
set colo=get timeout
) else (
for /f "tokens=2 delims==" %%i in ('findstr "ip=" data.txt') do (
set publicip=%%i
)
for /f "tokens=2 delims==" %%i in ('findstr "colo=" data.txt') do (
set colo=%%i
)
for /f "tokens=1 delims=-" %%i in ('findstr !colo! colo.txt') do (
set colo=%%i
)
)
del rtt.txt data.txt CR.txt CRLF.txt cut.txt speed.txt > nul 2>&1
RD /S /Q rtt > nul 2>&1
title The preferred IP has been automatically copied to the clipboard
echo Preferred IP !anycast!
echo Public IP !publicip!
if !tls! EQU 1 (echo support port 443 2053 2083 2087 2096 8443) else (echo support port 80 8080 8880 2052 2082 2086 2095)
echo set broadband !bandwidth! Mbps
echo Measured bandwidth !realbandwidth! Mbps
echo peak speed !max! kB/s
echo       delay !avgms! ms
echo data center !colo!
echo total time !alltime! Second

echo Press any key to close the window
pause > nul
goto :eof
