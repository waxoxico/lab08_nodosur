---
title: "Nodo Sur · Runbook de operación"
subtitle: "Procedimientos de diagnóstico, respuesta y reversión · Entrega 4"
date: "Noviembre 2026"
---

# 1. Cómo usar este documento

Cada procedimiento tiene la misma estructura: **síntoma**, **evidencia a
recoger**, **diagnóstico**, **acción**, **validación** y **reversión**.

La regla de oro: **recoger la evidencia antes de actuar**. Un servicio reiniciado
sin mirar los registros destruye la información que explica por qué falló.

## Responsables y escalamiento

| Componente | Máquina | Primer responsable | Si no responde |
|---|---|---|---|
| Balanceador, DNS, monitoreo | VM1 · `proxy1` | **Xavi** | Matías |
| Nodo web 1 | VM2 · `web1` | **Matías** | Yovani |
| Nodo web 2 | VM3 · `web2` | **Yovani** | Matías |
| Base de datos, NFS, respaldos | VM4 · `db1` | **Aníbal** | Xavi |

Los dos nodos web son idénticos, de modo que quien opera uno puede operar el
otro. VM1 y VM4 se cubren entre los integrantes con más contexto de
infraestructura.

**Criterio de escalamiento.** Si el primer responsable no responde en 15 minutos
ante una alerta crítica, actúa el segundo. Toda intervención se anota en la
bitácora con hora UTC.

## Niveles de severidad

| Severidad | Qué significa | Respuesta |
|---|---|---|
| **Crítica** | El servicio está caído o a un paso de estarlo | Atención inmediata |
| **Aviso** | Degradación o riesgo futuro | Atender en horario de trabajo |

## Datos de la plataforma

| Máquina | Administración | Red interna | Rol |
|---|---|---|---|
| VM1 `proxy1` | 10.33.195.180 | 10.33.199.65 | HAProxy, BIND, Prometheus, Grafana, Alertmanager |
| VM2 `web1` | 10.33.195.234 | 10.33.199.66 | WordPress en contenedor |
| VM3 `web2` | 10.33.195.170 | 10.33.199.67 | WordPress en contenedor |
| VM4 `db1` | 10.33.195.175 | 10.33.199.68 | MariaDB, NFS, respaldos |

Todas en **UTC**. El sitio muestra hora de Chile.

# 2. Comprobación rápida del estado

Antes de cualquier diagnóstico, estos cinco comandos dan el panorama.

```
# Desde VM1: estado de los backends
curl -s -u admin:CLAVE "http://10.33.195.180:32500/;csv" | grep aplicaciones_web | cut -d, -f1,2,18

# El sitio responde de extremo a extremo
curl -sIL https://www.lab08.nodosur.cl | grep -iE "^HTTP|^server"

# Todos los objetivos de Prometheus
curl -s localhost:9090/api/v1/targets | python3 -c "
import json,sys
for t in json.load(sys.stdin)['data']['activeTargets']:
    print(f\"  {t['labels'].get('job','?'):16} {t['labels'].get('maquina',''):8} {t['health']}\")"

# Alertas activas
curl -s localhost:9093/api/v2/alerts | python3 -m json.tool | grep -E '"alertname"|"state"'

# Último respaldo (en VM4)
sudo tail -3 /var/log/respaldo-nodosur.log
```

**Lo que debe verse en estado normal:** `srv-1` y `srv-2` en `UP`, el sitio
devolviendo `200` con `Server: Apache`, los ocho objetivos en `up`, ninguna
alerta activa y el último respaldo con su línea de cierre.

\newpage

# 3. Alerta: BackendCaido

**Severidad:** crítica · **Responsable:** según la máquina afectada

## Síntoma

Correo `[FIRING:1] BackendCaido`. Un nodo web no pasa el chequeo de salud. **El
sitio sigue operando** con el nodo restante.

## Evidencia a recoger

