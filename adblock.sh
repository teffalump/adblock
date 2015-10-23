#!/bin/sh
#Put in /etc/adblock.sh
#Block ads, malware, etc.

#### CONFIG SECTION ####

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

#### END CONFIG ####

#### FUNCTIONS ####

cleanup()
{
    #Delete files used to build list to free up the limited space
    echo 'Cleaning up...'
    rm -f /tmp/block.build.list
    rm -f /tmp/block.build.before
}

install_dependencies()
{
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
    if [ "$EXEMPT" = "Y" ]
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
    if [ "$SSL" = "Y" ]
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
}

add_config()
{
    if [ "$ONLY_WIRELESS" = "Y" ]
    then
        echo 'Wireless only blocking!'
        if [ "$EXEMPT" = "Y" ]
        then
            echo 'Exempting some ips...'
            FW1="iptables -t nat -I PREROUTING -m iprange ! --src-range $START_RANGE-$END_RANGE -i wlan+ -p tcp --dport 53 -j REDIRECT --to-ports 53"
            FW2="iptables -t nat -I PREROUTING -m iprange ! --src-range $START_RANGE-$END_RANGE -i wlan+ -p udp --dport 53 -j REDIRECT --to-ports 53"
        else
            FW1="iptables -t nat -I PREROUTING -i wlan+ -p tcp --dport 53 -j REDIRECT --to-ports 53"
            FW2="iptables -t nat -I PREROUTING -i wlan+ -p udp --dport 53 -j REDIRECT --to-ports 53"
        fi
    else
        if [ "$EXEMPT" = "Y" ]
        then
            echo "Exempting some ips..."
            FW1="iptables -t nat -I PREROUTING -m iprange ! --src-range $START_RANGE-$END_RANGE -p tcp --dport 53 -j REDIRECT --to-ports 53"
            FW2="iptables -t nat -I PREROUTING -m iprange ! --src-range $START_RANGE-$END_RANGE -p udp --dport 53 -j REDIRECT --to-ports 53"
        else
            FW1="iptables -t nat -I PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53"
            FW2="iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53"
        fi
    fi

    echo 'Updating config...'

    #Update DHCP config
    uci add_list dhcp.@dnsmasq[0].addnhosts=/etc/block.hosts > /dev/null 2>&1 && uci commit

    #Add to crontab
    echo "$CRON" >> /etc/crontabs/root

    #Update dnsmasq config for Tor
    TOR=`uci get tor.global.enabled 2> /dev/null`
    if [ "$TOR" == "1" ]
    then
        TORPORT=`uci get tor.client.dns_port`
        TORIP="127.0.0.1:$TORPORT"
        uci set dhcp.@dnsmasq[0].noresolv='1' > /dev/null &2>1 && uci commit
        uci add_list dhcp.@dnsmasq[0].server="$TORIP" > /dev/null &2>1 && uci commit
    fi

    # Add firewall rules
    echo "$FW1" >> /etc/firewall.user
    echo "$FW2" >> /etc/firewall.user

    # Provide hint if localservice is 1
    LS=`uci get dhcp.@dnsmasq[0].localservice 2> /dev/null`
    if [ "$LS" == "1" ]
    then
        echo "HINT: localservice is set to 1"
        echo "    Adblocking (and router DNS) over a VPN may not work"
        echo "    To allow VPN router DNS, manually set localservice to 0"
    fi


    # Determining uhttpd/httpd_gargoyle for transparent pixel support
    if [ "$TRANS" = "Y" ]
    then
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
        elif [ -s "/usr/sbin/httpd_gargoyle" ]
        then
            # Write without testing
            echo "httpd_gargoyle found..."
            echo "updating server error page to return transparent pixel..."
            uci set httpd_gargoyle.server.page_not_found_file="1.gif" && uci commit
        else
            echo "Cannot find supported web server..."
        fi
    fi
}

