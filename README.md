# HAProxy with easy ACME support

This repo can be used to build and run an HAProxy container that will automatically use [LetsEncrypt](https://letsencrypt.org) (or other ACME CA supported by [acme.sh](https://acme.sh")) to fetch certificates for backend servers running HTTP that you want to wrap in SSL.

You can also add additional HAProxy config of your own, although in the current incarnation any certs you put
in `/usr/local/etc/haproxy-certs` will be regenerated with ACME.

## Building
You can to build your own copy of this container to set a different default CA:

* `ACME_CA` (*optional*); use if you want to change the CA to e.g. ZeroSSL

```bash
git clone https://github.com/yostinso/acme-haproxy
cd acme-haproxy
docker build -t my-haproxy:latest --build-arg ACME_CA=letsencrypt .
```

## Docker configuration
### Required volumes
You need to create a volume (or two) to store the `acme.sh` config and generated certificates. You can either create a volume for all of `/acme` (although this might mean future versions of the container can't successfully upgrade `acme.sh`), or create the and mount the following two volumes (recommended):

* `/acme/certs`
* `/acme/conf`

### Optional volumes
You can optionally mount `haproxy.cfg` instead of building it into the container; it's located at:

* `/usr/local/etc/haproxy/haproxy.cfg`

### Required ports

* `443/tcp`
* `80/tcp`

By default you only need to expose port `443` unless you choose to add additional listeners to HAProxy. If you boot with the default haproxy.cfg, there will be a default listener on both 80 and 443 (with a self-signed cert) for testing.

### Environment variables
You **must** specify an email the first time you boot the container so that you can register
with the ACME CA. After the initial launch, it will be stored in the `haproxy_acme_conf` volume, but it doesn't hurt to keep using it. The easiest way to specify it is by updating `env.acme` to set `ACME_EMAIL=your@email.here`; the instructions for running the container below assume that you've done that.

## haproxy.cfg configuration
This is really beyond the scope of this README, but there are a couple of things to note:

* The container discovers which certificates to create/sign by interrogating HAProxy over the local API. It looks for certificates in `/usr/local/etc/haproxy-certs` that end in `.pem`. If you add additional certificates by mounting another folder or rebuilding the image, they will be ignored.

* The sample `haproxy.cfg` includes some (commented out) examples for e.g. forwarding to an SSL server or wrapping a normal HTTP server in SSL. There's also an example for [Teleport](https://goteleport.com) because figuring out how to handle multiplexing was a little tricky due to the way Teleport uses SNI.

* In the default config, HAProxy will also serve this README on both `:80` and `:443` (with a self-signed cert.) Try http://localhost after booting it up.


## Running

### Docker (standalone)
1. Create the volumes
    ```bash
    docker volume create haproxy_acme_certs
    docker volume create haproxy_acme_conf
    ```
2. Launch the container
    ```bash
    docker run \
        --env-file ./env.acme \
        -v "$(pwd)"/haproxy.cfg:/usr/local/etc/haproxy.cfg \
        -v haproxy_acme_certs:/acme/certs \
        -v haproxy_acme_conf:/acme/conf \
        -p 443:443 \
        --name haproxy \
        my-haproxy
    ```
    You may find it useful to link other containers or add explicits `hosts` entries so you can refer to hostnames in `haproxy.cfg`:
    ```bash
    docker run \
        --env-file ./env.acme \
        -v "$(pwd)"/haproxy.cfg:/usr/local/etc/haproxy.cfg \
        -v haproxy_acme_certs:/acme/certs \
        -v haproxy_acme_conf:/acme/conf \
        -p 443:443 \
        --name haproxy \
        --link other_container \
        --add-host other_host:10.0.0.2 \
        my-haproxy
    ```

### Docker-Compose (stack)