```
# En VM1
date -u +%FT%TZ
curl -s -u admin:CLAVE "http://10.33.195.180:32500/;csv" | grep aplicaciones_web | cut -d, -f1,2,18,37
sudo grep "$(date -u +%d/%b/%Y)" /var/log/haproxy.log | grep -iE "DOWN|UP" | tail -10
```

La columna 37 da el motivo del chequeo fallido, que orienta el diagnóstico:

| Motivo | Qué significa |
|---|---|
| `L4CON` | Conexión rechazada: el contenedor está detenido |
| `L4TOUT` | Sin respuesta: la máquina puede estar caída o el firewall bloquea |
| `L7STS` | Responde, pero con código de error: falla la aplicación |

## Diagnóstico

En el nodo afectado:

```
cd /srv/tas/wordpress-compose
sudo docker compose ps
sudo docker compose logs --tail 30
curl -sI -H "Host: www.lab08.nodosur.cl" http://127.0.0.1/health.php
```

| Si | Causa probable |
|---|---|
| El contenedor no aparece o está detenido | No arrancó tras un reinicio |
| Está `Up` pero no `healthy` | Falla el chequeo interno: revisar el NFS |
| `health.php` no responde | Apache del contenedor caído |
| `health.php` responde pero el proxy lo marca `DOWN` | Firewall: la regla de `DOCKER-USER` |

## Acción

```
cd /srv/tas/wordpress-compose && sudo docker compose up -d
```

Si el contenedor arranca y vuelve a caer, revisar el montaje NFS:

```
findmnt /var/www/html/wp-content
sudo mount -a
```

Si la regla de firewall falta:

```
sudo systemctl restart docker-user-rules.service
sudo iptables -L DOCKER-USER -n --line-numbers
```

## Validación

```
# En el nodo
sudo docker compose ps          # Up (healthy)
# En VM1, pasados 10 segundos
curl -s -u admin:CLAVE "http://10.33.195.180:32500/;csv" | grep srv-X | cut -d, -f2,18
```

Debe volver a `UP`, y debe llegar el correo `[RESOLVED]`.

## Reversión

Si el contenedor no levanta, el Apache nativo sigue instalado como respaldo:

```
cd /srv/tas/wordpress-compose && sudo docker compose down
sudo systemctl enable --now apache2
```

Tiempo de retiro y reintegración medido: **4 a 6 segundos** para detectar,
**3 segundos** para reintegrar.

\newpage

# 4. Alerta: TodosLosBackendsCaidos

**Severidad:** crítica · **Responsable:** Xavi · **Escalamiento:** Matías

## Síntoma

El sitio **no responde**. HAProxy no tiene ningún backend disponible.

## Evidencia a recoger

```
date -u +%FT%TZ
curl -sI https://www.lab08.nodosur.cl | head -1
curl -s -u admin:CLAVE "http://10.33.195.180:32500/;csv" | grep aplicaciones_web | cut -d, -f1,2,18,37
sudo tail -40 /var/log/haproxy.log
```

## Diagnóstico

Que caigan los **dos** nodos a la vez rara vez es casualidad. Lo probable es una
causa común:

| Candidato | Cómo se comprueba |
|---|---|
| **VM4 caída** | `ping 10.33.199.68` y `systemctl is-active mariadb` |
| **El NFS no responde** | `findmnt /var/www/html/wp-content` en los nodos |
| **MariaDB caída** | Los dos nodos darían `L7STS 500` |
| Red interna | `ping` entre las máquinas |

**VM4 es punto único de falla**: aloja la base y el contenido compartido. Su
caída deja los dos nodos sin servicio.

## Acción

Si el origen es VM4:

```
sudo systemctl start mariadb nfs-kernel-server
sudo systemctl is-active mariadb nfs-kernel-server
```

En los nodos, remontar el NFS si quedó colgado:

```
sudo umount -l /var/www/html/wp-content
sudo mount -a
findmnt /var/www/html/wp-content
```

