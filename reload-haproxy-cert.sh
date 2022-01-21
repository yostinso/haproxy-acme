#!/bin/bash

# Invoked from
# /acme/acme.sh --deploy --deploy-hook haproxy -d my.domain.tld
#
# And forced to pass us the PEM path by setting
# DEPLOY_HAPROXY_RELOAD="/acme/reload-haproxy-cert.sh \"\$_pem\""
#
# This is a dirty, dirty hack to get passed the certs getting deployed
# acme.sh:deploy/haproxy.sh calls eval on DEPLOY_HAPROXY_RELOAD, and before it
# does that, it sets _pem to the generated PEM path. Since we're invoked with eval
# we can get passed that value as an argument

source "$(dirname "$0")/helper_func.sh"

CERT="$1"

if ( ! cert_exists "$CERT" ); then
    new_cert "$CERT"
fi

set_cert "$CERT"

# Check transaction is for correct domain name and then commit the cert
# NB: This requires haproxy to be running
if ( haproxy_running ); then
    if ( show_cert "*$CERT" | grep -q "Subject: /CN=$(cert_dn "$CERT")" ); then
        # Commit
        commit_cert "$CERT"
        show_cert "$CERT"
    else
        # Abort
        show_cert "$CERT"
        abort_cert "$CERT"
        echo "ABORTED"
        exit 1
    fi
else
    echo "HAProxy not detected; not reloading"
fi