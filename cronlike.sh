#!/bin/bash

# Generate and update certificates using ACME/LetsEncrypt
# Requires the following in haproxy.cfg:
# global
#    stats socket /var/run/haproxy/api.sock user haproxy group haproxy mode 660 level admin expose-fd listeners
#    ... your other global config ...
#
# frontend public_ssl
#    bind :::443 v4v6
#    mode tcp
#
#    tcp-request inspect-delay 5s
#    tcp-request content capture req.ssl_sni len 250
#    tcp-request content accept if { req_ssl_hello_type 1 }
#
#    use_backend be_acme if { req.ssl_alpn acme-tls/1 }
#    ... your other backends here ...
#
# backend be_acme
#    mode tcp
#    server acme_sh localhost:12443 disabled


source "$(dirname "$0")/helper_func.sh"
source "$(dirname "$0")/generate_self_signed_certs.sh"

# Validate the ACME config
if ! grep -qr CA_EMAIL /acme/conf; then
    if [[ -z "$ACME_EMAIL" ]]; then
        while true; do
            echo ""
            echo "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
            echo "YOU HAVE NOT SPECIFIED AN ACCOUNT FOR ACME REGISTRATION"
            echo "Please update env.acme to include your email and make sure"
            echo "to pass --env-file (or otherwise set the ACME_EMAIL environment"
            echo "variable."
            echo ""
            echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
            echo ""
            kill -TERM "$(/usr/bin/supervisorctl pid)"
            while true; do sleep 5; done
        done
    else
        /acme/acme.sh --register-account --email "$ACME_EMAIL"
    fi
fi

# Generate self-signed certs before using supervisord to actually boot haproxy
generate_self_signed_certs "$HAPROXY_CFG" "$DEPLOY_HAPROXY_PEM_PATH"
/usr/bin/supervisorctl start haproxy

ACME_BACKEND=be_acme
ACME_SERVER=acme_sh

# shellcheck disable=SC2119
if ! ( wait_for_haproxy && server_exists $ACME_BACKEND $ACME_SERVER); then
    echo "HAProxy not running or doesn't have a server $ACME_BACKEND/$ACME_SERVER"
fi

for cert in $(all_certs); do
    HOSTNAME=$(cert_dn "$cert")

    # Verify that we have a cert issued and wait for haproxy to boot
    if ( /acme/acme.sh --list | awk '{ print $5 }' | grep -q "$HOSTNAME" ); then
        echo "ACME: Cert $HOSTNAME exists"
    else
        echo "ACME: Issuing new certificate for $HOSTNAME"
        /acme/acme.sh --issue --alpn --tlsport 12443 -d "$HOSTNAME"
    fi

    # Deploy the certs
    /acme/acme.sh --deploy --deploy-hook haproxy -d "$HOSTNAME"
done

set_server_state_and_wait $ACME_BACKEND $ACME_SERVER maint

echo "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
echo ""
echo "SUCCESS!"
echo ""
echo "HAProxy running and certificates generated!"
if grep -q "^backend be_readme$" "$HAPROXY_CFG"; then
    echo ""
    echo "Verify you can connect:"
    echo "http://localhost or https://localhost (expect a cert warning)"
fi
echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"

while true; do
    echo "ACME: Sleeping for 24 hours from $(date)"
    sleep 86400
    echo "ACME: Running ACME cert renewal"
    set_server_state_and_wait $ACME_BACKEND $ACME_SERVER ready

    /acme/acme.sh --cron --home /acme --config-home /acme/conf

    set_server_state $ACME_BACKEND $ACME_SERVER maint
done