## Validación

```
curl -sIL https://www.lab08.nodosur.cl | grep -iE "^HTTP|^server"
```

Un `200` con `Server: Apache`, y los dos backends en `UP`.

## Reversión

Si MariaDB no arranca por corrupción, el procedimiento de restauración está en
`informe-restauracion.md`. **RTO medido: 32 segundos** para datos y archivos.

\newpage

# 5. Alerta: ErroresServidorAltos

**Severidad:** aviso · **Responsable:** el del nodo afectado

## Síntoma

Tasa de respuestas 5xx por encima del umbral. **Los backends figuran `UP`**: el
servicio responde, pero con error.

## Evidencia a recoger

```
sudo grep " 5[0-9][0-9] " /var/log/haproxy.log | tail -20
# En el nodo afectado
sudo tail -30 /var/www/html/wp-content/debug.log
sudo docker compose logs --tail 40
```

## Diagnóstico

Un 5xx con el backend arriba suele venir de la aplicación:

| Causa | Cómo se confirma |
|---|---|
| Sin conexión a la base | `debug.log` con `mysqli_real_connect` |
| `wp-config.php` alterado | `sudo grep -E "DB_NAME|DB_USER|DB_HOST"` |
| Base caída o saturada | Panel de Grafana, sección MariaDB |
| Permisos del NFS | `ls -la /var/www/html/wp-content` |

## Acción

Según la causa. Si es la base, desde VM4:

```
sudo systemctl is-active mariadb
sudo mysql -e "SHOW PROCESSLIST;" | head -20
```

Si hay consultas bloqueadas, identificar y terminar la ofensora antes de
reiniciar el servicio.

## Validación

```
curl -sI https://www.lab08.nodosur.cl | head -1
```

Y que la tasa de 5xx baje en el panel durante cinco minutos.

\newpage

# 6. Alerta: MaquinaSinResponder

**Severidad:** crítica · **Responsable:** el de la máquina indicada

## Síntoma

Prometheus lleva dos minutos sin obtener métricas de una máquina. **Puede estar
apagada, sin red, o solo con el exportador caído.**

## Evidencia a recoger

```
date -u +%FT%TZ
ping -c 3 IP_INTERNA
nc -zv -w3 IP_INTERNA 22
nc -zv -w3 IP_INTERNA 9100
```

| Resultado | Significa |
|---|---|
| Nada responde | Máquina apagada o sin red |
| `ping` sí, SSH no | Sistema vivo, `sshd` caído |
| SSH sí, 9100 no | Solo el exportador. **El servicio real puede estar bien** |

## Acción

Si solo falla el exportador:

```
sudo systemctl restart prometheus-node-exporter
sudo systemctl is-active prometheus-node-exporter
```

Si la máquina no responde, acceder por la **consola de Proxmox**, que no depende
de la red, y revisar desde ahí.

## Validación

```
# En VM1
curl -s localhost:9090/api/v1/targets | grep -A2 MAQUINA | grep health
```

## Nota

Esta alerta cubre un hueco: **VM4 no es backend**, así que su caída no dispara
ninguna alerta de HAProxy. Sin esta regla, podría pasar inadvertida hasta que
fallara el sitio.

\newpage

# 7. Alerta: DiscoCasiLleno

**Severidad:** aviso · **Responsable:** el de la máquina

## Síntoma

El sistema de archivos raíz supera el 85 % durante diez minutos.

## Evidencia a recoger

```
df -h /
sudo du -sh /var/log /var/backups /srv 2>/dev/null | sort -h
sudo du -sh /var/log/* 2>/dev/null | sort -h | tail -5
```

## Diagnóstico

| Candidato | Dónde mirar |
|---|---|
| Respaldos acumulados | `/var/backups/nodosur` en VM4 y `~/respaldos` en VM1 |
| Registros sin rotar | `/var/log/haproxy.log` en VM1 |
| Imágenes de Docker | `sudo docker system df` |
| Contenido del sitio | `/srv/nfs/wp-content` en VM4 |

