#!/bin/bash
echo "@all@"
#获取服务器系统类型
function get_os_type
{
    os_type=''
    systemnum=''
    arch=''
    if [ -f /etc/redhat-release ];then
	cat /etc/redhat-release |grep -i centos &>/dev/null
	if [ $? -eq 0 ];then
            os_type='CentOS'
        fi
	cat /etc/redhat-release |grep -i red |grep -i hat &>/dev/null
	if [ $? -eq 0 ];then
            os_type='RHEL'
        fi
	systemnum=$(cat /etc/redhat-release |grep -o '[0-9]' |head -n 1)
	arch=$(cat /etc/redhat-release  |sed "s/.*release \([0-9].[0-9]\).*/\1/g" |awk '{print $1}' |awk -F. '{print $1"."$2}')
    elif [ ! -f /etc/redhat-release -a -f /etc/issue ];then
	cat /etc/issue |grep -i SUSE &>/dev/null
	if [ $? -eq 0 ];then
            os_type='SUSE'
	    systemnum=$(cat /etc/issue |grep -v ^$ |awk -F'Server' '{print $2}' |awk '{print $1}')
	    arch=$(cat /etc/issue |grep -v ^$ |awk -F'Server' '{print $2}' |awk '{print $1"_"$2}')
        fi
	cat /etc/issue |grep -i ubuntu &>/dev/null
	if [ $? -eq 0 ];then
            os_type='UBUNTU'
	    arch=$(cat /etc/issue |grep -v ^$ |awk '{print $2}')
	    systemnum=$(cat /etc/issue |grep -v ^$ |awk '{print $2}' |awk '{print $1}')
        fi
    fi
}

get_os_type;

#获取系统运行时间
uptime=`uptime |awk -F ',' '{print $1}' |awk '{print $3,$4}'`
echo l_runtime="${uptime}"

#获取系统安装时间
install_time=$(stat $(fdisk -l |grep Disk |head -n 1 |awk '{print $2}' |sed 's/://') |grep Change |awk '{print $2,$3}')
echo l_installtime="${install_time}"

#时区设置
if [ "${os_type}" == "UBUNTU" ];then
    timezone=$(timedatectl |grep -i timezone |awk '{print $2}')
    echo l_timezone="${timezone}"
else
    case ${systemnum} in
    7)
#        timezone=$(ls -l /etc/localtime |awk -F'/' '{print $(NF-1),$NF}' |tr ' ' '/')
        timezone=$(timedatectl |grep "Time zone" |awk -F': ' '{print $2}')
        echo l_timezone="${timezone}"
    ;;
    *)
#        timezone=$(cat /etc/sysconfig/clock |grep  ZONE |awk -F'"' '{print $2}' |grep -v ^$)
        timezone=$(timedatectl |grep "Time zone" |awk -F': ' '{print $2}')
        echo l_timezone="${timezone}"
    ;;
    esac
fi

#NTP配置
ntp_servers=""
ntpd_or_chronyd=$(ps -ef |grep -v grep |grep ntpd 2>&1 >/dev/null && echo ntpd || ps -ef |grep -v grep |grep chronyd 2>&1 >/dev/null && echo chronyd)
#if [ -f /etc/ntp.conf ];then
if [ $ntpd_or_chronyd == ntpd ];then
    servers=$(cat /etc/ntp.conf 2>/dev/null |egrep -v '^(\s*)#' |grep -v ^$ |grep 'server' |grep -v "pool.ntp.org" |awk '{print $2}' |tr '\n' ';')
    [ -n "${servers}" ] && ntp_servers+="${servers}"
fi
#if [ -f /etc/chrony.conf -a ! -f /etc/ntp.conf ];then
if [ $ntpd_or_chronyd == chronyd ];then
    servers=$(cat /etc/chrony.conf 2>/dev/null |egrep -v '^(\s*)#' |grep -v ^$ | grep 'server' |grep -v "pool.ntp.org" |awk '{print $2}' |tr '\n' ';')
     [ -n "${servers}" ] && ntp_servers+="${servers}"
