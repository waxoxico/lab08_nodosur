#!/bin/bash
# Respaldo de base de datos, archivos y configuracion de Nodo Sur.
# Se ejecuta en VM4 (db1). Deja copia local y la replica a VM1 (proxy1).
# Retencion: 30 dias. Verificacion por checksum antes de replicar.
#
# Destino en la maquina: /usr/local/sbin/respaldo-nodosur.sh (modo 750)
set -uo pipefail

BASE=lab08_db
LOCAL=/var/backups/nodosur
REMOTO_USR=xavineta2026
REMOTO_IP=10.33.199.65
REMOTO_DIR=respaldos/db1
RETENCION=30
SELLO=$(date -u +%Y%m%d-%H%M%S)
DESTINO="$LOCAL/$SELLO"
LOG=/var/log/respaldo-nodosur.log

log() { echo "$(date -u +%FT%TZ) $*" | tee -a "$LOG"; }
fallo() { log "ERROR: $*"; exit 1; }

mkdir -p "$DESTINO" || fallo "no se pudo crear $DESTINO"
log "=== inicio $SELLO ==="

# 1. Base de datos
# --single-transaction: volcado coherente sin bloquear la base
# --routines --triggers --events: incluye lo que no son tablas
mysqldump --single-transaction --routines --triggers --events \
          --databases "$BASE" > "$DESTINO/db-$BASE.sql" \
  || fallo "mysqldump de $BASE"
gzip -f "$DESTINO/db-$BASE.sql"
log "base de datos: $(du -h "$DESTINO/db-$BASE.sql.gz" | cut -f1)"

# 2. Archivos del sitio (contenido compartido por NFS)
tar -czf "$DESTINO/archivos-wp-content.tgz" -C /srv/nfs wp-content \
  || fallo "tar de wp-content"
log "archivos: $(du -h "$DESTINO/archivos-wp-content.tgz" | cut -f1)"

# 3. Configuracion de esta maquina
tar -czf "$DESTINO/config-db1.tgz" \
    /etc/mysql /etc/exports /etc/netplan /etc/fstab 2>/dev/null
log "configuracion: $(du -h "$DESTINO/config-db1.tgz" | cut -f1)"

# 3b. Configuracion de VM1 (balanceador, DNS y monitoreo), via SSH
# Requiere en VM1 una regla de sudo acotada a este unico comando.
ssh -o BatchMode=yes xavineta2026@10.33.199.65 \
    "sudo tar -czf - /etc/haproxy /etc/bind /etc/ssl/haproxy /srv/monitoring" \
    > "$DESTINO/config-proxy1.tgz" 2>/dev/null \
  && log "configuracion de proxy1: $(du -h "$DESTINO/config-proxy1.tgz" | cut -f1)" \
  || log "AVISO: no se pudo respaldar la configuracion de proxy1"

# 4. Verificacion de integridad
( cd "$DESTINO" && sha256sum ./* > SHA256SUMS && sha256sum -c SHA256SUMS >/dev/null ) \
  || fallo "verificacion de checksums"
log "checksums verificados: $(wc -l < "$DESTINO/SHA256SUMS") archivos"

# 5. Copia al destino separado
rsync -a --delete-after -e "ssh -o BatchMode=yes" \
      "$LOCAL/" "$REMOTO_USR@$REMOTO_IP:$REMOTO_DIR/" \
  || fallo "replica a $REMOTO_IP"
log "replicado a $REMOTO_IP:$REMOTO_DIR"

# 6. Rotacion
find "$LOCAL" -maxdepth 1 -type d -name '20*' -mtime +$RETENCION -exec rm -rf {} +
log "rotacion aplicada (retencion $RETENCION dias)"

# 7. Metrica de salud del respaldo, para Prometheus
TEXTFILE=/var/lib/node_exporter/textfile/respaldo.prom
mkdir -p "$(dirname "$TEXTFILE")"
cat > "$TEXTFILE" <<METRICA
# HELP respaldo_ultimo_exito_timestamp Marca de tiempo del ultimo respaldo correcto
# TYPE respaldo_ultimo_exito_timestamp gauge
respaldo_ultimo_exito_timestamp $(date +%s)
# HELP respaldo_tamano_bytes Tamano del ultimo respaldo
# TYPE respaldo_tamano_bytes gauge
respaldo_tamano_bytes $(du -sb "$DESTINO" | cut -f1)
METRICA
log "metrica de salud escrita"

log "=== fin $SELLO ==="
