FROM pandoc/core AS readme_render
COPY README.md docs-render/* /tmp/
RUN pandoc /tmp/README.md -o /tmp/README.html && cat /tmp/README.headers /tmp/README.html > /tmp/README.haproxy


FROM haproxy:3.1
USER root
RUN apt-get update && apt-get install -y curl socat supervisor

USER haproxy
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
USER root

RUN mkdir -p /var/run/haproxy && chown haproxy:haproxy /var/run/haproxy

# ACME
VOLUME [ "/acme/certs", "/acme/conf" ]

# Default CA. See https://github.com/acmesh-official/acme.sh#supported-ca
ARG ACME_CA=letsencrypt

ENV LE_CONFIG_HOME /acme/conf
ENV DEPLOY_HAPROXY_PEM_PATH /usr/local/etc/haproxy-certs
ENV HAPROXY_CFG=/usr/local/etc/haproxy/haproxy.cfg
# This is a dirty, dirty hack to get passed the certs getting deployed
# acme.sh:deploy/haproxy.sh calls eval on DEPLOY_HAPROXY_RELOAD, and before it
# does that, it sets _pem to the generated PEM path. Since we're invoked with eval
# we can get passed that value as an argument
ENV DEPLOY_HAPROXY_RELOAD="/acme/reload-haproxy-cert.sh \"\$_pem\""

RUN mkdir -p "${DEPLOY_HAPROXY_PEM_PATH}" /acme/certs && \
    chown -R haproxy:haproxy /acme "${DEPLOY_HAPROXY_PEM_PATH}"

USER haproxy
WORKDIR /acme
RUN curl https://get.acme.sh | sh -s -- force --no-cron --accountemail "" --home /acme --config-home ${LE_CONFIG_HOME} --cert-home /acme/certs/ --accountconf /acme/conf/my-account.conf
RUN /acme/acme.sh --config-home /acme/conf --set-default-ca --server "${ACME_CA}"
COPY *.sh /acme

USER root
COPY --from=readme_render /tmp/README.haproxy /usr/local/etc/haproxy/README.haproxy

COPY supervisord.conf /etc/supervisor/supervisord.conf

USER haproxy
WORKDIR /

CMD [ "/usr/bin/supervisord" ]
