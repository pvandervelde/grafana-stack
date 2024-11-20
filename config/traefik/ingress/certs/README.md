# Traefik certificates

Add the traefik certificate for the different services in this folder. The certificate should have the following
Subject Alternate Names:

* `grafana.<YOUR_DOMAIN>` for the grafana UI.
* `ingress-grafana.<YOUR_DOMAIN>` for the ingress proxy (traefik).
* `log.<YOUR_DOMAIN>` for the Loki log storage server.
* `prometheus.<YOUR_DOMAIN>` for the time series data base (mimir).
* `s3-grafana.<YOUR_DOMAIN>` for the Minio storage server.
* `traces.<YOUR_DOMAIN>` for the traces server (Tempo).

The certificate should be stored in a `tls.crt` file (public key) and a `tls.key` file (for the private key).
