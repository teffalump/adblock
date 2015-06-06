#!/bin/sh
#Put in /etc/adblock.sh

#Block ads, malware, etc.

# Only block wireless ads? Y/N
ONLY_WIRELESS="N"

# IPv6 support? Y/N
IPV6="N"

# Need SSL websites?
SSL="N"

# Try to transparently serve pixel response?
#   If enabled, understand the consequences and mechanics of this setup
TRANS="N"

# Exempt an ip range
EXEMPT="N"
START_RANGE="192.168.1.0"
END_RANGE="192.168.1.255"

# Redirect endpoint
ENDPOINT_IP4="0.0.0.0"
ENDPOINT_IP6="::"

#Change the cron command to what is comfortable, or leave as is
CRON="0 4 * * 0,3 sh /etc/adblock.sh"

#Need iptables-mod-nat-extra installed
if opkg list-installed | grep -q iptables-mod-nat-extra
then
    echo 'iptables-mod-nat-extra is installed!'
else
    echo 'Updating package list...'
    opkg update > /dev/null
    echo 'Installing iptables-mod-nat-extra...'
    opkg install iptables-mod-nat-extra > /dev/null
fi

#Need iptable-mod-iprange for exemption
if [ "$EXEMPT" == "Y" ]
then 
    if opkg list-installed | grep -q iptables-mod-iprange
    then
        echo 'iptables-mod-iprange installed'
    else
        echo 'Updating package list...'
        opkg update > /dev/null
        echo 'Installing iptables-mod-iprange...'
        opkg install iptables-mod-iprange > /dev/null
    fi
fi

#Need wget for https websites
if [ "$SSL" == "Y" ]
then
    if opkg list-installed wget | grep -q wget
    then
        if wget --version | grep -q +ssl
        then
            echo 'wget (with ssl) found'
        else
            # wget without ssl, need to reinstall full wget
            opkg update > /dev/null
            opkg install wget --force-reinstall > /dev/null
        fi
    else
        echo 'Updating package list...'
        opkg update > /dev/null
        echo 'Installing wget (with ssl)...'
        opkg install wget > /dev/null
    fi
fi


if [ "$ONLY_WIRELESS" == "Y" ]
then
    echo 'Wireless only blocking!'
    if [ "$EXEMPT" == "Y" ]
    then
        echo 'Exempting some ips...'
        FW1="iptables -t nat -I PREROUTING -m iprange ! --src-range $START_RANGE-$END_RANGE -i wlan+ -p tcp --dport 53 -j REDIRECT --to-ports 53"
        FW2="iptables -t nat -I PREROUTING -m iprange ! --src-range $START_RANGE-$END_RANGE -i wlan+ -p udp --dport 53 -j REDIRECT --to-ports 53"
    else
        FW1="iptables -t nat -I PREROUTING -i wlan+ -p tcp --dport 53 -j REDIRECT --to-ports 53"
        FW2="iptables -t nat -I PREROUTING -i wlan+ -p udp --dport 53 -j REDIRECT --to-ports 53"
    fi
else
    if [ "$EXEMPT" == "Y" ]
    then
        echo "Exempting some ips..."
        FW1="iptables -t nat -I PREROUTING -m iprange ! --src-range $START_RANGE-$END_RANGE -p tcp --dport 53 -j REDIRECT --to-ports 53"
        FW2="iptables -t nat -I PREROUTING -m iprange ! --src-range $START_RANGE-$END_RANGE -p udp --dport 53 -j REDIRECT --to-ports 53"
    else
        FW1="iptables -t nat -I PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53"
        FW2="iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53"
    fi
fi


DNSMASQ_EDITED="1"
FIREWALL_EDITED="1"

echo 'Updating config, if necessary...'

#Check proper DHCP config and, if necessary, update it
uci get dhcp.@dnsmasq[0].addnhosts > /dev/null 2>&1 && DNSMASQ_EDITED="0" || uci add_list dhcp.@dnsmasq[0].addnhosts=/etc/block.hosts && uci commit

#Leave crontab alone, or add to it
grep -q "/etc/adblock.sh" /etc/crontabs/root || echo "$CRON" >> /etc/crontabs/root

#Add firewall rules if necessary
grep -q "$FW1" /etc/firewall.user && FIREWALL_EDITED="0" || echo "$FW1" >> /etc/firewall.user
grep -q "$FW2" /etc/firewall.user && FIREWALL_EDITED="0" || echo "$FW2" >> /etc/firewall.user

#Delete the old block.hosts to make room for the updates
rm -f /etc/block.hosts

