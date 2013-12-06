#!/bin/sh
#Put in /etc/adblock.sh

#Script to grab and sort a list of adservers and malware

#Delete the old block.hosts to make room for the updates
rm -f /etc/block.hosts

#Download and process the files needed to make the lists (add more, if you want)
wget -qO- http://www.mvps.org/winhelp2002/hosts.txt|grep "^127.0.0.1" > /tmp/block.build.list
wget -qO- http://www.malwaredomainlist.com/hostslist/hosts.txt|grep "^127.0.0.1" >> /tmp/block.build.list
wget -qO- "http://hosts-file.net/.\ad_servers.txt"|grep "^127.0.0.1" >> /tmp/block.build.list
wget -qO- "http://adaway.org/hosts.txt"|grep "^127.0.0.1" >> /tmp/block.build.list

#Add black list, if non-empty
[ -s "/etc/black.list" ] && sed -e 's/^/127.0.0.1\t/g' /etc/black.list >> /tmp/block.build.list

#Sort the download/black lists
sed -e 's/\r//g' -e 's/^127.0.0.1[ ]\+/127.0.0.1\t/g' /tmp/block.build.list|sort|uniq > /tmp/block.build.before

if [ -s "/etc/white.list" ]
then
    #Filter the blacklist, supressing whitelist matches
    sed -e 's/\r//g' /etc/white.list > /tmp/white.list
    grep -vf /tmp/white.list /tmp/block.build.before > /etc/block.hosts
    rm -f /tmp/white.list
else
    cat /tmp/block.build.before > /etc/block.hosts
fi

#Delete files used to build list to free up the limited space
rm -f /tmp/block.build.before
rm -f /tmp/block.build.list

#Restart dnsmasq
/etc/init.d/dnsmasq restart

exit 0