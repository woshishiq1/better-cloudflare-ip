#!/bin/bash
# better-cloudflare-ip (Full Fixed Version for Mobile/Termux)

function bettercloudflareip(){
read -p "请设置期望的带宽大小(默认最小1,单位 Mbps):" bandwidth
read -p "请设置RTT测试进程数(默认10,最大50):" tasknum
if [ -z "$bandwidth" ]; then bandwidth=1; fi
if [ "$bandwidth" -eq 0 ]; then bandwidth=1; fi
if [ -z "$tasknum" ]; then tasknum=10; fi
if [ "$tasknum" -eq 0 ]; then echo "进程数不能为0,自动设置为默认值"; tasknum=10; fi
if [ "$tasknum" -gt 50 ]; then echo "超过最大进程限制,自动设置为最大值"; tasknum=50; fi

# 带宽换算为字节
speed=$((bandwidth * 128 * 1024))
starttime=$(date +%s)
cloudflaretest

# 实测带宽换算，增加空值保护
realbandwidth=$(( ${max:-0} / 128 / 1024 ))
endtime=$(date +%s)

echo "从服务器获取详细信息"
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
	publicip=获取超时
	colo=获取超时
else
	publicip=$(echo ${temp[@]} | sed -e 's/ /\n/g' | grep ip= | cut -f 2- -d'=')
	colo=$(grep -w "($(echo ${temp[@]} | sed -e 's/ /\n/g' | grep colo= | cut -f 2- -d'='))" colo.txt | awk -F"-" '{print $1}')
fi

clear
echo "优选IP $anycast"
echo "公网IP $publicip"
if [ $tls == 1 ]
then
	echo "支持端口 443 2053 2083 2087 2096 8443"
else
	echo "支持端口 80 8080 8880 2052 2082 2086 2095"
fi
echo "设置带宽 $bandwidth Mbps"
echo "实测带宽 $realbandwidth Mbps"
echo "峰值速度 $(( ${max:-0} / 1024 )) kB/s"
echo "往返延迟 $avgms 毫秒"
echo "数据中心 $colo"
echo "总计用时 $((endtime - starttime)) 秒"
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
curl --resolve $domain:443:$1 https://$domain/$file -o /dev/null --connect-timeout 2 --max-time 10 > log.txt 2>&1
# 统一的数值清洗与字节换算逻辑
cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' > raw_speed.txt
while read -r line; do
    if [[ $line == *M* ]]; then
        echo "$line" | sed 's/M//g' | awk '{printf "%.0f\n", $1 * 1048576}' >> speed.txt
    elif [[ $line == *k* ]]; then
        echo "$line" | sed 's/k//g' | awk '{printf "%.0f\n", $1 * 1024}' >> speed.txt
    elif [[ "$line" =~ ^[0-9.]+$ ]]; then
        echo "$line" | awk '{printf "%.0f\n", $1}' >> speed.txt
    fi
done < raw_speed.txt
max=0
for i in $(cat speed.txt 2>/dev/null); do
    i_int=$(echo $i | cut -f1 -d'.')
    if [ "${i_int:-0}" -ge "${max:-0}" ]; then max=$i_int; fi
done
rm -rf log.txt speed.txt raw_speed.txt
echo $max
}

function speedtesthttp(){
rm -rf log.txt speed.txt
if [ $(echo $1 | grep : | wc -l) == 0 ]
then
	curl -x $1:80 http://$domain/$file -o /dev/null --connect-timeout 2 --max-time 10 > log.txt 2>&1
else
	curl -x [$1]:80 http://$domain/$file -o /dev/null --connect-timeout 2 --max-time 10 > log.txt 2>&1
fi
cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' > raw_speed.txt
while read -r line; do
    if [[ $line == *M* ]]; then
        echo "$line" | sed 's/M//g' | awk '{printf "%.0f\n", $1 * 1048576}' >> speed.txt
    elif [[ $line == *k* ]]; then
        echo "$line" | sed 's/k//g' | awk '{printf "%.0f\n", $1 * 1024}' >> speed.txt
    elif [[ "$line" =~ ^[0-9.]+$ ]]; then
        echo "$line" | awk '{printf "%.0f\n", $1}' >> speed.txt
    fi
done < raw_speed.txt
max=0
for i in $(cat speed.txt 2>/dev/null); do
    i_int=$(echo $i | cut -f1 -d'.')
    if [ "${i_int:-0}" -ge "${max:-0}" ]; then max=$i_int; fi
done
rm -rf log.txt speed.txt raw_speed.txt
echo $max
}

