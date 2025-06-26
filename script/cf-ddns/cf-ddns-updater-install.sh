#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --dns-record <DNS_RECORD>"
    echo "  --cf-zone-id <CF_ZONE_ID>"
    echo "  --cf_zone-id-api-token <CF_ZONE_ID_API_TOKEN>"
    echo "  --notify-me-telegram <yes/no>"
    echo "  --telegram-chat-id <TELEGRAM_CHAT_ID>"
    echo "  --telegram-bot-api-token <TELEGRAM_BOT_API_TOKEN>"
    exit 1
}

# Parse command line arguments
while [ "$1" != "" ]; do
    case $1 in
        --dns-record )           shift; DNS_RECORD=$1 ;;
        --cf-zone-id )           shift; CF_ZONE_ID=$1 ;;
        --cf_zone-id-api-token ) shift; CF_ZONE_ID_API_TOKEN=$1 ;;
        --notify-me-telegram )   shift; NOTIFY_ME_TELEGRAM=$1 ;;
        --telegram-chat-id )     shift; TELEGRAM_CHAT_ID=$1 ;;
        --telegram-bot-api-token ) shift; TELEGRAM_BOT_API_TOKEN=$1 ;;
        * )                      usage
    esac
    shift
done

# Download script
curl -o /usr/local/bin/update-cloudflare-dns https://mk386.github.io/script/cf-ddns/update-cloudflare-dns
chmod +x /usr/local/bin/update-cloudflare-dns

# Download configuration file
curl -o /usr/local/bin/update-cloudflare-dns.conf https://mk386.github.io/script/cf-ddns/update-cloudflare-dns.conf

# Update configuration file with provided parameters
[ -n "$DNS_RECORD" ] && sed -i "s/(DNS_RECORD)/$DNS_RECORD/" /usr/local/bin/update-cloudflare-dns.conf
[ -n "$CF_ZONE_ID" ] && sed -i "s/(CF_ZONE_ID)/$CF_ZONE_ID/" /usr/local/bin/update-cloudflare-dns.conf
[ -n "$CF_ZONE_ID_API_TOKEN" ] && sed -i "s/(CF_ZONE_ID_API_TOKEN)/$CF_ZONE_ID_API_TOKEN/" /usr/local/bin/update-cloudflare-dns.conf
[ -n "$NOTIFY_ME_TELEGRAM" ] && sed -i "s/(NOTIFY_ME_TELEGRAM)/$NOTIFY_ME_TELEGRAM/" /usr/local/bin/update-cloudflare-dns.conf
[ -n "$TELEGRAM_CHAT_ID" ] && sed -i "s/(TELEGRAM_CHAT_ID)/$TELEGRAM_CHAT_ID/" /usr/local/bin/update-cloudflare-dns.conf
[ -n "$TELEGRAM_BOT_API_TOKEN" ] && sed -i "s/(TELEGRAM_BOT_API_TOKEN)/$TELEGRAM_BOT_API_TOKEN/" /usr/local/bin/update-cloudflare-dns.conf

# Add cron job
CRON_JOB="* * * * * /usr/local/bin/update-cloudflare-dns"
(crontab -l 2>/dev/null | grep -v "/usr/local/bin/update-cloudflare-dns"; echo "$CRON_JOB") | crontab -

echo "Installation and configuration completed successfully"
