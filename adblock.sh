#!/bin/sh
#Put in /etc/adblock.sh

#Script to grab and sort a list of adservers and malware

#Check proper DHCP config and, if necessary, update it
uci get dhcp.@dnsmasq[0].addnhosts > /dev/null 2>&1 || uci add_list dhcp.@dnsmasq[0].addnhosts=/etc/block.hosts && uci commit

#Leave crontab alone, or add to it
grep -q "/etc/adblock.sh" /etc/crontabs/root || echo "0 4 * * 0,3 sh /etc/adblock.sh" >> /etc/crontabs/root

#Delete the old block.hosts to make room for the updates
rm -f /etc/block.hosts

#Download and process the files needed to make the lists (add more, if you want)
wget -qO- http://www.mvps.org/winhelp2002/hosts.txt| sed 's/0.0.0.0/127.0.0.1/g' |grep "^127.0.0.1" > /tmp/block.build.list
wget -qO- http://www.malwaredomainlist.com/hostslist/hosts.txt|grep "^127.0.0.1" >> /tmp/block.build.list
wget -qO- "http://hosts-file.net/.\ad_servers.txt"|grep "^127.0.0.1" >> /tmp/block.build.list
wget -qO- "http://adaway.org/hosts.txt"|grep "^127.0.0.1" >> /tmp/block.build.list

#Add black list, if non-empty
[ -s "/etc/black.list" ] && awk '/^[^#]/ { print "127.0.0.1",$1 }' /etc/black.list >> /tmp/block.build.list

#Sort the download/black lists
awk '{sub(/\r$/,"");print $1,$2}' /tmp/block.build.list|sort|uniq > /tmp/block.build.before

if [ -s "/etc/white.list" ]
then
    #Filter the blacklist, supressing whitelist matches
    awk '/^[^#]/ {sub(/\r$/,"");print $1}' /etc/white.list | grep -vf - /tmp/block.build.before > /etc/block.hosts
else
    cat /tmp/block.build.before > /etc/block.hosts
fi

#Delete files used to build list to free up the limited space
rm -f /tmp/block.build.before
rm -f /tmp/block.build.list

#Restart dnsmasq
/etc/init.d/dnsmasq restart

exit 0