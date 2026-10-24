#!/bin/sh
# Solo el balanceador (VM1) puede alcanzar los puertos que Docker publica
set -eu
for p in 80; do
  iptables -C DOCKER-USER ! -s 10.33.199.65 -p tcp -m conntrack --ctorigdstport "$p" --ctdir ORIGINAL -j DROP 2>/dev/null || iptables -I DOCKER-USER ! -s 10.33.199.65 -p tcp -m conntrack --ctorigdstport "$p" --ctdir ORIGINAL -j DROP
done
