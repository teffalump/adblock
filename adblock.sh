#!/bin/sh
#Put in /etc/adblock.sh

#Script to grab and sort a list of adservers and malware

#Pre-defined commands (change the cron command to what is comfortable, or leave as is)
FW1="iptables -t nat -I PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53"
FW2="iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53"
CRON="0 4 * * 0,3 sh /etc/adblock.sh"
DNSMASQ_EDITED="1"

echo 'Updating config, if necessary...'

#Check proper DHCP config and, if necessary, update it
uci get dhcp.@dnsmasq[0].addnhosts > /dev/null 2>&1 && DNSMASQ_EDITED="0" || uci add_list dhcp.@dnsmasq[0].addnhosts=/etc/block.hosts && uci commit

#Leave crontab alone, or add to it
grep -q "/etc/adblock.sh" /etc/crontabs/root || echo "$CRON" >> /etc/crontabs/root

#Add firewall rules if necessary
grep -q "$FW1" /etc/firewall.user || echo "$FW1" >> /etc/firewall.user
grep -q "$FW2" /etc/firewall.user || echo "$FW2" >> /etc/firewall.user

#Delete the old block.hosts to make room for the updates
rm -f /etc/block.hosts

echo 'Downloading hosts lists...'

#Download and process the files needed to make the lists (add more, if you want)
wget -qO- http://www.mvps.org/winhelp2002/hosts.txt| awk '/^0.0.0.0/' > /tmp/block.build.list
wget -qO- http://www.malwaredomainlist.com/hostslist/hosts.txt|awk '{sub(/^127.0.0.1/, "0.0.0.0")} /^0.0.0.0/' >> /tmp/block.build.list
wget -qO- "http://hosts-file.net/.\ad_servers.txt"|awk '{sub(/^127.0.0.1/, "0.0.0.0")} /^0.0.0.0/' >> /tmp/block.build.list

#need GNU wget from opkg since BusyBox wget doesn't handle https well (for me it seems, lol)
wget -qO- --no-check-certificate "https://adaway.org/hosts.txt"|awk '{sub(/^127.0.0.1/, "0.0.0.0")} /^0.0.0.0/' >> /tmp/block.build.list

echo 'Adding blacklist, if necessary...'

#Add black list, if non-empty
[ -s "/etc/black.list" ] && awk '/^[^#]/ { print "0.0.0.0",$1 }' /etc/black.list >> /tmp/block.build.list

echo 'Sorting lists...'

#Sort the download/black lists
awk '{sub(/\r$/,"");print $1,$2}' /tmp/block.build.list|sort -u > /tmp/block.build.before

echo 'Adding ipv6 support...'

#Add ipv6 support
awk '1;{print "::",$2}' /tmp/block.build.before > /tmp/block.build.tmp && mv /tmp/block.build.tmp /tmp/block.build.before

echo 'Filtering white list, if necessary...'

if [ -s "/etc/white.list" ]
then
    #Filter the blacklist, supressing whitelist matches
    #  This is relatively slow =-(
    awk '/^[^#]/ {sub(/\r$/,"");print $1}' /etc/white.list | grep -vf - /tmp/block.build.before > /etc/block.hosts
else
    cat /tmp/block.build.before > /etc/block.hosts
fi

echo 'Cleaning up...'

#Delete files used to build list to free up the limited space
rm -f /tmp/block.build.before
rm -f /tmp/block.build.list

echo 'Restarting dnsmasq...'

#Restart dnsmasq
if [ "$DNSMASQ_EDITED" -eq "0" ]
then
    pkill -HUP dnsmasq
else
    /etc/init.d/dnsmasq restart
fi

exit 0