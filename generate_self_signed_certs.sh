#!/bin/bash
# source "$(dirname "$0")/helper_func.sh"

generate_self_signed_certs() {
    cfg="$1"
    cert_path="$2"

    certs=$(
        grep "^ *bind .*crt  *$cert_path.*pem" "$cfg" | \
        while IFS= read -r line; do

            cert=$(
                echo "$line" | awk '{ 
                    for (i=0; i<=NF; i++) {
                        if ($i == "crt") {
                            print $(i+1)
                            break
                        }
                    }
                }'
            )
            echo "$cert"
        done
    )

    generated=()
    for cert in $certs; do
        cn="$(cert_dn "$cert")"
        if [[ ! -f "$cert_path/$cn.pem" ]]; then
            tmp="/tmp/cert-$cn"
            mkdir -pv "$tmp"

            openssl genrsa > "$tmp/$cn.key"
            openssl req -new -key "$tmp/$cn.key" -subj "/CN=$cn" > "$tmp/$cn.csr"
            openssl x509 -req -days 7 -in "$tmp/$cn.csr" -signkey "$tmp/$cn.key" > "$tmp/$cn.crt"

            out="$cert_path/$cn.pem"
            cat "$tmp/$cn.key" "$tmp/$cn.crt" > "$out"

            rm -rv "$tmp"
            generated+=( "Generated $(openssl x509 -in "$out" -noout -subject)" )
        fi
    done
    echo "${generated[@]}"
}