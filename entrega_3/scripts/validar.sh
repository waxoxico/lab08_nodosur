#!/bin/bash
# validar.sh — Validación de SOLO LECTURA del nodo web en contenedores y del balanceador.
# Grupo Tas_08 · Nodo Sur · Entrega 3
#
# Uso:
#   ./validar.sh nodo          en VM2 o VM3, con un usuario que tenga sudo
#   ./validar.sh balanceador   en VM1
#
# No modifica nada. Termina con código 0 si todo está bien y 1 si alguna comprobación falla.
# El nodo lee su nombre, IP, puerto y NFS del .env del Compose (por defecto en
# /srv/tas/wordpress-compose; se puede cambiar con la variable DIR).

set -u
DIR="${DIR:-/srv/tas/wordpress-compose}"
BALANCEADOR="10.33.199.65"
HOST_SITIO="www.lab08.nodosur.cl"
FALLAS=0

ok()     { printf '  [ OK ]  %s\n' "$1"; }
mal()    { printf '  [FALLA] %s\n' "$1"; FALLAS=$((FALLAS + 1)); }
aviso()  { printf '  [AVISO] %s\n' "$1"; }
titulo() { printf '\n== %s ==\n' "$1"; }

validar_nodo() {
  cd "$DIR" 2>/dev/null || { echo "No existe $DIR"; exit 2; }
  [ -r .env ] || { echo "No se puede leer $DIR/.env (¿se ejecuta con el usuario dueño?)"; exit 2; }
  set -a; . ./.env; set +a

  titulo "Contenedor del nodo $NODE_NAME ($PUBLISH_IP:$PUBLISH_PORT)"
  sudo docker compose config --quiet 2>/dev/null && ok "compose.yaml válido" || mal "compose.yaml inválido"

  estado=$(sudo docker inspect -f '{{.State.Health.Status}}' "$NODE_NAME" 2>/dev/null || echo ausente)
  [ "$estado" = healthy ] && ok "Contenedor $NODE_NAME en estado healthy" || mal "Contenedor $NODE_NAME: $estado"

  r=$(curl -s --max-time 5 -H "Host: $HOST_SITIO" "http://$PUBLISH_IP:$PUBLISH_PORT/health.php")
  case "$r" in
    "OK $NODE_NAME "*) ok "health.php responde: ${r%% sapi*}" ;;
    *) mal "health.php inesperado: '$r'" ;;
  esac

  h=$(curl -sI --max-time 5 -H "Host: $HOST_SITIO" "http://$PUBLISH_IP:$PUBLISH_PORT/" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-backend"{print $2}')
  [ "$h" = "$NODE_NAME" ] && ok "Encabezado X-Backend = $h" || mal "X-Backend = '$h' (esperado $NODE_NAME)"

  titulo "Almacenamiento compartido"
  src=$(sudo docker exec "$NODE_NAME" sh -c "df -P /var/www/html/wp-content | tail -1 | awk '{print \$1}'" 2>/dev/null)
  [ "$src" = "$NFS_ADDR:$NFS_PATH" ] && ok "wp-content dentro del contenedor viene de $src" || mal "wp-content en el contenedor: '$src'"

  titulo "Segmentación y arranque"
  sudo iptables -S DOCKER-USER 2>/dev/null | grep -q -- "! -s $BALANCEADOR/32 .*--ctorigdstport $PUBLISH_PORT .*-j DROP" \
    && ok "DOCKER-USER limita el puerto $PUBLISH_PORT al balanceador ($BALANCEADOR)" \
    || mal "Falta la regla de DOCKER-USER para el puerto $PUBLISH_PORT"
  [ "$(systemctl is-enabled docker-user-rules.service 2>/dev/null)" = enabled ] && [ "$(systemctl is-active docker-user-rules.service 2>/dev/null)" = active ] \
    && ok "docker-user-rules habilitado y activo" || mal "docker-user-rules no está habilitado y activo"
  [ "$(systemctl is-enabled apache2 2>/dev/null)" != enabled ] && [ "$(systemctl is-active apache2 2>/dev/null)" != active ] \
    && ok "Apache nativo deshabilitado e inactivo" || mal "Apache nativo sigue habilitado o activo"

  titulo "Secretos"
  meta=$(stat -c '%U:%G %a' /var/www/html/wp-config.php 2>/dev/null)
  [ "$meta" = "www-data:www-data 640" ] && ok "wp-config.php: $meta" || mal "wp-config.php: '$meta' (esperado www-data:www-data 640)"
  n=$(sudo grep -cE "^define\( *'(AUTH|SECURE_AUTH|LOGGED_IN|NONCE)_(KEY|SALT)'" /var/www/html/wp-config.php 2>/dev/null)
  p=$(sudo grep -c "put your unique phrase here" /var/www/html/wp-config.php 2>/dev/null)
  [ "$n" = 8 ] && [ "$p" = 0 ] && ok "8 claves y sales definidas, ninguna de ejemplo" || mal "Claves y sales: $n definidas, $p de ejemplo"
  [ "$(stat -c %a .env)" = 600 ] && ok ".env con modo 600" || mal ".env con modo $(stat -c %a .env)"
  grep -qiE 'passw|pwd|secret' compose.yaml && mal "compose.yaml contiene palabras de credenciales" || ok "compose.yaml sin credenciales"

  titulo "Imagen y hora"
  d=$(sudo docker image inspect "wordpress:$WP_IMAGE_TAG" --format '{{index .RepoDigests 0}}' 2>/dev/null)
  case "$d" in
    *d42f63cb89ad0eab*) ok "Imagen con el digest verificado" ;;
    *) aviso "Digest distinto o ausente: '$d'" ;;
  esac
  LC_ALL=C timedatectl 2>/dev/null | grep -q 'synchronized: yes' && ok "Reloj sincronizado" || mal "Reloj sin sincronizar"
}