## Acción

**Nunca borrar a ciegas.** Primero identificar, después actuar.

```
# Forzar rotación de registros
sudo logrotate -f /etc/logrotate.d/haproxy

# Limpiar imágenes de Docker sin uso
sudo docker image prune -a

# Comprobar la rotación de respaldos
sudo ls -lt /var/backups/nodosur/ | head
```

La rotación de respaldos está automatizada a 30 días. Si hay más carpetas de las
esperadas, el `find` del script no está limpiando.

## Validación

```
df -h /
```

Por debajo del 85 %, y la alerta debe resolverse sola.

## Precaución

**Antes de borrar cualquier registro**, comprobar que las evidencias de pruebas y
ensayos están respaldadas. En VM1, `/var/log/haproxy.log` contiene las líneas de
tiempo de las pruebas de falla.

\newpage

# 8. Alerta: ExportadorSinDatos

**Severidad:** aviso · **Responsable:** Xavi

## Síntoma

Prometheus no recolecta métricas de HAProxy. **El monitoreo está ciego**, aunque
el servicio puede seguir operando con normalidad.

## Evidencia a recoger

```
curl -s http://10.33.195.180:8405/metrics | head -3
sudo systemctl is-active haproxy
sudo docker logs prometheus --tail 20
```

## Diagnóstico

| Causa | Cómo se comprueba |
|---|---|
| HAProxy caído | `systemctl is-active haproxy` |
| El `frontend prometheus` no está | `grep -A3 "frontend prometheus" /etc/haproxy/haproxy.cfg` |
| Firewall | `sudo ufw status \| grep 8405` |
| Prometheus caído | `sudo docker ps \| grep prometheus` |

**La causa más frecuente es el firewall.** Los contenedores llegan desde
`172.16.0.0/12`, y si falta la regla el síntoma es un timeout silencioso.

## Acción

```
sudo ufw allow from 172.16.0.0/12 to any port 8405 proto tcp
sudo docker restart prometheus
```

## Validación

```
curl -s localhost:9090/api/v1/targets | grep -A2 haproxy-native | grep health
```

\newpage

# 9. Procedimiento: restaurar desde respaldo

**Responsable:** Aníbal · **Escalamiento:** Xavi

## Cuándo

Pérdida o corrupción de datos, o necesidad de recuperar un estado anterior.

## Procedimiento

El detalle completo, con tiempos medidos, está en `informe-restauracion.md`.
Resumen operativo:

```
# 1. Elegir el respaldo
sudo ls -lt /var/backups/nodosur/

SELLO=<identificador>
DIR=/var/backups/nodosur/$SELLO

# 2. Verificar integridad ANTES de restaurar
sudo bash -c "cd $DIR && sha256sum -c SHA256SUMS"

# 3. Restaurar en ambiente de prueba, NO en produccion
sudo mysql -e "DROP DATABASE IF EXISTS restore_test; CREATE DATABASE restore_test;"
sudo zcat $DIR/db-lab08_db.sql.gz \
  | sed 's/`lab08_db`/`restore_test`/g; s/^USE .*/USE `restore_test`;/' \
  | sudo mysql restore_test

# 4. Verificar funcionalmente
sudo mysql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='restore_test';"
```

**Debe devolver 98 tablas.** Un número distinto significa que la restauración
falló, aunque los comandos hayan terminado sin error.

## Precaución

**Restaurar siempre primero en `restore_test`.** Solo tras validar el contenido
se considera restaurar sobre la base productiva, y esa decisión la toma el
responsable con el segundo informado.

## Limpieza

```
sudo mysql -e "DROP DATABASE IF EXISTS restore_test;"
sudo rm -rf /tmp/restore_files
```

\newpage

# 10. Procedimiento: cambios de configuración

Aplica a cualquier cambio en los cuatro servicios.

