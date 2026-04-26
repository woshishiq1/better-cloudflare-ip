#!/bin/bash
# Cloudflare 优选 IP Termux 稳定增强版

function bettercloudflareip(){
    read -p "请输入期望带宽 (单位 Mbps, 建议 50-100): " bandwidth
    read -p "请输入测试线程数 (手机建议 10-20, 最大 30): " tasknum
    bandwidth=${bandwidth:-1}
    tasknum=${tasknum:-10}

    # 手机端强制保护逻辑：防止触发安卓幻影进程杀手
    if [ "$tasknum" -gt 30 ]; then
        echo "检测到环境为手机，已将线程下调至安全阈值 (30)"
        tasknum=30
    fi

    # 计算目标字节速度 (Mbps * 128 * 1024 = Bytes/s)
    speed=$((bandwidth * 128 * 1024))
    starttime=$(date +%s)
    
    # 执行核心测试逻辑
    cloudflaretest

    if [ -z "$anycast" ]; then
        echo "未能在当前批次找到达标节点，请尝试降低带宽要求。"
        return
    fi

    # 结果收尾
    realbandwidth=$(( ${max:-0} / 128 / 1024 ))
    endtime=$(date +%s)

    echo "正在获取节点详细信息..."
    temp=($(curl --resolve $domain:443:$anycast -s https://$domain/cdn-cgi/trace --connect-timeout 2 --max-time 3))
    publicip=$(echo ${temp[@]} | tr ' ' '\n' | grep ip= | cut -f 2- -d'=')
    colo=$(echo ${temp[@]} | tr ' ' '\n' | grep colo= | cut -f 2- -d'=')

    clear
    echo "=========================================="
    echo "        Cloudflare 优选测试完成"
    echo "=========================================="
    echo "优选 IP    : $anycast"
    echo "公网 IP    : ${publicip:-获取超时}"
    echo "数据中心   : ${colo:-未知}"
    echo "往返延迟   : ${avgms:-0} ms"
    echo "峰值速度   : $(( ${max:-0} / 1024 )) kB/s"
    echo "实测带宽   : $realbandwidth Mbps"
    echo "总计用时   : $((endtime - starttime)) 秒"
    echo "=========================================="
}

# RTT 测试子函数：负责处理分配给它的 IP 列表
function run_rtt_batch(){
    local file_id=$1
    local mode=$2 # tls 1 or 0
    while read -r ip; do
        if [ "$mode" == "1" ]; then
            rsp=$(curl --resolve $domain:443:$ip https://$domain/cdn-cgi/trace -o /dev/null -s --connect-timeout 2 --max-time 3 -w %{time_connect}_%{http_code})
        else
            if [[ "$ip" == *:* ]]; then # IPv6
                rsp=$(curl -x [$ip]:80 http://$domain/cdn-cgi/trace -o /dev/null -s --connect-timeout 2 --max-time 3 -w %{time_connect}_%{http_code})
            else
                rsp=$(curl -x $ip:80 http://$domain/cdn-cgi/trace -o /dev/null -s --connect-timeout 2 --max-time 3 -w %{time_connect}_%{http_code})
            fi
        fi

        if [ "$(echo $rsp | awk -F_ '{print $2}')" == "200" ]; then
            local ms=$(echo $rsp | awk -F_ '{printf ("%.0f\n",$1*1000)}')
            printf "%03d %s\n" $ms $ip >> rtt/all_results.log
        fi
    done < "rtt/list_$file_id.txt"
}

# 测速子函数：提取峰值速度
function get_speed(){
    local ip=$1
    local mode=$2 # tls 1 or 0
    rm -f log.txt
    
    if [ "$mode" == "1" ]; then
        curl --resolve $domain:443:$ip https://$domain/$file -o /dev/null --connect-timeout 3 --max-time 10 > log.txt 2>&1
    else
        if [[ "$ip" == *:* ]]; then
            curl -x [$ip]:80 http://$domain/$file -o /dev/null --connect-timeout 3 --max-time 10 > log.txt 2>&1
        else
            curl -x $ip:80 http://$domain/$file -o /dev/null --connect-timeout 3 --max-time 10 > log.txt 2>&1
        fi
    fi

    # 处理 curl 进度条中的速度值 (支持 M, k, B 单位和浮点数)
    local result=$(cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | \
    awk '{
        if($1 ~ /M/) {gsub(/M/,"",$1); printf "%.0f\n", $1*1048576}
        else if($1 ~ /k/) {gsub(/k/,"",$1); printf "%.0f\n", $1*1024}
        else {printf "%.0f\n", $1}
    }' | sort -rn | head -n 1)
    
    echo "${result:-0}"
}

function cloudflaretest(){
    while true; do
        rm -rf rtt && mkdir rtt
        echo "$(date +'%H:%M:%S') 正在随机生成测试 IP..."
        
        # IP 生成逻辑
        local n=0
        declare -a test_ips
        while [ $n -lt 100 ]; do
            for line in $(awk 'BEGIN{srand()} {print rand()"\t"$0}' $filename | sort -n | head -n 50 | awk '{print $2}'); do
                if [ "$ips" == "ipv4" ]; then
                    test_ips[$n]="${line%.*}.$(($RANDOM%256))"
                else
                    test_ips[$n]="$line$(printf '%x:%x:%x:%x:%x' $((RANDOM)) $((RANDOM)) $((RANDOM)) $((RANDOM)) $((RANDOM)))"
                fi
                n=$((n+1))
                [ $n -ge 100 ] && break
            done
        done

        # 任务分发
        local idx=1
        for p in ${test_ips[@]}; do
            echo "$p" >> "rtt/list_$idx.txt"
            [ $idx -ge $tasknum ] && idx=1 || idx=$((idx+1))
        done

        echo "$(date +'%H:%M:%S') 正在进行延迟测试 (线程: $tasknum)..."
        for i in $(seq 1 $tasknum); do
            [ -f "rtt/list_$i.txt" ] && run_rtt_batch "$i" "$tls" &
        done
        wait

        if [ ! -f rtt/all_results.log ]; then
            echo "当前批次 IP 全部丢包，正在重试..."
            continue
        fi

        # 按延迟排序并逐个测速
        sort -n rtt/all_results.log > rtt_final.txt
        echo "已找到有效 IP，开始进行带宽测试..."
        
        while read -r line; do
            avgms=$(echo $line | awk '{print $1}')
            anycast=$(echo $line | awk '{print $2}')
            echo -n "测试中: $anycast | 延迟: ${avgms}ms | "
            
            max=$(get_speed "$anycast" "$tls")
            
            if [ "${max:-0}" -ge "$speed" ]; then
                echo "达标! ($((max/1024)) kB/s)"
                break 2
            else
                echo "速度: $((max/1024)) kB/s (未达标)"
            fi
        done < rtt_final.txt
    done
}

function datacheck(){
    echo "检查必要资源文件..."
    local base_url="https://www.baipiao.eu.org/cloudflare"
    for f in colo.txt url.txt ips-v4.txt ips-v6.txt; do
        if [ ! -f "$f" ]; then
            echo "正在下载 $f..."
            curl -s -L "$base_url/${f/-v/v}" -o "$f"
        fi
    done
}

# --- 程序入口 ---
datacheck
url=$(sed -n '1p' url.txt)
domain=$(echo $url | cut -f 1 -d'/')
file=$(echo $url | cut -f 2- -d'/')

while true; do
    clear
    echo "1. IPv4 优选 (TLS/443)"
    echo "2. IPv4 优选 (HTTP/80)"
    echo "3. IPv6 优选 (TLS/443)"
    echo "4. IPv6 优选 (HTTP/80)"
    echo "7. 清空缓存"
    echo "8. 更新数据"
    echo "0. 退出"
    echo ""
    read -p "请选择菜单: " menu
    case ${menu:-0} in
        1) ips=ipv4; filename=ips-v4.txt; tls=1; bettercloudflareip; break ;;
        2) ips=ipv4; filename=ips-v4.txt; tls=0; bettercloudflareip; break ;;
        3) ips=ipv6; filename=ips-v6.txt; tls=1; bettercloudflareip; break ;;
        4) ips=ipv6; filename=ips-v6.txt; tls=0; bettercloudflareip; break ;;
        7) rm -rf rtt log.txt speed.txt rtt_final.txt; echo "已清理"; sleep 1 ;;
        8) rm -f colo.txt url.txt ips-v4.txt ips-v6.txt; datacheck ;;
        0) exit 0 ;;
        *) echo "输入错误" ;;
    esac
done
