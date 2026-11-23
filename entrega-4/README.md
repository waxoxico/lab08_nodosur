# Entrega 4 · Observabilidad y continuidad operacional

Nodo Sur · TAS 2026 · Grupo Tas_08

## Qué contiene

| Ruta | Qué es |
|---|---|
| `bitacora-entrega-4.md` | Bitácora completa: qué se hizo, por qué, incidentes y estado por criterio |
| `informe-restauracion.md` | Ensayo de restauración con medición de RPO y RTO |
| `runbook.md` | Manual de operación: procedimientos, responsables y escalamiento |
| `backup/` | Script de respaldo, unidades de `systemd` y regla de `sudo` |
| `monitoreo/` | Compose del stack, Prometheus, reglas de alerta y Alertmanager |
| `logs/` | Configuración de `rsyslog` y política de retención |

Los tres documentos están también en PDF.

## Arquitectura de operación

```
                    ┌──────────────── VM1 proxy1 ────────────────┐
                    │  HAProxy :80 :443 :8405(metricas)          │
  web1, web2, db1   │  Prometheus :9090   Alertmanager :9093     │
   ──logs:5514──>   │  Grafana :3000 (HTTPS)                     │
                    │  Postfix (127.0.0.1 y 172.18.0.1)          │
                    │  /var/log/nodosur/<maquina>/<fecha>.log    │
                    └────────────────────────────────────────────┘
                                      ▲
                        respaldos ────┘
                    VM4 db1: MariaDB + NFS + respaldo diario
```

## Despliegue

### Respaldos, en VM4

```
sudo install -m 750 backup/respaldo-nodosur.sh /usr/local/sbin/
sudo install -m 644 backup/respaldo-nodosur.service /etc/systemd/system/
sudo install -m 644 backup/respaldo-nodosur.timer   /etc/systemd/system/
sudo mkdir -p /var/backups/nodosur && sudo chmod 700 /var/backups/nodosur
sudo systemctl daemon-reload
sudo systemctl enable --now respaldo-nodosur.timer
```

Requiere una llave SSH de `root@db1` hacia `xavineta2026@proxy1`, y en VM1 la
regla de `sudo` de `backup/sudoers.d-respaldo-remoto` en `/etc/sudoers.d/`
(modo 440).

### Monitoreo, en VM1

```
cd /srv/monitoring
cp monitoreo/.env.example .env     # y poner los valores reales
sudo docker compose config --quiet && sudo docker compose up -d
```

Los certificados de Grafana se extraen del PEM de HAProxy:

```
sudo openssl x509 -in /etc/ssl/haproxy/lab08.nodosur.pem -out grafana/certs/grafana.crt
sudo openssl pkey -in /etc/ssl/haproxy/lab08.nodosur.pem -out grafana/certs/grafana.key
sudo chown 472:0 grafana/certs/grafana.*
sudo chmod 640 grafana/certs/grafana.key
```

El `chown` a **472:0** es necesario: Grafana corre con ese uid pero gid 0.

### Registros

En VM1, `logs/10-nodosur-receptor.conf` y `logs/91-nodosur-local.conf` en
`/etc/rsyslog.d/`, más `logs/logrotate-nodosur` en `/etc/logrotate.d/nodosur`.

En VM2, VM3 y VM4, `logs/90-nodosur-emisor.conf` en `/etc/rsyslog.d/`.

```
sudo rsyslogd -N1 && sudo systemctl restart rsyslog
sudo chown syslog:adm /var/log/nodosur   # solo en VM1
```

### Reglas de firewall necesarias

| Máquina | Regla |
|---|---|
| VM1 | `ufw allow from 172.16.0.0/12 to any port 25` |
| VM1 | `ufw allow from 172.16.0.0/12 to any port 8405` |
| VM1 | `ufw allow from 172.16.0.0/12 to any port 9100` |
| VM1 | `ufw allow from 10.33.199.64/29 to any port 5514` |
| VM2, VM3, VM4 | `ufw allow from 10.33.199.65 to any port 9100` |
| VM4 | `ufw allow from 10.33.199.65 to any port 9104` |

Los contenedores alcanzan el host desde `172.16.0.0/12`. Un timeout silencioso
al consultar un exportador casi siempre es una regla que falta.