## Las tres reglas

| Regla | Comando |
|---|---|
| **Copia antes de editar** | `sudo cp -a ARCHIVO ARCHIVO.bak` |
| **Validar antes de aplicar** | Encadenar con `&&` |
| **Un cambio a la vez** | Y comprobar entre uno y otro |

## Validar y aplicar por servicio

| Servicio | Comando |
|---|---|
| HAProxy | `sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy` |
| BIND | `sudo named-checkconf -z && sudo systemctl reload named` |
| Apache | `sudo apache2ctl configtest && sudo systemctl reload apache2` |
| Compose | `sudo docker compose config --quiet && sudo docker compose up -d` |
| Prometheus | `curl -s -XPOST localhost:9090/-/reload` |
| Netplan | `sudo netplan try` |

**`netplan try` revierte solo a los 120 segundos** si se pierde la conexión. Es
la red de seguridad al tocar la red por SSH.

## Qué requiere reinicio y qué no

| Cambio | Acción |
|---|---|
| Zona de BIND, VirtualHost, configuración de HAProxy | `reload` |
| Puertos, módulos nuevos, extensiones de PHP | `restart` |
| `wp-config.php` o datos de la base | Nada |

## Si algo sale mal

Toda configuración tiene su copia `.bak`. Los procedimientos de reversión
completos están en la bitácora de la Entrega 3.

\newpage

# 11. Procedimiento: degradación controlada

Para ensayos y demostraciones. **No ejecutar en horario de uso real.**

## Retirar un backend

```
# En el nodo, anotando la hora
cd /srv/tas/wordpress-compose && date -u +%FT%TZ && sudo docker compose stop
```

Qué debe ocurrir:

| Tiempo | Evento |
|---|---|
| 4 a 6 s | HAProxy marca el backend `DOWN` |
| ~1 min | La alerta entra en `firing` |
| +30 s | Llega el correo `[FIRING]` |

Durante toda la degradación, **el sitio sigue respondiendo** con el nodo
restante.

## Recuperar

```
cd /srv/tas/wordpress-compose && date -u +%FT%TZ && sudo docker compose start
```

Debe llegar un correo `[RESOLVED]` en un par de minutos.

## Medición de referencia

Ensayo del 20/11: detección en **73 segundos**, frente al objetivo de 5 minutos.

## Qué NO hacer en una demostración

- **No reiniciar VM1**: se cae el balanceador, el DNS y todo el monitoreo.
- **No apagar VM4**: deja los dos nodos sin base de datos ni archivos.
- **No ejecutar `docker compose down -v`**: el `-v` borra los volúmenes.
- **No tocar la base productiva** para ensayos de restauración.

\newpage

# 12. Límites conocidos y riesgo residual

Declararlos es parte del criterio, y evita presentar como robusto lo que no lo es.

| Límite | Efecto | Mitigación posible |
|---|---|---|
| **VM4 es punto único de falla** | Su caída deja el sitio sin base ni archivos | Réplica de MariaDB, almacenamiento redundante |
| **VM1 es punto único de falla** | Sin balanceador no hay entrada; sin DNS no resuelve el nombre | Segundo proxy con IP virtual |
| **Las cuatro VMs comparten host de Proxmox** | Un fallo del host las derriba todas | Distribuir en hosts distintos |
| **El respaldo se replica dentro del mismo host** | Protege de perder una VM, no el host | Destino fuera del sitio |
| **Montaje NFS `hard`** | Si VM4 no responde, los procesos esperan en vez de fallar rápido | Evaluar `soft` con tiempo de espera |
| **RPO de 24 h** | En campaña se perderían pedidos | Subir frecuencia o activar `binlog` |
| **Detección de 4 a 6 s** | Algunas peticiones reciben error antes del retiro | Intervalo de chequeo más corto |

## Distinción conceptual

El proyecto pide diferenciarlos, y conviene no confundirlos:

