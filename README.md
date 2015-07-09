## Description

In its basic usage, this script will modify the router such that blocked addresses are null routed and unreachable. Since the address blocklist is full of advertising, malware, and tracking servers, this setup is generally a good thing. In addition, the router will update the blocklist weekly. However, the blocking is leaky, so do not expect everything to be blocked.

## Setup

The script must be copied to an OpenWRT router (gargoyle firmware works fine, too).

For example, if the router is located at 192.168.1.1:

    # scp adblock.sh root@192.168.1.1:/etc/adblock.sh

Make the script executable:

    # chmod +x /etc/adblock.sh

## Basic usage

If you are running the script for the first time:

    # sh /etc/adblock.sh -f

There should be status updates in the output, but there should be *no* errors. If these commands complete without errors, the adblocking is active. You can test it by looking up, say, [google analytics](https://www.google-analytics.com).

## Whitelists and blacklists

The script supports defining whitelisted urls. That is, urls that will be filtered out of the downloaded blocklists. To whitelist urls, place them (one per line) in */etc/white.list*.

Similarly, the script supports defining blacklisted urls - urls that will be added to the downloaded blocklists. To blacklist urls, place them (one per line) in */etc/black.list*.

NOTE: The whitelist support is pretty stupid, so don't expect smart filtering (e.g., domain extrapolation). I've found it tedious, but worthwhile, to find the offending url in */etc/block.hosts* and copy it to */etc/white.list*.

## Advanced usage

### Toggle on and off

To toggle the blocking on and off, run the script with the -t switch:

    # sh /etc/adblock.sh -t

### Manually update blocklist

To manually update the blocklist, run the script without switches:

    # sh /etc/adblock.sh

### Configuration 

The config section of the script has some variables that alter the behaviour of the script.

For example, if you change:

    ONLY_WIRELESS="N"
    
to

    ONLY_WIRELESS="Y"
    
Then only the wireless interface of the router will filter the blocklist.

To change the configuration of an already active installation. I would toggle the adblocking off first, change the script, then toggle it back on. That is,

    # sh /etc/adblock.sh -t # turn off
    ...modify variables...
    # sh /etc/adblock.sh -t # turn on

However, if you change certain variables, you must re-update the blocklist because the redirection values will have changed.

Configurable variables:

* ONLY_WIRELESS (Y/N): Only filter on wireless interface
* EXEMPT (Y/N): Exempt ip range from filtering (between START_ RANGE and END_RANGE)
* IPV6*: (Y/N): Add IPv6 support
* SSL (Y/N): Install wget with ssl support (only needed for ssl websites)
* TRANS*: (Y/N): Modify router web server to server transparent pixel responses for blocked websites
* ENDPOINT_IP4/IP6*: Define the IP to return for blocked hostnames (IPv4 and IPv6)
* CRON: The cron line to put in the crontab

*: require updating the blocklist. 