fi
for i in $(crontab -l 2>/dev/null |grep -v ^# |grep -v ^$ |grep ntpdate |awk -F'ntpdate' '{print $2}' |awk '{print $1}')
do
    echo ${ntp_servers} |grep $i &>/dev/null
    [ $? -ne 0 ] && ntp_servers+="${i};"
done
if [ ! -n "$ntp_servers" ];then
    echo l_ntpserver="null"
else
    echo l_ntpserver="${ntp_servers}"
fi
#CPU型号
cpu_num=`cat /proc/cpuinfo |grep 'model name' |awk -F': ' '{print $2}' |uniq -c |wc -l`
echo -n "l_cpumodel="
for i in `seq 1 ${cpu_num}`
do
    cpu_n=`cat /proc/cpuinfo |grep 'model name' |awk -F': ' '{print $2}' |uniq -c |sed -n "${i}p"`
    read a b < <(echo $cpu_n)
    echo -n "${b} x ${a};"
done
echo ""

#CPU个数
cpu_num=`cat /proc/cpuinfo |grep 'model name' |awk -F': ' '{print $2}' |wc -l`
echo l_cpunum="${cpu_num}"

#内存数量
mem_num=`dmidecode|grep -P -A5 "Memory\s+Device"|grep Size|grep -v Range |grep -v "No Module Installed" |wc -l`
echo l_memnum="${mem_num}"

#内存大小
mem_k=`cat /proc/meminfo |grep MemTotal |awk '{print $2}'`
bc=`which bc 2>/dev/null`
if [ -n "$bc" ];then
    mem_g=$(printf "%.2f" `echo "scale=2; ${mem_k}/1024" |bc`)
else
    mem_g=`free -m |grep  Mem |awk '{print $2}'`
fi
echo l_memsize="${mem_g}M"

#本地磁盘数量
disk_num=`fdisk -l 2>/dev/null |grep "Disk /dev/" |grep -v mapper |awk '{print $2,$3,$4}' |uniq |awk -F/ '{print $3}' |sed s/[[:space:]]//g |wc -l`
echo l_disknum="${disk_num}"

#磁盘大小
echo -n "l_disksize="
for i in `seq 1 $disk_num`
do
    disk_info=`fdisk -l 2>/dev/null |grep "Disk /dev/" |grep -v mapper |awk '{print $2,$3,$4}' |uniq |awk -F/ '{print $3}' |sed -n ${i}p |sed s/[[:space:]]//g |tr -d ',' |tr ':' ' '`
    read a b < <(echo ${disk_info})
    echo -n "磁盘名###${a}@@@磁盘大小###${b}@@@@@"
done
echo ''

#获取MAC地址
#net_mac=$(ip addr |grep -A3 BROADCAST |egrep  -A1 'LOWER_UP' |grep ether |awk '{print $2}' |tr '\n' ';' |sed "s/\;$//g")
#echo l_mac="${net_mac}"
echo -n "l_mac="
for i in $(ip addr |grep -A3 BROADCAST |egrep  'LOWER_UP' |awk -F': ' '{print $2}')
do
    net_mac=$(ip addr |grep -A3 BROADCAST |egrep  -A1 $i |grep ether |awk '{print $2}' |tr '\n' ';' |sed "s/\;$//g")
    echo -n "name###${i}@@@mac###${net_mac}@@@@@"
done
echo ""

#Inode使用情况 l_inode
m=`df -hiTPBK |sed '1d' |grep -v "/dev/sr" |grep -v tmpfs |grep -v devtmpfs |grep -v "loop"  |wc -l`
echo -n "l_inode="
for ((i=1;i<=m;i++))
do
    read a b c d e f g < <(df -hiTPBK |sed '1d' |grep -v "/dev/sr" |grep -v tmpfs |grep -v devtmpfs |grep -v "loop"  |sed -n "${i}p")
    echo -n "Filesystem###${a}@@@Type###${b}@@@Inodes###${c}@@@IUsed###${d}@@@IFree###${e}@@@IUse%###${f}@@@Mounted on###${g}@@@@@"
done
echo ''

#管理员账号
admin=$(cat /etc/passwd |egrep -v "^(s*)#|^$" |awk -F: '{if ($3=="0")print $1}' |tr '\n' ';' | sed "s/\;$//g")
echo l_adminaccount="${admin}"

#系统最大文件打开数
file_open=$(ulimit -n)
echo l_openfiles="${file_open}"

#拥有sh权限账号
num=`cat /etc/passwd |egrep -v "nologin|shutdown" |grep sh |awk -F ':' '{print $1,$7}' |wc -l`
if  [ ${num} == 0 ];then
    echo "l_sh=null"
else
    echo -n "l_sh="
    for i in `seq 1 $num`
    do
        read a b < <(cat /etc/passwd |egrep -v "nologin|shutdown" |grep sh |awk -F ':' '{print $1,$7}' |sed -n ${i}p)
	echo -n "username###${a}@@@sh_type###${b}@@@@@"
    done
    echo ""
fi

#umask值设置
u_mask=$(umask)
echo l_umask="${u_mask}"

#拥有sudo权限账号或组
sudoer=$(egrep -v "^#|^Default|^%wheel|^root|^$" /etc/sudoers | grep 'ALL=' | awk '{print $1}' |tr '\n' ';' |sed "s/\;$//g")
if [ -n "${sudoer}" ];then
    echo l_soduers="${sudoer}"
else
    echo "l_soduers=null"
fi

#系统运行模式
which runlevel &>/null
[ $? -eq 0 ] && sys_run=$(runlevel |awk '{print $2}')
if [ ! -n "${sys_run}" ];then
    sys_run=$(who -r |awk '{print $2}')
fi
echo l_sysruntype="${sys_run}"

#系统内核版本
uname=`uname -r`
echo l_kernelinfo="${uname}"

#LIMIT参数设置情况 l_limitinfo
limit_num=$(cat /etc/security/limits.conf |egrep -v "^(s*)#|^$" |egrep "hard|soft" |wc -l)
if [ ${limit_num} -ne 0 ];then
    echo -n "l_limitinfo="
    for i in  `seq 1 $limit_num`
    do
	read a b c d < <(cat /etc/security/limits.conf |egrep -v "^(s*)#|^$" |egrep "hard|soft" |sed -n ${i}p)
	echo -n "domain###${a}@@@type###${b}@@@item###${c}@@@value###${d}@@@@@"
    done
    echo ""
else
    echo "l_limitinfo=null"
fi

#防火墙状态 l_firewall
if [ "${os_type}" == "UBUNTU" ];then
    status=$(ufw status |awk '{print $2}')
    if [ "${status}" == "active" ];then
        echo "l_firewall=active"
    else
	echo "l_firewall=inactive"
    fi
elif [ "${os_type}" == "SUSE" ];then
    rcSuSEfirewall2 status &>/dev/null
    if [ $? -eq 0 ];then
        echo l_firewall="active"
    else
        echo "l_firewall=inactive"
    fi
else
    case ${systemnum} in
    7)
    systemctl status firewalld.service &>/dev/null
    if [ $? -eq 0 ];then
        echo "l_firewall=active"
    else
        echo "l_firewall=inactive"
    fi
    ;;
    *)
    service iptables status  &>/dev/null
    if [ $? -eq 0 ];then
        echo "l_firewall=active"
    else
        echo "l_firewall=inactive"
    fi
    ;;
    esac