| Concepto | Qué tiene Nodo Sur |
|---|---|
| **Balanceo de carga** | Sí: HAProxy reparte entre dos nodos |
| **Tolerancia a falla** | Sí, en la capa web: un nodo puede caer |
| **Alta disponibilidad** | **No**: el balanceador, la base, el NFS y el DNS son únicos |

# 13. Registro de intervenciones

Toda acción sobre la plataforma se anota con:

| Campo | Contenido |
|---|---|
| Hora UTC | De inicio y de fin |
| Quién | El integrante que interviene |
| Síntoma | Lo observado, no lo supuesto |
| Evidencia | Comandos ejecutados y su salida |
| Acción | Lo que realmente resolvió |
| Validación | Cómo se comprobó |

**Los incidentes resueltos se documentan igual que los fallidos.** Un intento que
no funcionó, con su causa, vale más que el silencio: evita que otro repita el
mismo camino.

\newpage

# 14. Actualización del 22/11/2026 (complemento)

Las secciones 14 a 21 **se agregan** a este runbook. Las anteriores se conservan
tal cual; donde difieran, mandan estas, que describen la implementación
verificada el 22/11.

| Cambio | Efecto en la operación |
|---|---|
| Cuentas nominativas para los segundos responsables | El escalamiento de la sección 1 se puede ejecutar: cada reemplazo entra con **su propio usuario** (§19) |
| Cuenta de servicio `respaldo` en VM1, VM2 y VM3 | El respaldo ya no depende de la cuenta de Xavi |
| 10 reglas de alerta | Nueva `RespaldoIncompleto` (§16) |
| Retención de logs con `limpieza-logs-nodosur` | La sección 7 debe revisar ese timer, no logrotate (§20) |
| Claves en `/srv/monitoring/.env` | Los comandos con `admin:CLAVE` toman la clave del `.env`: `grep '^HAPROXY_STATS_PASS=' /srv/monitoring/.env` y usar el valor después del `=` |

**Datos de la plataforma, corrección:** los hostnames reales son `proxy1`,
`web1`, `web2` y `db1`.

\newpage

# 15. Procedimiento: la portada se cuelga en un nodo, pero el chequeo de salud pasa

**Severidad:** crítica (la mitad de los usuarios ve el sitio colgado) ·
**Responsable:** el del nodo afectado · **Caso real:** web1, 22/11, 00:39–01:52 UTC.

## Síntoma

- Algunos usuarios ven el sitio "cargando" sin fin y otros lo ven bien.
- HAProxy muestra los dos backends en `UP` y **no hay alerta**, porque `health.php` responde.
- En una prueba repetida, las respuestas se alternan entre `200` y sin respuesta.

## Evidencia a recoger (antes de actuar)

```
# En VM1: que nodo atiende y cuanto tarda (4 peticiones)
for i in 1 2 3 4; do curl -sk -m 15 -o /dev/null -D - -w "tiempo=%{time_total}s\n" \
  --resolve www.lab08.nodosur.cl:443:10.33.195.180 https://www.lab08.nodosur.cl/ | grep -iE "^HTTP|^x-backend|^tiempo"; done

# En el nodo sospechoso
uptime                                   # carga alta sin uso de CPU = procesos en estado D
sudo docker top web1 -eo pid,etime,stat,wchan:20,args
sudo cat /proc/PID/stack                 # para cada PID en estado D
sudo ls -l /proc/PID/fd | grep wp-content
sudo dmesg -T | grep -iE "nfs|blocked for" | tail
```

Guardar esa salida en `~/evidencia-e4/` **antes** de reiniciar nada.

## Diagnóstico

| Si se ve | Significa |
|---|---|
| Procesos `apache2` en estado `D` en `iterate_dir` o `vfs_unlink` sobre `wp-content/...` | Una operación NFS colgada bloquea una carpeta que WordPress lee en cada petición |
| `dmesg`: `blocked for more than N seconds` y `nfs_...` | Confirma el bloqueo en el cliente NFS. El inicio del incidente es la hora del aviso menos N segundos |
| `ls` del NFS funciona, pero la portada no | El NFS no está caído: el bloqueo es puntual, en una carpeta o archivo |

