#!/bin/bash
# Respaldo de base de datos, archivos y configuracion de Nodo Sur.
# Se ejecuta en VM4 (db1) como root mediante respaldo-nodosur.timer.
# Copia local en /var/backups/nodosur y copia separada en VM1, con la
# cuenta de servicio "respaldo" (no depende de cuentas personales).
# Retencion de 30 dias aplicada por separado en origen y destino.
# Checksums verificados en origen y en destino.
set -uo pipefail

BASE=lab08_db
LOCAL=/var/backups/nodosur
REMOTO_USR=respaldo
REMOTO_IP=10.33.199.65
REMOTO_DIR=respaldos/db1
RETENCION=30
SELLO=$(date -u +%Y%m%d-%H%M%S)
DESTINO="$LOCAL/$SELLO"
LOG=/var/log/respaldo-nodosur.log
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10"
AVISOS=0

log()   { echo "$(date -u +%FT%TZ) $*" | tee -a "$LOG"; }
fallo() { log "ERROR: $*"; exit 1; }
aviso() { log "AVISO: $*"; AVISOS=$((AVISOS+1)); }

# Configuracion a respaldar (rutas relativas a /).
# Las listas remotas deben coincidir EXACTAMENTE con /etc/sudoers.d/respaldo de cada nodo.
CONF_DB1="etc/mysql etc/exports etc/netplan etc/fstab etc/ufw etc/rsyslog.d etc/systemd/system usr/local/sbin etc/mysqld_exporter"
CONF_PROXY1="etc/haproxy etc/bind etc/ssl/haproxy srv/monitoring etc/ufw etc/postfix etc/aliases etc/rsyslog.d etc/netplan etc/systemd/system etc/sudoers.d usr/local/sbin usr/local/bin"
CONF_WEB="srv/tas var/www/html/wp-config.php etc/apache2 etc/ufw etc/rsyslog.d etc/netplan etc/fstab etc/systemd/system usr/local/sbin usr/local/bin"

mkdir -p "$DESTINO" && chmod 700 "$DESTINO" || fallo "no se pudo crear $DESTINO"
log "=== inicio $SELLO ==="

# 1. Base de datos: volcado coherente sin bloquear el sitio
mysqldump --single-transaction --routines --triggers --events \
          --databases "$BASE" | gzip > "$DESTINO/db-$BASE.sql.gz" \
  || fallo "mysqldump de $BASE"
log "base de datos: $(du -h "$DESTINO/db-$BASE.sql.gz" | cut -f1)"

# 2. Archivos del sitio (contenido compartido por NFS)
tar -czf "$DESTINO/archivos-wp-content.tgz" -C /srv/nfs wp-content
rc=$?
# tar: 0 = correcto, 1 = algun archivo cambio durante la lectura (copia utilizable,
# normal con el sitio en uso), 2 o mas = error fatal
if [ "$rc" -eq 1 ]; then
  log "nota: wp-content cambio durante la lectura (tar codigo 1), copia utilizable"
elif [ "$rc" -ne 0 ]; then
  fallo "tar de wp-content (codigo $rc)"
fi
log "archivos: $(du -h "$DESTINO/archivos-wp-content.tgz" | cut -f1)"

# 3. Configuracion local (sin silenciar errores)
if tar -czf "$DESTINO/config-db1.tgz" -C / $CONF_DB1; then
  log "configuracion de db1: $(du -h "$DESTINO/config-db1.tgz" | cut -f1)"
else
  aviso "configuracion de db1 incompleta"
fi

# 4. Configuracion remota con la cuenta de servicio "respaldo"
remota() {  # $1 nombre, $2 IP, $3 rutas
  local f="$DESTINO/config-$1.tgz"
  if $SSH "respaldo@$2" "sudo /usr/bin/tar -czf - -C / $3" > "$f" && [ -s "$f" ]; then
    log "configuracion de $1: $(du -h "$f" | cut -f1)"
  else
    [ -s "$f" ] || rm -f "$f"
    aviso "configuracion de $1 incompleta o inaccesible"
  fi
}
remota proxy1 10.33.199.65 "$CONF_PROXY1"
remota web1   10.33.199.66 "$CONF_WEB"
remota web2   10.33.199.67 "$CONF_WEB"

# 5. Integridad en origen
( cd "$DESTINO" && sha256sum ./*.gz ./*.tgz > SHA256SUMS && sha256sum -c --quiet SHA256SUMS ) \
  || fallo "verificacion de checksums en origen"
log "checksums verificados en origen: $(wc -l < "$DESTINO/SHA256SUMS") archivos"

# 6. Copia separada, SIN --delete: un borrado en el origen no se propaga al destino
rsync -a -e "$SSH" "$DESTINO" "$REMOTO_USR@$REMOTO_IP:$REMOTO_DIR/" \
  || fallo "replica a $REMOTO_IP"
$SSH "$REMOTO_USR@$REMOTO_IP" "cd $REMOTO_DIR/$SELLO && sha256sum -c --quiet SHA256SUMS" \
  || fallo "verificacion de checksums en el destino"
log "replicado y verificado en $REMOTO_IP:$REMOTO_DIR/$SELLO"

# 7. Retencion de 30 dias, independiente en cada lado
find "$LOCAL" -maxdepth 1 -type d -name '20*' -mtime +"$RETENCION" -exec rm -rf {} +
$SSH "$REMOTO_USR@$REMOTO_IP" "find $REMOTO_DIR -maxdepth 1 -type d -name '20*' -mtime +$RETENCION -exec rm -rf {} +" \
  || aviso "rotacion en el destino"
log "rotacion aplicada (retencion $RETENCION dias en origen y destino)"

# 8. Metricas para Prometheus (escritura atomica)
TEXTFILE=/var/lib/node_exporter/textfile/respaldo.prom
mkdir -p "$(dirname "$TEXTFILE")"
cat > "$TEXTFILE.tmp" <<METRICA
# HELP respaldo_ultimo_exito_timestamp Marca de tiempo del ultimo respaldo correcto
# TYPE respaldo_ultimo_exito_timestamp gauge
respaldo_ultimo_exito_timestamp $(date +%s)
# HELP respaldo_tamano_bytes Tamano del ultimo respaldo
# TYPE respaldo_tamano_bytes gauge
respaldo_tamano_bytes $(du -sb "$DESTINO" | cut -f1)
# HELP respaldo_avisos Componentes que no se pudieron respaldar en la ultima ejecucion
# TYPE respaldo_avisos gauge
respaldo_avisos $AVISOS
METRICA
mv "$TEXTFILE.tmp" "$TEXTFILE"
log "metrica de salud escrita (avisos: $AVISOS)"
log "=== fin $SELLO ==="