fi

#selinux状态 l_selinux
which getenforce &>/dev/null
if [ $? -eq 0 ];then
    echo "l_selinux=$(getenforce)"
else
    echo "l_selinux=no selinux"
fi
#swap空间使用情况 l_swap
swap=$(free -m |grep -i swap |awk '{print $2,$3,$4}')
read a b c < <(echo ${swap})
if [ $a != 0 ];then
swap_used=$(printf "%d%%" $((b*100/a)))
fi
echo "l_swap=total###${a}@@@used###${b}@@@free###${c}@@@使用率###${swap_used:-0}@@@@@"


#LVM配置 l_lvm
if $(lvs 2>/dev/null | awk '{print $1}' | grep -q 'LV'); then
    echo "l_lvm=已配置"
else
    echo "l_lvm=未配置"
fi

#计划任务 l_crontab
z=0
echo -n "l_crontab="
for user in $(cut -f1 -d: /etc/passwd)
do
    cron=`crontab -l -u ${user} 2>/dev/null`
    if [ -n "$cron" ];then
        n=`crontab -l -u ${user} |wc -l`
        for m in `seq 1 $n`
        do
            let z+=1
            read a b c d e f < <(crontab -l -u ${user} |sed -n "${m}p" |sed "s/$/;/g")
            echo -n "minute###${a}@@@hour###${b}@@@day###${c}@@@month###${d}@@@weekday###${e}@@@command###${f}@@@user###${user}@@@@@"
        done
    fi