validar_balanceador() {
  titulo "Balanceador (HAProxy)"
  sudo haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1 && ok "haproxy.cfg válido (haproxy -c)" || mal "haproxy.cfg inválido"
  sudo grep -q 'option httpchk' /etc/haproxy/haproxy.cfg && sudo grep -q 'http-check expect status 200' /etc/haproxy/haproxy.cfg \
    && ok "Chequeo de salud de capa 7 declarado" || mal "Falta el chequeo de salud de capa 7"

  estado=$(echo 'show stat' | sudo socat stdio /run/haproxy/admin.sock 2>/dev/null | cut -d, -f2,18,37,38)
  for s in srv-1 srv-2; do
    l=$(printf '%s\n' "$estado" | grep "^$s,")
    [ "$l" = "$s,UP,L7OK,200" ] && ok "$l" || mal "$s: ${l:-sin datos}"
  done

  titulo "HTTP, TLS y distribución"
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1/)
  [ "$c" = 302 ] && ok "HTTP redirige a HTTPS (302)" || mal "HTTP devuelve $c (esperado 302)"
  curl -skI --max-time 5 --http2 -H "Host: $HOST_SITIO" https://127.0.0.1/ | head -1 | grep -q 'HTTP/2 200' \
    && ok "HTTPS con HTTP/2 responde 200" || mal "HTTPS sin HTTP/2 o sin 200"
  cert=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$HOST_SITIO" 2>/dev/null | openssl x509 2>/dev/null)
  printf '%s\n' "$cert" | openssl x509 -noout -ext subjectAltName 2>/dev/null | grep -q "DNS:$HOST_SITIO" \
    && ok "Certificado con SAN para $HOST_SITIO" || mal "Certificado sin SAN para $HOST_SITIO"
  printf '%s\n' "$cert" | openssl x509 -noout -checkend 86400 >/dev/null 2>&1 \
    && ok "Certificado vigente por más de 24 horas" || mal "Certificado vencido o por vencer"
  pem=$(sudo grep -oE 'ssl crt +"?[^" ]+' /etc/haproxy/haproxy.cfg | head -1 | sed -E 's/ssl crt +"?//')
  if [ -n "$pem" ] && sudo test -r "$pem"; then
    fs=$(printf '%s\n' "$cert" | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
    fd=$(sudo openssl x509 -in "$pem" -noout -fingerprint -sha256 2>/dev/null)
    [ -n "$fs" ] && [ "$fs" = "$fd" ] \
      && ok "El certificado servido coincide con el de disco ($pem)" \
      || mal "El certificado servido NO coincide con el de disco ($pem): una recarga lo cambiaría"
    sudo openssl x509 -in "$pem" -noout -ext subjectAltName 2>/dev/null | grep -q "DNS:$HOST_SITIO" \
      && ok "El certificado en disco tiene SAN" || mal "El certificado en disco no tiene SAN"
  else
    aviso "No se pudo leer desde haproxy.cfg la ruta del certificado"
  fi
  n=$(for i in $(seq 1 10); do curl -skI --max-time 5 "https://$HOST_SITIO" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-backend"{print $2}'; done | sort -u | wc -l)
  [ "$n" -eq 2 ] && ok "10 peticiones respondidas por los dos nodos" || mal "10 peticiones respondidas por $n nodo(s) distinto(s)"

  titulo "Administración"
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://10.33.195.180:32500/)
  [ "$c" = 401 ] && ok "El panel de estadísticas exige credenciales (401)" || mal "El panel de estadísticas devuelve $c (esperado 401)"
}

case "${1:-}" in
  nodo) validar_nodo ;;
  balanceador) validar_balanceador ;;
  *) echo "Uso: $0 nodo | balanceador"; exit 2 ;;
esac

printf '\nResultado: %s comprobación(es) fallida(s)\n' "$FALLAS"
[ "$FALLAS" -eq 0 ]
