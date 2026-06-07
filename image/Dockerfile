# border_router egress-setup image: minimal Alpine with the routing tools the
# entrypoint needs (iproute2 for ip rule/route, nftables for masquerade).
# Built component-local and published as ghcr.io/alexmkx/garuda-border-router
# via .publish/public-workflows/publish-images.yml.
FROM alpine:3.20

RUN apk add --no-cache iproute2 nftables

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
