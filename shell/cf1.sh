#!/bin/bash
# better-cloudflare-ip (Fixed English Version)

function bettercloudflareip(){
read -p "Please set the expected bandwidth size (default minimum is 1 Mbps, unit Mbps):" bandwidth
read -p "Please set the number of RTT test processes (default is 10, maximum 50):" tasknum
if [ -z "$bandwidth" ]; then bandwidth=1; fi
if [ "$bandwidth" -eq 0 ]; then bandwidth=1; fi
if [ -z "$tasknum" ]; then tasknum=10; fi
if [ "$tasknum" -eq 0 ]; then
	echo "The number of processes cannot be 0, it is automatically set to the default value"
	tasknum=10
fi
if [ "$tasknum" -gt 50 ]; then
	echo "Exceeded the maximum process limit, automatically set to the maximum"
	tasknum=50
fi

speed=$((bandwidth * 128 * 1024))
starttime=$(date +%s)
cloudflaretest
realbandwidth=$(( ${max:-0} / 128 ))
endtime=$(date +%s)

echo "Get details from server"
unset temp
if [ "$ips" == "ipv4" ]
then
	if [ $tls == 1 ]
	then
		temp=($(curl --resolve $domain:443:$anycast --retry 1 -s https://$domain/cdn-cgi/trace --connect-timeout 2 --max-time 3))
	else
		temp=($(curl -x $anycast:80 --retry 1 -s http://$domain/cdn-cgi/trace --connect-timeout 2 --max-time 3))
	fi
else
	if [ $tls == 1 ]
	then
		temp=($(curl --resolve $domain:443:$anycast --retry 1 -s https://$domain/cdn-cgi/trace --connect-timeout 2 --max-time 3))
	else
		temp=($(curl -x [$anycast]:80 --retry 1 -s http://$domain/cdn-cgi/trace --connect-timeout 2 --max-time 3))
	fi
fi

if [ $(echo ${temp[@]} | sed -e 's/ /\n/g' | grep colo= | wc -l) == 0 ]
then
	publicip="get timeout"
	colo="get timeout"
else
	publicip=$(echo ${temp[@]} | sed -e 's/ /\n/g' | grep ip= | cut -f 2- -d'=')
	colo=$(grep -w "($(echo ${temp[@]} | sed -e 's/ /\n/g' | grep colo= | cut -f 2- -d'='))" colo.txt | awk -F"-" '{print $1}')
fi
clear
echo "preferred IP $anycast"
echo "public net IP $publicip"
if [ $tls == 1 ]
then
	echo "supported ports 443 2053 2083 2087 2096 8443"
else
	echo "supported ports 80 8080 8880 2052 2082 2086 2095"
fi
echo "set bandwidth $bandwidth Mbps"
echo "measured bandwidth $realbandwidth Mbps"
echo "peak speed $(( ${max:-0} )) kB/s"
echo "IP delay:$avgms ms"
echo "data center $colo"
echo "total time $((endtime - starttime)) Second"
}

function rtthttps(){
avgms=0
n=1
for ip in `cat rtt/$1.txt`
do
	while true
	do
		if [ $n -le 3 ]
		then
			rsp=$(curl --resolve $domain:443:$ip https://$domain/cdn-cgi/trace -o /dev/null -s --connect-timeout 1 --max-time 3 -w %{time_connect}_%{http_code})
			if [ "$(echo $rsp | awk -F_ '{print $2}')" != "200" ]
			then
				avgms=0
				n=1
				break
			else
				avgms=$(( $(echo $rsp | awk -F_ '{printf ("%d\n",$1*1000)}') + avgms ))
				n=$((n+1))
			fi
		else
			avgms=$((avgms/3))
			if [ $avgms -lt 10 ]; then echo 00$avgms $ip >> rtt/$1.log
			elif [ $avgms -ge 10 ] && [ $avgms -lt 100 ]; then echo 0$avgms $ip >> rtt/$1.log
			else echo $avgms $ip >> rtt/$1.log; fi
			avgms=0
			n=1
			break
		fi
	done
done
rm -rf rtt/$1.txt
}

function rtthttp(){
avgms=0
n=1
for ip in `cat rtt/$1.txt`
do
	while true
	do
		if [ $n -le 3 ]
		then
			if [ $(echo $ip | grep : | wc -l) == 0 ]
			then
				rsp=$(curl -x $ip:80 http://$domain/cdn-cgi/trace -o /dev/null -s --connect-timeout 1 --max-time 3 -w %{time_connect}_%{http_code})
			else
				rsp=$(curl -x [$ip]:80 http://$domain/cdn-cgi/trace -o /dev/null -s --connect-timeout 1 --max-time 3 -w %{time_connect}_%{http_code})
			fi
			if [ "$(echo $rsp | awk -F_ '{print $2}')" != "200" ]
			then
				avgms=0
				n=1
				break
			else
				avgms=$(( $(echo $rsp | awk -F_ '{printf ("%d\n",$1*1000)}') + avgms ))
				n=$((n+1))
			fi
		else
			avgms=$((avgms/3))
			if [ $avgms -lt 10 ]; then echo 00$avgms $ip >> rtt/$1.log
			elif [ $avgms -ge 10 ] && [ $avgms -lt 100 ]; then echo 0$avgms $ip >> rtt/$1.log
			else echo $avgms $ip >> rtt/$1.log; fi
			avgms=0
			n=1
			break
		fi
	done
done
rm -rf rtt/$1.txt
}

function speedtesthttps(){
rm -rf log.txt speed.txt
curl --resolve $domain:443:$1 https://$domain/$file -o /dev/null --connect-timeout 1 --max-time 10 > log.txt 2>&1
cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep -v 'k\|M' >> speed.txt
for i in `cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep k | sed 's/k//g'`
do
	k=$(echo | awk '{print '$i'*1024 }' | awk -F\. '{print $1}')
	echo $k >> speed.txt
done
for i in `cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep M | sed 's/M//g'`
do
	M=$(echo | awk '{print '$i'*1048576 }' | awk -F\. '{print $1}')
	echo $M >> speed.txt
done
max=0
for i in $(cat speed.txt 2>/dev/null)
do
	if [ $i -ge $max ]
	then
		max=$i
	fi
done
rm -rf log.txt speed.txt
echo $max
}

function speedtesthttp(){
rm -rf log.txt speed.txt
if [ $(echo $1 | grep : | wc -l) == 0 ]
then
	curl -x $1:80 http://$domain/$file -o /dev/null --connect-timeout 1 --max-time 10 > log.txt 2>&1
else
	curl -x [$1]:80 http://$domain/$file -o /dev/null --connect-timeout 1 --max-time 10 > log.txt 2>&1
fi
cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep -v 'k\|M' >> speed.txt
for i in `cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep k | sed 's/k//g'`
do
	k=$(echo | awk '{print '$i'*1024 }' | awk -F\. '{print $1}')
	echo $k >> speed.txt
done
for i in `cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep M | sed 's/M//g'`
do
	M=$(echo | awk '{print '$i'*1048576 }' | awk -F\. '{print $1}')
	echo $M >> speed.txt
done
max=0
for i in $(cat speed.txt 2>/dev/null)
do
	if [ $i -ge $max ]
	then
		max=$i
	fi
done
rm -rf log.txt speed.txt
echo $max
}

function cloudflaretest(){
while true
do
	while true
	do
		rm -rf rtt rtt.txt log.txt speed.txt
		mkdir rtt
		echo "is generating $ips"
		unset temp
		if [ "$ips" == "ipv4" ]
		then
			n=0
			iplist=100
			while true
			do
				for i in `awk 'BEGIN{srand()} {print rand()"\t"$0}' $filename | sort -n | awk '{print $2} NR=='$iplist' {exit}' | awk -F\. '{print $1"."$2"."$3}'`
				do
					temp[$n]=$(echo $i.$(($RANDOM%256)))
					n=$((n+1))
				done
				if [ $n -ge $iplist ]; then break; fi
			done
		else
			n=0
			iplist=100
			while true
			do
				for i in `awk 'BEGIN{srand()} {print rand()"\t"$0}' $filename | sort -n | awk '{print $2} NR=='$iplist' {exit}' | awk -F: '{print $1":"$2":"$3}'`
				do
					temp[$n]=$(echo $i:$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))):$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))):$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))):$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))):$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))))
					n=$((n+1))
				done
				if [ $n -ge $iplist ]; then break; fi
			done
		fi
		ipnum=$(echo ${temp[@]} | sed -e 's/ /\n/g' | sort -u | wc -l)
		[ "${tasknum:-0}" == 0 ] && tasknum=1
		if [ $ipnum -lt $tasknum ]; then tasknum=$ipnum; fi
		n=1
		for i in `echo ${temp[@]} | sed -e 's/ /\n/g' | sort -u`
		do
			echo $i>>rtt/$n.txt
			if [ $n == $tasknum ]; then n=1; else n=$((n+1)); fi
		done
		n=1
		while true
		do
			if [ $tls == 1 ]; then rtthttps $n & else rtthttp $n & fi
			if [ $n == $tasknum ]; then break; else n=$((n+1)); fi
		done
		while true
		do
			n=$(ls rtt 2>/dev/null | grep txt | wc -l)
			if [ $n -ne 0 ]; then echo "$(date +'%H:%M:%S') Wait for the end of the RTT test, the number of remaining processes $n"
			else echo "$(date +'%H:%M:%S') RTT test completed"; break; fi
			sleep 1
		done
		n=$(ls rtt 2>/dev/null | grep log | wc -l)
		if [ $n == 0 ]
		then
			echo "All current IPs have RTT packet loss"
			echo "Continue with new RTT test"
		else
			cat rtt/*.log > rtt.txt
			status=0
			echo "IP address to be tested"
			cat rtt.txt | sort | awk '{print $2" IP delay: "$1" ms"}'
			for i in `cat rtt.txt | sort | awk '{print $1"_"$2}'`
			do
				avgms=$(echo $i | awk -F_ '{print $1}')
				ip=$(echo $i | awk -F_ '{print $2}')
				echo "testing $ip"
				if [ $tls == 1 ]; then max=$(speedtesthttps $ip); else max=$(speedtesthttp $ip); fi
				
				if [ "${max:-0}" -ge "${speed:-0}" ]
				then
					status=1
					anycast=$ip
					max=$(( ${max:-0} / 1024 ))
					echo "$ip peak speed $max kB/s"
					rm -rf rtt rtt.txt
					break
				else
					max_display=$(( ${max:-0} / 1024 ))
					echo "$ip peak speed $max_display kB/s"
				fi
			done
			if [ $status == 1 ]; then break; fi
		fi
	done
	break
done
}

function singlehttps(){
read -p "Please enter the IP that needs to be tested: " ip
read -p "Please enter the port that needs to be tested (default 443): " port
if [ -z "$ip" ]; then echo "No IP entered"; return; fi
port=${port:-443}
echo "Speed testing $ip port $port"
speed_raw=$(curl --resolve $domain:$port:$ip https://$domain:$port/$file -o /dev/null -s --connect-timeout 5 --max-time 15 -w "%{speed_download}")
speed_download=$(echo "${speed_raw:-0}" | awk '{printf "%.0f\n", $1/1024}')
}

function singlehttp(){
read -p "Please enter the IP that needs to be tested: " ip
read -p "Please enter the port that needs to be tested (default 80): " port
if [ -z "$ip" ]; then echo "No IP entered"; return; fi
port=${port:-80}
echo "Speed testing $ip port $port"
if [ $(echo $ip | grep : | wc -l) == 0 ]; then
	speed_raw=$(curl -x $ip:$port http://$domain:$port/$file -o /dev/null -s --connect-timeout 5 --max-time 15 -w "%{speed_download}")
else
	speed_raw=$(curl -x [$ip]:$port http://$domain:$port/$file -o /dev/null -s --connect-timeout 5 --max-time 15 -w "%{speed_download}")
fi
speed_download=$(echo "${speed_raw:-0}" | awk '{printf "%.0f\n", $1/1024}')
}

function datacheck(){
clear
echo "If the download of the following files fails, you can manually visit the URL to download and save them to the same directory"
echo "https://www.baipiao.eu.org/cloudflare/colo Save as colo.txt"
echo "https://www.baipiao.eu.org/cloudflare/url Save as url.txt"
echo "https://www.baipiao.eu.org/cloudflare/ips-v4 Save as ips-v4.txt"
echo "https://www.baipiao.eu.org/cloudflare/ips-v6 Save as ips-v6.txt"
while true
do
	if [ ! -f "colo.txt" ]; then curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/colo -o colo.txt
	elif [ ! -f "url.txt" ]; then curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/url -o url.txt
	elif [ ! -f "ips-v4.txt" ]; then curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/ips-v4 -o ips-v4.txt
	elif [ ! -f "ips-v6.txt" ]; then curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/ips-v6 -o ips-v6.txt
	else break; fi
done
}

datacheck
url=$(sed -n '1p' url.txt)
domain=$(echo $url | cut -f 1 -d'/')
file=$(echo $url | cut -f 2- -d'/')
clear
while true
do
	echo "1. IPV4 preferred(TLS)"
	echo "2. IPV4 preferred"
	echo "3. IPV6 preferred(TLS)"
	echo "4. IPV6 preferred"
	echo "5. Single IP speed measurement(TLS)"
	echo "6. Single IP speed measurement"
	echo "7. Empty the cache"
	echo "8. update data"
	echo -e "0. quit\n"
	read -p "Please select the menu (default 0): " menu
	menu=${menu:-0}
	case $menu in
		0) clear; echo "exit successfully"; break ;;
		1) ips=ipv4; filename=ips-v4.txt; tls=1; bettercloudflareip; break ;;
		2) ips=ipv4; filename=ips-v4.txt; tls=0; bettercloudflareip; break ;;
		3) ips=ipv6; filename=ips-v6.txt; tls=1; bettercloudflareip; break ;;
		4) ips=ipv6; filename=ips-v6.txt; tls=0; bettercloudflareip; break ;;
		5) singlehttps; clear; echo "$ip average speed ${speed_download:-0} kB/s" ;;
		6) singlehttp; clear; echo "$ip average speed ${speed_download:-0} kB/s" ;;
		7) rm -rf rtt rtt.txt log.txt speed.txt; clear; echo "cache has been cleared" ;;
		8) rm -rf colo.txt url.txt ips-v4.txt ips-v6.txt; datacheck; clear ;;
		*) echo "Invalid choice" ;;
	esac
done