function cloudflaretest(){
while true
do
	while true
	do
		rm -rf rtt rtt.txt log.txt speed.txt
		mkdir rtt
		echo "正在生成 $ips"
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
			if [ $n -ne 0 ]; then echo "$(date +'%H:%M:%S') 等待RTT测试结束,剩余进程数 $n"
			else echo "$(date +'%H:%M:%S') RTT测试完成"; break; fi
			sleep 1
		done
		n=$(ls rtt 2>/dev/null | grep log | wc -l)
		if [ $n == 0 ]
		then
			echo "当前所有IP都存在RTT丢包, 继续新的RTT测试"
		else
			cat rtt/*.log > rtt.txt
			status=0
			echo "待测速的IP地址"
			cat rtt.txt | sort | awk '{print $2" 往返延迟 "$1" 毫秒"}'
			for i in `cat rtt.txt | sort | awk '{print $1"_"$2}'`
			do
				avgms=$(echo $i | awk -F_ '{print $1}')
				ip=$(echo $i | awk -F_ '{print $2}')
				echo "正在测试 $ip"
				if [ $tls == 1 ]; then max=$(speedtesthttps $ip); else max=$(speedtesthttp $ip); fi
				
				if [ "${max:-0}" -ge "${speed:-0}" ]
				then
					status=1
					anycast=$ip
					echo "$ip 峰值速度 $(( ${max:-0} / 1024 )) kB/s"
					rm -rf rtt rtt.txt
					break
				else
					echo "$ip 峰值速度 $(( ${max:-0} / 1024 )) kB/s"
				fi
			done
			if [ $status == 1 ]; then break; fi
		fi
	done
	break
done
}

# 恢复并加固的单IP测速逻辑
function singlehttps(){
read -p "请输入需要测速的IP: " ip
read -p "请输入需要测速的端口(默认443): " port
if [ -z "$ip" ]; then
	echo "未输入IP"
	return
fi
port=${port:-443}
echo "正在测速 $ip 端口 $port"
# 使用 -s 静默执行并提取字节速度，使用awk防错计算kb/s
speed_raw=$(curl --resolve $domain:$port:$ip https://$domain:$port/$file -o /dev/null -s --connect-timeout 5 --max-time 15 -w "%{speed_download}")
speed_download=$(echo "${speed_raw:-0}" | awk '{printf "%.0f\n", $1/1024}')
}

function singlehttp(){
read -p "请输入需要测速的IP: " ip
read -p "请输入需要测速的端口(默认80): " port
if [ -z "$ip" ]; then
	echo "未输入IP"
	return
fi
port=${port:-80}
echo "正在测速 $ip 端口 $port"
if [ $(echo $ip | grep : | wc -l) == 0 ]; then
	speed_raw=$(curl -x $ip:$port http://$domain:$port/$file -o /dev/null -s --connect-timeout 5 --max-time 15 -w "%{speed_download}")
else
	speed_raw=$(curl -x [$ip]:$port http://$domain:$port/$file -o /dev/null -s --connect-timeout 5 --max-time 15 -w "%{speed_download}")
fi
speed_download=$(echo "${speed_raw:-0}" | awk '{printf "%.0f\n", $1/1024}')
}

function datacheck(){
clear
echo "检查必要组件..."
for pkg in curl awk sed bc; do
    if ! command -v $pkg &> /dev/null; then echo "提示: 缺少组件 $pkg, 建议通过包管理器安装以获得最佳体验"; fi
done
echo "如果下面这些文件下载失败,可以手动访问网址保存至同级目录"
while true
do
	if [ ! -f "colo.txt" ]; then 
        echo "下载 colo.txt..."
        curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/colo -o colo.txt
	elif [ ! -f "url.txt" ]; then 
        echo "下载 url.txt..."
        curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/url -o url.txt
	elif [ ! -f "ips-v4.txt" ]; then 
        echo "下载 ips-v4.txt..."
        curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/ips-v4 -o ips-v4.txt
	elif [ ! -f "ips-v6.txt" ]; then 
        echo "下载 ips-v6.txt..."
        curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/ips-v6 -o ips-v6.txt
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
	echo "1. IPV4优选(TLS)"
	echo "2. IPV4优选"
	echo "3. IPV6优选(TLS)"
	echo "4. IPV6优选"
	echo "5. 单IP测速(TLS)"
	echo "6. 单IP测速"
	echo "7. 清空缓存"
	echo "8. 更新数据"
	echo -e "0. 退出\n"
	read -p "请选择菜单(默认0): " menu
	menu=${menu:-0}
	
	if [ "$menu" == "0" ]; then
		clear
		echo "退出成功"
		break
	elif [ "$menu" == "1" ]; then
		ips=ipv4; filename=ips-v4.txt; tls=1; bettercloudflareip; break
	elif [ "$menu" == "2" ]; then
		ips=ipv4; filename=ips-v4.txt; tls=0; bettercloudflareip; break
	elif [ "$menu" == "3" ]; then
		ips=ipv6; filename=ips-v6.txt; tls=1; bettercloudflareip; break
	elif [ "$menu" == "4" ]; then
		ips=ipv6; filename=ips-v6.txt; tls=0; bettercloudflareip; break
	elif [ "$menu" == "5" ]; then
		singlehttps
		clear
		echo "$ip 平均速度 ${speed_download:-0} kB/s"
	elif [ "$menu" == "6" ]; then
		singlehttp
		clear
		echo "$ip 平均速度 ${speed_download:-0} kB/s"
	elif [ "$menu" == "7" ]; then
		rm -rf rtt rtt.txt log.txt speed.txt
		clear
		echo "缓存已经清空"
	elif [ "$menu" == "8" ]; then
		rm -rf colo.txt url.txt ips-v4.txt ips-v6.txt
		datacheck
		clear
		echo "数据中心信息与测试地址已更新"
	else
		echo "无效选择，请重新输入"
	fi
done
