#!/bin/bash

HAPROXY_API_SOCK=/var/run/haproxy/api.sock
##
# Cert name parsers
##
cert_dn() {
    cert="$1"
    basename "${cert%%.pem}"
}

show_cert() {
    cert="$1"
    echo "show ssl cert $cert" | socat stdio "$HAPROXY_API_SOCK"
}

##
# HAProxy certificate functions
##
cert_exists() {
    cert="$1"
    show_cert "$cert" | grep -q "$cert"
    return $?
}

new_cert() {
    cert="$1"
    echo "new ssl cert $cert" | socat stdio "$HAPROXY_API_SOCK"
}

set_cert() {
    cert="$1"
    echo -e "set ssl cert $cert <<\n$(grep -v ^$ "$cert")\n" | socat stdio "$HAPROXY_API_SOCK"
}

abort_cert() {
    cert="$1"
    echo "abort ssl cert $cert" | socat stdio "$HAPROXY_API_SOCK"
}

commit_cert() {
    cert="$1"
    echo "commit ssl cert $cert" | socat stdio "$HAPROXY_API_SOCK"
}

##
# HAProxy maintenance helpers
##
server_state() {
    be="$1"
    srv="$2"
    echo "show servers state $be" | \
        socat stdio "$HAPROXY_API_SOCK" | \
        awk '{ print $2 " " $4 " " $7 }' | \
        grep "$be $srv" | \
        awk '{ print $3 }'
}

set_server_state() {
    be="$1"
    srv="$2"
    state="$3"
    echo "set server $be/$srv state $state"
    echo "set server $be/$srv state $state" | socat stdio "$HAPROXY_API_SOCK"
}

state_to_num() {
    state="$1"
    case "$state" in
        ready)
            echo -n 0
            ;;
        maint)
            echo -n 1
            ;;
        drain)
            echo -n 8
            ;;
        *)
            echo -n 0
            ;;
    esac
}

num_to_state() {
    # Got the mask values from enum srv_admin in
    # https://github.com/haproxy/haproxy/blob/2c776f1c30c85be11c9ba8ca8d9a7d62690d1a32/include/haproxy/server-t.h
    num="$1"
    if [[ $(( "$num" & 0x23 )) -gt 0 ]]; then
        echo -n "maint"
    elif [[ $(( "$num" & 0x18 )) -gt 0 ]]; then
        echo -n "drain"
    else
        echo -n "ready" # Probably
    fi
}

server_state_name() {
    num_to_state "$(server_state "$@")"
}


set_server_state_and_wait() {
    be="$1"
    srv="$2"
    state="$3"
    while true; do
        if [[ -S "$HAPROXY_API_SOCK" ]]; then
            state_name="$(server_state_name "$be" "$srv")"
            if [[ "$state_name" == "$state" ]]; then
                echo "$be $srv server in state $state_name"
                break
            fi
            echo "Wait for HAProxy API..."
            echo "$be $srv server in state $(num_to_state "$(server_state "$be" "$srv")")"
            set_server_state "$be" "$srv" "$state"
            sleep 1
        fi
    done
}

haproxy_running() {
    echo "show info" | socat stdio "$HAPROXY_API_SOCK" | grep -q ^Pid
    return $?
}

wait_for_haproxy() {
    wait_seconds="${1:-30}"
    echo -n "Waiting for HAProxy API..."
    while true; do
        if ( haproxy_running ); then break; fi
        if [[ "$wait_seconds" -le 0 ]]; then
            echo "Failed to find haproxy"
            return 1
        else
            echo -n "."
            sleep 1
        fi
    done
    echo "found"
    return 0
}

server_exists() {
    be="$1"
    srv="$2"
    echo "show servers state $be" | socat stdio "$HAPROXY_API_SOCK" | grep -v '^$' | awk '{ print $2 "/" $4 }' | tail -n +3 | grep -q "$be/$srv"
}

all_certs() {
    show_cert | tail -n +2 | grep -v '^$' | grep -v /haproxy-acme.pem
}