**Ojo:** la antigüedad de un proceso de Apache **no** es la duración del
bloqueo, porque Apache reutiliza sus procesos.

## Acción (cambio mínimo)

```
timeout 90 sudo docker restart -t 20 web1; echo "codigo: $?"
```

Mientras tanto, el otro nodo atiende solo. Si el código es `124` o siguen
procesos `D` antiguos en el host, el bloqueo está en el kernel: **reiniciar la
VM** del nodo (vuelve sola en unos 24 s, con el otro nodo atendiendo).

## Validación

```
ps -eo pid,etime,stat,args | awk 'NR==1 || $3 ~ /D/'       # sin procesos D
timeout 10 ls /var/www/html/wp-content/languages; echo $?  # 0
# En VM1: 4 peticiones con 200, alternando web1 y web2
```

## Mejoras pendientes (lección del incidente)

- `health.php` debe tocar el NFS y WordPress, con un tiempo de espera corto.
- Agregar una alerta de latencia o de sesiones acumuladas por servidor en HAProxy.
- Bajar `timeout server` (hoy 10 min) para que una petición colgada termine en 504 y dispare `ErroresServidorAltos`.

\newpage

# 16. Alertas de respaldo

**Responsable:** Aníbal · **Escalamiento:** Xavi

| Alerta | Qué indica | Primer paso |
|---|---|---|
| `RespaldoNoEjecutado` (crítica) | Más de 26 h sin respaldo correcto | `systemctl status respaldo-nodosur.timer respaldo-nodosur.service` y `sudo tail -20 /var/log/respaldo-nodosur.log` en db1 |
| `RespaldoDemasiadoPequeno` (crítica) | El último respaldo pesa menos de 50 MB | Revisar el último conjunto en `/var/backups/nodosur/` y su `sha256sum -c` |
| `RespaldoIncompleto` (aviso) | `respaldo_avisos > 0`: algún componente no se respaldó | `sudo grep AVISO /var/log/respaldo-nodosur.log` |

**Diagnóstico de `AVISO: configuracion de X incompleta o inaccesible`:**

```
# Desde db1, probar la cuenta de servicio contra el nodo X
sudo ssh -o BatchMode=yes respaldo@IP_X 'echo ok'
```

| Resultado | Causa probable |
|---|---|
| `Permission denied` | Cambió `authorized_keys` de `respaldo` en X |
| `Host key verification failed` | Se reinstaló X o cambió su llave de host: **verificar la huella** antes de aceptarla |
| `ok`, pero el `tar` falla | La lista de rutas del script no coincide **exactamente** con `/etc/sudoers.d/respaldo` de X |

**`nota: wp-content cambio durante la lectura`** no es un error: `tar`
devolvió código 1 porque el sitio escribió mientras se respaldaba. La copia es
utilizable.

**Validación:** `sudo systemctl start respaldo-nodosur.service` y revisar que
el log termine en `avisos: 0`. Después, `sha256sum -c` en VM1 como `respaldo`.

\newpage

# 17. Procedimiento: restaurar sobre producción

**Responsable:** Aníbal, con Xavi informado (decisión de dos personas).
**Solo después** de validar el respaldo con la sección 18.