# Determining uhttpd/httpd_gargoyle for transparent pixel support
if [ "$TRANS" == "Y" ]
then
    ENDPOINT_IP4=$(uci get network.lan.ipaddr)
    if [ "$IPV6" == "Y"]
    then
        ENDPOINT_IP6=$(uci get network.lan6.ipaddr)
    fi
    if [ ! -e "/www/1.gif" ]
    then
        /usr/bin/wget -O /www/1.gif http://upload.wikimedia.org/wikipedia/commons/c/ce/Transparent.gif  > /dev/null
    fi
    if [ -s "/usr/sbin/uhttpd" ]
    then
        #The default is none, so I don't want to check for it, so just write it
        echo "uhttpd found..."
        echo "updating server error page to return transparent pixel..."
        uci set uhttpd.main.error_page="/1.gif" && uci commit
        /etc/init.d/uhttpd restart
    elif [ -s "/usr/sbin/httpd_gargoyle" ]
    then
        # Write without testing
        echo "httpd_gargoyle found..."
        echo "updating server error page to return transparent pixel..."
        uci set httpd_gargoyle.server.page_not_found_file="1.gif" && uci commit
        /etc/init.d/httpd_gargoyle restart
    else
        ENDPOINT_IP4="0.0.0.0"
        ENDPOINT_IP6="::"
        echo "Cannot find supported web server..."
    fi
fi

echo 'Downloading hosts lists...'

#Download and process the files needed to make the lists (enable/add more, if you want)
wget -qO- http://www.mvps.org/winhelp2002/hosts.txt| awk -v r="$ENDPOINT_IP4" '{sub(/^0.0.0.0/, r)} $0 ~ "^"r' > /tmp/block.build.list
wget -qO- "http://adaway.org/hosts.txt"|awk -v r="$ENDPOINT_IP4" '{sub(/^127.0.0.1/, r)} $0 ~ "^"r' >> /tmp/block.build.list
#wget -qO- http://www.malwaredomainlist.com/hostslist/hosts.txt|awk -v r="$ENDPOINT_IP4" '{sub(/^127.0.0.1/, r)} $0 ~ "^"r' >> /tmp/block.build.list
#wget -qO- "http://hosts-file.net/.\ad_servers.txt"|awk -v r="$ENDPOINT_IP4" '{sub(/^127.0.0.1/, r)} $0 ~ "^"r' >> /tmp/block.build.list

#Add black list, if non-empty
if [ -s "/etc/black.list" ]
then
    echo 'Adding blacklist...'
    awk -v r="$ENDPOINT_IP4" '/^[^#]/ { print r,$1 }' /etc/black.list >> /tmp/block.build.list
fi

echo 'Sorting lists...'

#Sort the download/black lists
awk '{sub(/\r$/,"");print $1,$2}' /tmp/block.build.list|sort -u > /tmp/block.build.before

#Filter (if applicable)
if [ -s "/etc/white.list" ]
then
    #Filter the blacklist, supressing whitelist matches
    #  This is relatively slow =-(
    echo 'Filtering white list...'
    egrep -v "^[[:space:]]*$" /etc/white.list | awk '/^[^#]/ {sub(/\r$/,"");print $1}' | grep -vf - /tmp/block.build.before > /etc/block.hosts
else
    cat /tmp/block.build.before > /etc/block.hosts
fi

safe_pattern=$(printf '%s\n' "$ENDPOINT_IP4" | sed 's/[[\.*^$(){}?+|/]/\\&/g')
safe_addition=$(printf '%s\n' "$ENDPOINT_IP6" | sed 's/[\&/]/\\&/g')

if [ "$IPV6" == "Y" ]
then
    echo 'Adding ipv6 support...'
    sed -i -re "s/^(${safe_pattern}) (.*)$/\1 \2\n${safe_addition} \2/g" /etc/block.hosts
fi

echo 'Cleaning up...'

#Delete files used to build list to free up the limited space
rm -f /tmp/block.build.list
rm -f /tmp/block.build.before

if [ "$FIREWALL_EDITED" -ne "0" ]
then
    echo 'Restarting firewall...'
    if [ -s "/usr/lib/gargoyle/restart_firewall.sh" ]
    then
        /usr/lib/gargoyle/restart_firewall.sh > /dev/null 2>&1
    else
        /etc/init.d/firewall restart > /dev/null 2>&1
    fi
fi

echo 'Restarting dnsmasq...'

#Restart dnsmasq
if [ "$DNSMASQ_EDITED" -eq "0" ]
then
    killall -HUP dnsmasq
else
    /etc/init.d/dnsmasq restart
fi

exit 0