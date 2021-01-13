#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

err_report() {
    echo "An error occurded on line $1 of this script."
}

trap 'err_report $LINENO' ERR

random_string() {
    LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c32
}

if [ ! "$(id -u)" -eq 0 ]; then
	echo "This script needs to be run as root or through sudo"
	exit 1
fi

# switch to dir of script in case its executed from somewhere else
cd "$(dirname "$(readlink -f "$0")")"

if [ "$(ucr get appcenter/apps/kopano-core/status)" != "installed" ]; then
    echo "Kopano Core is not installed"
    exit 1
fi

if [ "$(ucr get appcenter/apps/openid-connect-provider/status)" = "installed" ]; then
    echo "Cannot run on the same system as the openid-connect-provider app"
    exit 1
fi

if [ "$(ucr get appcenter/apps/kopano-mmet/status)" = "installed" ]; then
    echo "Cannot run on the same system as the kopano-meet app"
    exit 1
fi

eval "$(ucr shell)"

if [ ! -e ./.env ]; then
	FQDN="$hostname.$domainname"

	cat <<-EOF >"./.env"
FQDN=$FQDN
INSECURE=no
TZ=Europe/Amsterdam
COMPOSE_PROJECT_NAME=kopano
EOF
fi

source .env

echo "configuring Apache"
cat << EOF >/etc/apache2/ucs-sites.conf.d/kopano-api.conf
ProxyPass /.well-known/openid-configuration http://127.0.0.1:2015/.well-known/openid-configuration retry=0
ProxyPass /konnect/v1/jwks.json http://127.0.0.1:2015/konnect/v1/jwks.json retry=0
ProxyPass /konnect/v1/session http://127.0.0.1:2015//konnect/v1/session retry=0
ProxyPass /konnect/v1/static http://127.0.0.1:2015/konnect/v1/static retry=0
ProxyPass /konnect/v1/token http://127.0.0.1:2015/konnect/v1/token retry=0
ProxyPass /konnect/v1/userinfo http://127.0.0.1:2015/konnect/v1/userinfo retry=0
ProxyPass /signin/ http://127.0.0.1:2015/signin/ retry=0
ProxyPass /api/gc/v1/ http://127.0.0.1:2015/api/gc/v1/ retry=0
ProxyPass /api/kvs/v1/ http://127.0.0.1:2015/api/kvs/v1/ retry=0
ProxyPass /grapi-explorer/ http://127.0.0.1:2015/grapi-explorer/ retry=0
EOF

invoke-rc.d apache2 reload

echo "starting containers"
docker-compose pull
docker-compose up -d

echo "setting config options in server.cfg for oidc"
ucr set \
    kopano/cfg/server/kcoidc_issuer_identifier="https://$FQDN" \
    kopano/cfg/server/enable_sso=yes \
    kopano/cfg/server/kcoidc_initialize_timeout?360

echo "restarting kopano-server to apply changes"
systemctl restart kopano-server

echo "Please go to https://$FQDN/grapi-explorer/ to make test queries against the Kopano RestAPI."