```
SELLO=<identificador validado>; DIR=/var/backups/nodosur/$SELLO
date -u +%FT%TZ                                            # T0
sudo bash -c "cd $DIR && sha256sum -c SHA256SUMS"           # integridad

# 1. Contener: sacar los dos nodos de servicio (los usuarios ven 503, no datos a medias)
#    En web1 y web2:
cd /srv/tas/wordpress-compose && sudo docker compose stop

# 2. Respaldo de seguridad del estado actual, por si hay que volver atras (db1)
sudo bash -c 'mysqldump --single-transaction --databases lab08_db | gzip > /root/lab08_db.antes-restaurar.sql.gz'

# 3. Base de datos (db1)
sudo zcat $DIR/db-lab08_db.sql.gz | sudo mysql

# 4. Archivos (db1, como root; conserva duenos y permisos)
sudo tar -xzf $DIR/archivos-wp-content.tgz -C /srv/nfs

# 5. Reintegrar: en web1 y web2
cd /srv/tas/wordpress-compose && sudo docker compose start
```

**Validación:** portada `200` por HAProxy con `x-backend` web1 y web2; producto
de prueba visible; 98 tablas en `lab08_db`; registrar T1.

**Reversión:** restaurar `/root/lab08_db.antes-restaurar.sql.gz` con el mismo
procedimiento.

\newpage

# 18. Ensayo de restauración funcional (sin tocar producción)

Ejecutado el 22/11: **RTO del servicio de 3 min 50 s**. Detalle en
`informe-restauracion.md` §8.

1. **db1:** restaurar en `restore_test`; crear un usuario temporal
   `restore_test@10.33.199.66` con permisos solo sobre `restore_test`; enviar
   a `respaldo@web1` el `.tgz` de archivos y un `.env` temporal por `scp`.
2. **web1:** extraer en `/tmp/restore_test` y levantar un WordPress temporal en
   `127.0.0.1:8099`, con `WP_HOME` y `WP_SITEURL` sobrescritos.
3. **Validar:** portada `200`; `?rest_route=/wp/v2/product/20`; `wc/v3`
   presente; archivo de marca servido.
4. **Limpiar:** `docker rm -f -v wp-restore-test`; borrar `/tmp/restore_test`
   y los archivos temporales; `DROP USER` y `DROP DATABASE restore_test`.

\newpage

# 19. Escalamiento con cuentas nominativas

| VM | Responsable (cuenta) | Reemplazo (cuenta) |
|---|---|---|
| VM1 proxy1 | Xavi (`xavineta2026`) | Matías (`mgonzalez`) |
| VM2 web1 | Matías (`mgonzalez`) | Yovani (`yovani`) |
| VM3 web2 | Yovani (`yovani`) | Matías (`mgonzalez`) |
| VM4 db1 | Aníbal (`anibal`) | Xavi (`xavineta2026`) |

- **Nadie entra con la cuenta de otro.** Si la VPN falla, se salta desde otra VM, pero con el usuario propio: `ssh mgonzalez@10.33.199.65`.
- Las cuentas de reemplazo se crearon con cambio de contraseña obligatorio en el primer ingreso.
- Revocar un acceso: `sudo usermod -L USUARIO` (bloquea) o `sudo deluser USUARIO sudo` (quita privilegios).

# 20. Retención y consulta de logs

| Tarea | Comando |
|---|---|
| Estado de la retención | `systemctl list-timers limpieza-logs-nodosur.timer` |
| Última ejecución | `sudo grep -a 'limpieza-logs:' /var/log/syslog` |
| Buscar un mensaje de `logger` | Usar `etiqueta:`, no `etiqueta[`: en rsyslog no lleva el PID |
| Reconstruir una secuencia entre máquinas | Cruzar `/var/log/haproxy.log`, `/var/log/nodosur/<maquina>/<fecha>.log` y `/var/log/mail.log`, ordenando por la marca de tiempo UTC (ver `capturas/E4_secuencia_logs.png`) |

# 21. Alerta: CpuAlta

**Severidad:** aviso · **Responsable:** el de la máquina

```
top -b -n1 | head -15
ps -eo pid,etime,pcpu,stat,args --sort=-pcpu | head
```

Si la **carga** es alta pero la **CPU** está baja, no es un problema de CPU:
son procesos en estado `D` esperando I/O. Aplicar la sección 15.
