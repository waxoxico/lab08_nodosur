#!/bin/bash
# Retencion de logs centralizados de Nodo Sur (VM1)
# Comprime los de mas de 1 dia y borra los de mas de 30 dias.
# Reemplaza a logrotate: los archivos son por dia y con nombre unico,
# por lo que "rotate 30" nunca eliminaba nada.
set -euo pipefail
DIR=/var/log/nodosur
DIAS=30
find "$DIR" -type f -name '*.log' -empty -mmin +60 -delete
find "$DIR" -type f \( -name '*.log' -o -name '*.log-*' \) ! -name '*.gz' -mtime +0 -exec gzip -9 {} +
find "$DIR" -type f -name '*.gz' -mtime +"$DIAS" -delete
logger -t limpieza-logs "retencion aplicada en $DIR: comprime >1 dia, borra >$DIAS dias"