done
echo ''

#DNS设置
dnsname=$(cat /etc/resolv.conf |egrep -v "^(s*)#|^$|127.0.0.1" |grep nameserver |awk '{print $2}' |tr '\n' ';' |sed "s/\;$//g")
if [ -n "$dnsname" ];then
    echo "l_dnsconfig=${dnsname}"
else
    echo "l_dnsconfig=null"
fi

#主机类型
dmidecode -s system-product-name &>/dev/null
if [ $? -eq 0 ];then
    virtual=$(dmidecode -s system-product-name |grep -i virtual)
    KVM=$(dmidecode -s system-product-name | grep -i KVM)
    if [ -n "$virtual" -o -n "$KVM" ];then
	#echo "sys_type=Virtual"
	echo "sys_type=1"
    else
	#echo "sys_type=Physical"
	echo "sys_type=2"
    fi
else
    echo 'sys_type=null'
fi

# 子网掩码
netmask=$(ifconfig | grep -i 'mask' | grep -v '127.0.0.1' | awk '{print $4}' |head -1|cut -d ":" -f 2)
echo "netmask=${netmask}"

# 网关
gateway=$(ip route show | grep "default" |awk '{print $3}')
echo "gateway=${gateway}"

#磁盘空间使用状态
df_info=$(timeout 5s df &>/dev/null)
# df_info=$(df)
if [ $? == 0 ];then
    m=`df -hP |grep -v grep |grep -v tmpfs |sed '1d' |wc -l`
    echo "l_diskpartition=["
    for ((i=1;i<=m;i++))
    do
        disk=`df -hP |grep -v grep |grep -v tmpfs |sed '1d' |sed -n "${i}p"`
        read a b c d e f < <(echo ${disk})
        if [ $i != $m ];then
            echo '{"PartitionName": "'$a'", "Size": "'$b $e $f'"},'
        else
            echo '{"PartitionName": "'$a'", "Size": "'$b $e $f'"}'
        fi
    done
    echo "]"
else
    m=`df -l -hP |grep -v grep |grep -v tmpfs |sed '1d' |wc -l`
    echo "l_diskpartition=["
    for ((i=1;i<=m;i++))
    do
        disk=`df -l -hP |grep -v grep |grep -v tmpfs |sed '1d' |sed -n "${i}p"`
        read a b c d e f < <(echo ${disk})
        if [ $i != $m ];then
            echo '{"PartitionName": "'$a'", "Size": "'$b $e $f'"},'
        else
            echo '{"PartitionName": "'$a'", "Size": "'$b $e $f'"}'
        fi
    done
    echo "]"
fi

# 系统启动时间
echo l_boottime=`who -b |awk '{print $3" "$4}' `

#网卡速率
ip_address=`netstat -tulnp | grep -w gse_agent | grep LISTEN | head -1 |awk '{print $4}' | awk -F ':' '{print $1}'`

if [ -z "$ip_address" ]; then
  echo ""
else
  echo l_ethspeed=$(ethtool `ip addr | grep $ip_address | awk '{print $NF}'` | grep Speed | awk '{print $2}')
fi

#硬件信息
dmi_info=$(dmidecode -t1)
echo l_manufacturer=$(echo "$dmi_info" | grep Manufacturer | awk -F : '{print $2}' | awk 'gsub(/^ *| *$/,"")')
echo l_model=$(echo "$dmi_info" | grep "Product Name" | awk -F : '{print $2}' | awk 'gsub(/^ *| *$/,"")')
echo l_sn=$(echo "$dmi_info" | grep "Serial Number" | awk -F : '{print $2}' | awk 'gsub(/^ *| *$/,"")')

echo -n "@end@"