## Verificación rápida

```
# Objetivos de Prometheus (deben ser 8, todos up)
curl -s localhost:9090/api/v1/targets | python3 -c "
import json,sys
for t in json.load(sys.stdin)['data']['activeTargets']:
    print(f\"  {t['labels'].get('job','?'):16} {t['labels'].get('maquina',''):8} {t['health']}\")"

# Reglas cargadas (9 en 3 grupos)
curl -s localhost:9090/api/v1/rules | grep -oE '"name":"[^"]+"'

# Ultimo respaldo, en VM4
sudo tail -3 /var/log/respaldo-nodosur.log

# Registros centralizados
sudo ls /var/log/nodosur/
```

## Objetivos y resultados medidos

| Indicador | Meta | Medido |
|---|---|---|
| Detección de falla crítica | ≤ 5 min | **73 s** |
| RTO del servicio web | ≤ 60 min | **32 s** |
| RPO general | ≤ 24 h | ≤ 24 h, 0 s de pérdida en el ensayo |
| Retención de respaldos | ≥ 30 días | 30 días, con copia separada |

## Límites conocidos

- VM1 y VM4 son puntos únicos de falla.
- Las cuatro VMs comparten el mismo host de Proxmox; la réplica del respaldo
  protege frente a la pérdida de una VM, no del host.
- El certificado TLS es autofirmado: el dominio solo existe en el DNS privado.
- Ambos receptores de Alertmanager apuntan al mismo buzón, porque el laboratorio
  no tiene más destinatarios. El enrutamiento por responsable está implementado.

Detalle completo en la sección correspondiente del `runbook.md`.

---

# Actualización del 22/11/2026 (complemento)