update_blocklist()
{
    #Delete the old block.hosts to make room for the updates
    rm -f /etc/block.hosts

    # Correct endpoint for transparent pixel response
    if [ "$TRANS" = "Y" ] && [ -e "/www/1.gif" ] && ([ -s "/usr/sbin/uhttpd" ] || [ -s "/usr/sbin/httpd_gargoyle" ])
    then
        ENDPOINT_IP4=$(uci get network.lan.ipaddr)
        if [ "$IPV6" = "Y" ]
        then
            ENDPOINT_IP6=$(uci get network.lan6.ipaddr)
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
        #Filter the blacklist, suppressing whitelist matches
        #  This is relatively slow =-(
        echo 'Filtering white list...'
        egrep -v "^[[:space:]]*$" /etc/white.list | awk '/^[^#]/ {sub(/\r$/,"");print $1}' | grep -vf - /tmp/block.build.before > /etc/block.hosts
    else
        cat /tmp/block.build.before > /etc/block.hosts
    fi

    if [ "$IPV6" = "Y" ]
    then
        safe_pattern=$(printf '%s\n' "$ENDPOINT_IP4" | sed 's/[[\.*^$(){}?+|/]/\\&/g')
        safe_addition=$(printf '%s\n' "$ENDPOINT_IP6" | sed 's/[\&/]/\\&/g')
        echo 'Adding ipv6 support...'
        sed -i -re "s/^(${safe_pattern}) (.*)$/\1 \2\n${safe_addition} \2/g" /etc/block.hosts
    fi
}

restart_firewall()
{
    echo 'Restarting firewall...'
    if [ -s "/usr/lib/gargoyle/restart_firewall.sh" ]
    then
        /usr/lib/gargoyle/restart_firewall.sh > /dev/null 2>&1
    else
        /etc/init.d/firewall restart > /dev/null 2>&1
    fi
}

restart_dnsmasq()
{
    if [ "$1" -eq "0" ]
    then
        echo 'Re-reading blocklist'
        killall -HUP dnsmasq
    else
        echo 'Restarting dnsmasq...'
        /etc/init.d/dnsmasq restart
    fi
}

restart_http()
{
    if [ -s "/usr/sbin/uhttpd" ]
    then
        echo 'Restarting uhttpd...'
        /etc/init.d/uhttpd restart
    elif [ -s "/usr/sbin/httpd_gargoyle" ]
    then
        echo 'Restarting httpd_gargoyle...'
        /etc/init.d/httpd_gargoyle restart
    fi
}
restart_cron()
{
    echo 'Restarting cron...'
    /etc/init.d/cron restart > /dev/null 2>&1
}

remove_config()
{
    echo 'Reverting config...'

    # Remove addnhosts
    uci del_list dhcp.@dnsmasq[0].addnhosts=/etc/block.hosts > /dev/null 2>&1 && uci commit

    # Remove cron entry
    sed -i '/adblock/d' /etc/crontabs/root

    # Remove firewall rules
    sed -i '/--to-ports 53/d' /etc/firewall.user
    
    # Remove Tor workarounds
    uci del_list dhcp.@dnsmasq[0].server > /dev/null 2>&1 && uci commit
    uci set dhcp.@dnsmasq[0].noresolv='0' > /dev/null 2>&1 && uci commit

    # Remove proxying
    uci delete uhttpd.main.error_page > /dev/null 2>&1 && uci commit
    uci set httpd_gargoyle.server.page_not_found_file="login.sh" > /dev/null 2>&1 && uci commit
}


toggle()
{
    # Check for cron as test for on/off
    if grep -q "adblock" /etc/crontabs/root
    then
        # Turn off
        echo 'Turning off!'
        remove_config
    else
        # Turn on
        echo 'Turning on!'
        add_config
    fi

    # Restart services
    restart_firewall
    restart_dnsmasq 1
    restart_http
    restart_cron
}

#### END FUNCTIONS ####

### Options parsing ####

case "$1" in
    # Toggle on/off
    "-t")
        toggle
        ;;
    #First time run
    "-f")
        install_dependencies
        add_config
        update_blocklist
        restart_firewall
        restart_dnsmasq 1
        restart_http
        restart_cron
        cleanup
        ;;
    #Reinstall
    "-r")
        remove_config
        install_dependencies
        add_config
        update_blocklist
        restart_firewall
        restart_dnsmasq 1
        restart_http
        restart_cron
        cleanup
        ;;
    #Default updates blocklist only
    *)
        update_blocklist
        restart_dnsmasq 0
        cleanup
        ;;
esac

#### END OPTIONS ####

exit 0