> Esta sección **se agrega** a lo anterior. Lo escrito arriba se conserva tal
> cual. Donde haya diferencias, **manda esta sección**, que describe la
> implementación verificada el 22/11/2026 tras una auditoría de solo lectura.
> Detalle completo en `bitacora-entrega-4.md` (sección "Sesión de correcciones
> posterior a la auditoría") y en `auditoria-entrega-4.md`.

## Contenido agregado

| Ruta | Qué es |
|---|---|
| `auditoria-entrega-4.md` | Auditoría contra la rúbrica, hallazgos y estado posterior a las correcciones |
| `capturas/` | 12 capturas de evidencia (Grafana antes, durante y después; correo de alerta; secuencia de logs; checksums) |
| `historico-2026-11-20/` | Versiones del 20/11 de los archivos que se reemplazaron. **No se borró nada** |
| `backup/sudoers.d-respaldo.proxy1`, `backup/sudoers.d-respaldo.web` | Regla de sudo de la cuenta de servicio `respaldo` (un solo `tar` con argumentos fijos) |
| `backup/authorized_keys.respaldo` | Llave pública de db1, restringida a su IP y sin terminal |
| `logs/limpieza-logs-nodosur.{sh,service,timer}` | Retención real de 30 días de los logs centralizados (reemplaza a logrotate) |
| `logs/45-nodosur-local.conf` | La antigua `91-nodosur-local.conf`, renumerada para que los eventos de HAProxy lleguen al almacén central |

## Qué cambió respecto de lo descrito arriba

| Antes (20/11) | Ahora (22/11) |
|---|---|
| El respaldo replica a `xavineta2026@proxy1` (cuenta personal) | Replica a la cuenta de servicio **`respaldo@proxy1`**, sin contraseña y con un solo permiso |
| Configuración respaldada: VM4 y parte de VM1 | Configuración de **las 4 VMs** (`config-db1`, `config-proxy1`, `config-web1`, `config-web2`) |
| `rsync --delete` (espejo) | Sin `--delete`; retención de 30 días **independiente** en origen y destino |
| Checksum solo en origen | Checksum verificado **en origen y en destino** |
| 9 reglas de alerta | **10 reglas**: se agregó `RespaldoIncompleto` (métrica `respaldo_avisos`) |
| Retención de logs con logrotate | Script + timer `limpieza-logs-nodosur` (03:30 UTC). Logrotate no borraba nada porque los archivos son por día con nombre único |
| Claves en el `compose.yaml` de VM1 | `/srv/monitoring/.env` (600); claves de HAProxy y Grafana **rotadas** |
| Responsables de respaldo sin cuenta en la VM | Cada VM tiene su responsable y su reemplazo con **cuenta nominativa** |

## Despliegue de la cuenta de servicio `respaldo` (VM1, VM2 y VM3)

```
sudo useradd --system --create-home --home-dir /home/respaldo --shell /bin/bash respaldo
sudo passwd -l respaldo && sudo chmod 700 /home/respaldo
sudo install -d -m 700 -o respaldo -g respaldo /home/respaldo/.ssh
sudo install -m 600 -o respaldo -g respaldo backup/authorized_keys.respaldo /home/respaldo/.ssh/authorized_keys
# VM1: backup/sudoers.d-respaldo.proxy1   VM2 y VM3: backup/sudoers.d-respaldo.web
sudo visudo -cf backup/sudoers.d-respaldo.web && sudo install -m 440 backup/sudoers.d-respaldo.web /etc/sudoers.d/respaldo
sudo -u respaldo mkdir -p /home/respaldo/respaldos     # solo en VM1
```

En db1, registrar las llaves de host de web1 y web2 **verificando la huella**
antes de aceptarlas (`ssh-keyscan` + `ssh-keygen -lf`).

## Despliegue de la retención de logs (VM1)

```
sudo install -m 750 logs/limpieza-logs-nodosur.sh /usr/local/sbin/
sudo install -m 644 logs/limpieza-logs-nodosur.service logs/limpieza-logs-nodosur.timer /etc/systemd/system/
sudo systemd-analyze verify /etc/systemd/system/limpieza-logs-nodosur.*
sudo systemctl daemon-reload && sudo systemctl enable --now limpieza-logs-nodosur.timer
```

## Verificación rápida (versión actual)

```
# 10 reglas en 3 grupos
curl -s localhost:9090/api/v1/rules | grep -oE '"name":"[^"]+"' | grep -vc "disponibilidad\|recursos\|respaldos"
# Ultimo respaldo y sus 6 archivos verificados (db1)
sudo tail -12 /var/log/respaldo-nodosur.log
# Copia separada verificada por la cuenta de servicio (VM1)
sudo -u respaldo bash -c 'cd ~/respaldos/db1/$(ls ~/respaldos/db1 | tail -1) && sha256sum -c SHA256SUMS'
```

## Objetivos y resultados medidos (actualizado)

| Indicador | Meta | Medido el 20/11 | **Medido el 22/11** |
|---|---|---|---|
| Detección de falla crítica (falla → `firing`) | ≤ 5 min | 73 s | **1 min 23 s** |
| **Notificación recibida** (falla → correo entregado) | ≤ 5 min | 7 min 34 s | **1 min 51 s** |
| Continuidad con un backend caído | Sin interrupción | — | **164 de 166 peticiones (98,8 %)** |
| RTO de **extracción** de datos | — | 32 s | 6 s (base) |
| **RTO del servicio** (CMS funcionando sobre lo restaurado) | ≤ 60 min | No medido | **3 min 50 s** |
| RPO | ≤ 24 h | ≤ 24 h | ≤ 24 h (timer diario, ejecución automática verificada el 21/11 03:04) |
| Retención de respaldos | ≥ 30 días | 30 días | 30 días en origen **y** en destino, de forma independiente |

## Límites conocidos (agregados)

- **Incidente real del 22/11 (00:39–01:52 UTC):** una operación NFS colgada en web1 dejó la portada sin responder en ese nodo durante unos 73 minutos sin que ninguna alerta lo detectara, porque `health.php` no carga WordPress ni toca el NFS. Ver la bitácora y `runbook.md` §15.
- Los eventos de HAProxy solo llegan al almacén central después de renombrar `91-` a `45-nodosur-local.conf` (ver bitácora).
- El SSH mantiene la autenticación por contraseña **por criterio del docente**, mitigada con UFW (solo la VPN y la red universitaria).
- En db1 siguen servicios de prácticas de clase ajenos a Nodo Sur, bloqueados por UFW (declarados como riesgo residual).
