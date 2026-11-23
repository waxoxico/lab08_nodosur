---
title: "Nodo Sur · Entrega 4 — Bitácora"
subtitle: "Observabilidad y continuidad operacional"
date: "Noviembre 2026"
---

# Contexto

La Entrega 4 pesa el 25 % de la nota del proyecto. Su propósito, según el
enunciado, es *"pasar de una plataforma funcionando a una plataforma que puede
ser operada, alertada y recuperada"*.

A diferencia de lo que el equipo supuso al principio, **no es una entrega de
monitorización**: el monitoreo son 30 de los 100 puntos, y backup más
restauración suman 35.

## Los siete criterios

| # | Criterio | Peso |
|---|---|---|
| 1 | Cobertura de monitorización | 15 |
| 2 | Alertas y escalamiento | 15 |
| 3 | Logs, tiempo y trazabilidad | 10 |
| 4 | Backup y retención | 15 |
| 5 | Restauración y medición RPO/RTO | 20 |
| 6 | Correo/relay y automatización | 10 |
| 7 | Runbook y demostración operativa | 15 |

La rúbrica repite la advertencia de las entregas anteriores: *"La evidencia debe
verificarse en la implementación, no solo en capturas."*

## Objetivos contra los que se mide

Vienen de la sección 3 del enunciado del proyecto. Son las metas con las que hay
que comparar los resultados medidos:

| Indicador | Meta | Condición |
|---|---|---|
| Disponibilidad mensual | ≥ 99,5 % | Identificar qué sigue siendo punto único de falla |
| Detección de falla crítica | ≤ 5 min | Alerta verificable, no observación manual |
| RTO del servicio web | ≤ 60 min | Medido en ejercicio controlado |
| RPO general | ≤ 24 h | Proponer mejora para datos transaccionales |
| Retención de respaldos | ≥ 30 días | Con rotación y al menos una copia separada |
| Administración remota | Solo canales seguros | Accesos nominativos y revocables |

## Las seis evidencias mínimas

| Evidencia | Estado |
|---|---|
| Panel con métricas antes, durante y después de una degradación | Pendiente |
| Alerta recibida y vinculada con la evidencia de la causa | **Hecho** |
| Logs que permitan reconstruir una secuencia de eventos | **Hecho** |
| Inventario de respaldos, retención y verificación por checksum | **Hecho** |
| Datos identificables creados antes del backup y comprobados tras restaurar | **Hecho** |
| Registro de RPO y RTO real, comparación con objetivos y mejora propuesta | **Hecho** |

---

# Punto de partida

Lo que quedó operativo al cerrar la Entrega 3 y sirve de base:

| Pieza | Dónde | Qué aporta a esta entrega |
|---|---|---|
| Chequeo de salud de capa 7 en HAProxy | VM1 | Retira y reintegra nodos según salud real |
| Panel de estadísticas de HAProxy | `10.33.195.180:32500` | Fuente de métricas del proxy |
| `/var/log/haproxy.log` | VM1 | Cada petición con su backend y su código |
| `health.php` | VM2 y VM3 | Recorre la pila completa, incluido el intérprete |
| Tarea programada de aviso | VM1, cada minuto | Avisa por `wall`. **No cuenta como alerta**: no sale de la máquina |
| Relojes en UTC y sincronizados | Las cuatro VMs | Base para la correlación de logs |
| `validar.sh` | VM1, VM2, VM3 | Comprobación de estado de solo lectura |

---

# Monitorización

## Arquitectura implantada

El stack vive en **VM1 (`proxy1`)**, en `/srv/monitoring/`, desplegado con Docker
Compose:

```
HAProxy (systemd, proxy1)
 ├── :32500  página de stats (CSV, con auth) → haproxy-exporter (contenedor, :9101)
 └── :8405   exportador Prometheus integrado ──────────┐
                                                        ▼
                             Prometheus (contenedor, 127.0.0.1:9090)
                                                        ▼
                             Grafana (contenedor, 10.33.195.180:3000)
```

El dashboard en uso consume el **exportador integrado** (`:8405`). El exportador
antiguo sigue corriendo pero ningún panel lo usa.

## Incidentes resueltos durante la puesta en marcha

Sesión del 16/11. El dashboard mostraba "No data" por una cadena de cinco fallas
independientes:

| # | Problema | Causa | Solución |
|---|---|---|---|
| 1 | Sin acceso a Grafana | Contraseña olvidada, Grafana en contenedor | `grafana cli admin reset-admin-password` |
| 2 | Backends en `DOWN` (`L4TOUT`) | Contenedores de WordPress detenidos tras un reinicio, sin política de reinicio | `docker start` y `docker update --restart unless-stopped` |
| 3 | Exportador con `HTTP 401` | El `compose.yaml` usaba `admin:[clave omitida]`; HAProxy exige `admin:[otra clave omitida]` | Corregir el `scrape-uri` |
| 4 | Los cambios del compose no se aplicaban | Comilla suelta en la primera línea (`'services:`) | `sed -i "1s/^'//"` |
| 5 | Variable `Host` vacía con métricas presentes | El dashboard 12693 requiere el exportador integrado (`haproxy_process_nbproc`) | Añadir `frontend prometheus` en `:8405` y el job `haproxy-native` |
| 6 | Target `:8405` en `DOWN` | UFW sin regla para la red de Docker | `ufw allow from 172.16.0.0/12 to any port 8405` |

**Lecciones registradas.** Un `401` indica que la red funciona y fallan las
credenciales. Un error de YAML puede venir de muchas líneas antes de la que
reporta. Si algo funciona desde el host pero no desde un contenedor, sospechar
del firewall: los contenedores llegan desde `172.16.0.0/12`.

## Lo que falta para la cobertura exigida

El criterio pide *"proxy, backends, DB y hosts"*. Hoy solo se observa el proxy.

| Falta | Con qué se resuelve | Qué aporta |
|---|---|---|
| CPU, memoria, disco, carga y red de las cuatro VMs | `node_exporter` | La saturación y capacidad que pide el criterio |
| Estado de los contenedores | `cAdvisor` | Salud de los nodos web |
| MariaDB en VM4 | `mysqld_exporter` | Conexiones, consultas lentas, errores |
| Salud de los respaldos | Métrica propia desde el script | El enunciado la pide explícitamente |

---

# Backup y retención

## Antecedente: la tarea de respaldo de la Entrega 2 quedó obsoleta

El repositorio conserva en `configs/crontab-root.txt` la tarea programada que se
implantó en septiembre:

```
0  2 * * * mysqldump --single-transaction --routines --triggers wordpress > /var/backups/wordpress/wordpress-$(date +\%Y\%m\%d).sql
30 2 * * * rsync -a --delete /var/www/html/wp-content/ /var/backups/wordpress/wp-content/
```

**Esa tarea dejó de ser válida al cambiar la arquitectura en la Entrega 3**, por
tres motivos que conviene dejar registrados:

| Problema | Detalle |
|---|---|
| Respalda la base equivocada | Vuelca `wordpress`, la base residual de 12 tablas. El sitio usa **`lab08_db`**, con 98 |
| No hay destino separado | El `rsync` copia dentro de la misma máquina |
| Corre en la máquina equivocada | Se escribió cuando MariaDB vivía en VM2; la base está en VM4 desde la Entrega 3 |

El ensayo de restauración de esa época (`evidencias/ensayo-restauracion.txt`,
10/09, 97 tablas restauradas en la base `restore_test`) corresponde a la
plataforma anterior. Su **formato** sigue siendo válido y se reutiliza como
plantilla para el ensayo de esta entrega, pero **sus datos no describen el
sistema actual** y no deben presentarse como evidencia vigente.

Es un caso de configuración que sobrevive a la arquitectura que la justificaba.
El respaldo descrito a continuación la reemplaza.

## Decisiones de diseño

| Decisión | Motivo |
|---|---|
| El respaldo corre en **VM4** | Concentra los dos activos críticos: la base y el `wp-content` compartido por NFS |
| La copia se replica a **VM1** | El criterio exige destino separado del origen |
| `root` de MariaDB se autentica por el usuario del sistema | **No hay credenciales en el script ni en ningún archivo**, lo que cumple la regla del proyecto |
| Llave `ed25519` sin contraseña de VM4 a VM1 | Única forma de automatizar sin escribir una contraseña en texto plano |
| `systemd timer` en vez de `cron` | `Persistent=true` recupera ejecuciones perdidas, queda registrado en `journalctl` y se deshabilita con `systemctl` |

**Limitación declarada.** VM1 y VM4 comparten el mismo host de Proxmox. La
réplica protege frente a la pérdida de una VM, no frente a la pérdida del host.
Es una copia separada del origen, no una copia fuera del sitio.

**Nota de seguridad.** La llave sin contraseña implica que quien obtenga `root`
en VM4 puede escribir en VM1. Se asume en un laboratorio aislado. La mejora
natural sería restringirla con la opción `command=` en `authorized_keys`.

## Qué se respalda

| Activo | Origen | Tamaño en la primera ejecución |
|---|---|---|
| Base de datos | `lab08_db` en MariaDB | 224 K comprimido |
| Archivos del sitio | `/srv/nfs/wp-content` | 76 M |
| Configuración de VM4 | `/etc/mysql`, `/etc/exports`, `/etc/netplan`, `/etc/fstab` | 8 K |

La base `wordpress`, de 12 tablas, es un resto de una instalación previa y queda
fuera del respaldo a propósito. El sitio usa `lab08_db`.

## El script

`/usr/local/sbin/respaldo-nodosur.sh`, modo `750`. Destino local
`/var/backups/nodosur`, modo `700`.

Pasos y justificación de cada uno:

| Paso | Qué hace | Por qué |
|---|---|---|
| 1 | `mysqldump --single-transaction --routines --triggers --events` | Volcado coherente **sin bloquear** la base, de modo que el sitio sigue operando. Incluye lo que no son tablas |
| 2 | `tar` de `wp-content` | Los archivos que WordPress no guarda en la base |
| 3 | `tar` de la configuración | El tercer activo que pide el criterio y el que más se olvida |
| 4 | `sha256sum` y `sha256sum -c` | **Verificación de integridad**, exigida por el nivel sobresaliente |
| 5 | `rsync` sobre SSH a VM1 | El **destino separado** |
| 6 | `find -mtime +30 -exec rm -rf` | La **retención** de 30 días del enunciado |

El script usa `set -uo pipefail` y una función `fallo()` que registra y aborta.
Esto evita el escenario que la rúbrica penaliza expresamente: *"presenta solo el
mensaje de backup exitoso"* sobre una carpeta vacía.

Cada ejecución queda en `/var/log/respaldo-nodosur.log` con marcas de tiempo en
UTC e ISO 8601.

## Automatización

`/etc/systemd/system/respaldo-nodosur.service` (tipo `oneshot`, tras
`mariadb.service`) y `respaldo-nodosur.timer`:

```
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=300
```

Habilitado con `systemctl enable --now`. La verificación con
`systemctl list-timers` confirmó la próxima ejecución programada.

## Primera ejecución verificada

20/11/2026, identificador `20261120-221713`. Duración: **78 segundos**.

```
22:17:13Z === inicio 20261120-221713 ===
22:17:13Z base de datos: 224K
22:18:28Z archivos: 76M
22:18:28Z configuracion: 8.0K
22:18:29Z checksums verificados: 3 archivos
22:18:30Z replicado a 10.33.199.65:respaldos/db1
22:18:30Z rotacion aplicada (retencion 30 dias)
22:18:31Z === fin 20261120-221713 ===
```

Comprobación en el destino separado: los tres archivos presentes en VM1 con el
archivo `SHA256SUMS` correspondiente.

---

# Restauración y medición de RPO/RTO

Ensayo del 20/11/2026 en VM4. Detalle completo en `informe-restauracion.md`.

## Diseño del ensayo

Se restauró **sin tocar el ambiente productivo**: la base se dirigió a un
esquema paralelo (`restore_test`) y los archivos a un directorio temporal. El
criterio exige expresamente que la restauración *"no modifique innecesariamente
el ambiente productivo"*.

Antes de respaldar se crearon dos marcas identificables:

| Marca | Valor |
|---|---|
| Entrada en la base | ID 20, `post_date_gmt` = `2026-11-20 22:37:01` UTC |
| Archivo en el NFS | `marca-restauracion.txt`, con sello `22:37:36Z` |

## Resultados

| Fase | Duración |
|---|---|
| Restauración de la base (98 tablas) | 8 s |
| Restauración de archivos (332 MB) | 24 s |
| **RTO medido** | **32 s** |

| Objetivo | Meta | Medido | |
|---|---|---|---|
| RPO | ≤ 24 h | 0 s de pérdida en el ensayo; ≤ 24 h en operación | Cumple |
| RTO | ≤ 60 min | 32 s | Cumple con holgura |

Verificación de integridad previa: los tres archivos del respaldo pasaron
`sha256sum -c` con `OK`.

## Incidente registrado

El primer intento **falló en silencio**. El `zcat` se ejecutó sin privilegios
sobre `/var/backups/nodosur`, que es de `root` con modo `700`. El proceso
terminó sin error visible y la base quedó creada pero **vacía**.

Se detectó porque la verificación devolvió **0 tablas** en lugar de 98.

Es la justificación de por qué el ensayo comprueba funcionamiento y no solo el
código de salida de los comandos. Un procedimiento que se conformara con que el
comando terminó habría documentado una restauración inexistente.

## Hallazgo: zona horaria de WordPress

El sitio tenía configurada la zona `Europe/Madrid`, heredada de la instalación
inicial, mientras las cuatro máquinas operan en UTC. Producía un desfase de una
hora entre el `post_date` mostrado y las marcas del sistema.

**Corregido a `America/Santiago`.** El criterio aplicado:

> Los servidores operan en UTC para que los logs sean correlacionables entre
> máquinas. La capa de presentación muestra hora local de Chile.

La coherencia queda demostrada en la propia tabla: WordPress almacena siempre
la hora universal en las columnas `_gmt`, y el `post_date_gmt` de la entrada de
prueba coincide exactamente con las marcas del sistema.

Esto responde al criterio de **logs, tiempo y trazabilidad**, que pide hora
consistente.

## Mejoras propuestas

El enunciado pide proponer mejora para datos transaccionales durante campañas,
donde perder hasta 24 h de pedidos sería inaceptable:

| Mejora | Qué resuelve |
|---|---|
| Subir la frecuencia durante campañas, a cada 4 o 6 h | Reduce el RPO a ese intervalo; solo cambia `OnCalendar` |
| Registro binario de MariaDB (`binlog`) | RPO cercano a cero, recuperación hasta el instante previo |
| Copia fuera del host de Proxmox | Protege frente a la pérdida del host, no solo de la VM |
| Ensayo de restauración automatizado y periódico | Detecta respaldos corruptos antes de necesitarlos |

---

# Cobertura de monitorización

## Punto de partida

El stack solo observaba HAProxy. El criterio exige *"proxy, backends, DB y
hosts"* con señales de disponibilidad, latencia, errores, saturación y
capacidad: faltaban tres de los cuatro componentes.

## Qué se añadió

| Exportador | Dónde | Qué aporta |
|---|---|---|
| `prometheus-node-exporter` | Las **cuatro** VMs, puerto 9100 | CPU, memoria, disco, carga y red. La **saturación y capacidad** que faltaban |
| `mysqld_exporter` | VM4, puerto 9104 | Estado del motor, conexiones y consultas |

## Objetivos recolectados

Ocho, todos en estado `up`:

```
  haproxy                   up
  haproxy-native            up
  mysql            db1      up
  node             proxy1   up
  node             web1     up
  node             web2     up
  node             db1      up
  prometheus                up
```

Cada objetivo lleva las etiquetas `maquina` y `rol`, de modo que los paneles se
filtran por máquina y las alertas indican de dónde proceden.

## Las cinco señales del criterio

| Señal | Métrica | Componente |
|---|---|---|
| Disponibilidad | `haproxy_server_status`, `up` | Proxy y hosts |
| Latencia | `haproxy_backend_connect_time_average_seconds` | Proxy |
| Errores | `haproxy_backend_http_responses_total{code="5xx"}` | Backends |
| Saturación | `node_cpu_seconds_total`, memoria, carga | Los cuatro hosts |
| Capacidad | `node_filesystem_avail_bytes` | Los cuatro hosts |

## Mediciones de referencia

Tomadas el 20/11 con el sistema en reposo, sirven de línea base para los
umbrales:

| Máquina | CPU | Disco |
|---|---|---|
| web1 | 1,4 % | 12,6 % |
| web2 | 1,5 % | 12,4 % |
| db1 | 1,7 % | 12,6 % |
| proxy1 | 3,9 % | 10,1 % |

**Nota de método.** Las primeras lecturas marcaron entre 54 % y 69 % de CPU. No
era carga real: `rate(...[5m])` necesita cinco minutos de historia para
estabilizarse, y los exportadores acababan de arrancar. Tres minutos después los
valores eran los de la tabla. **Una métrica recién recolectada no es una medición
válida.**

## Paneles en Grafana

Tres dashboards en `http://10.33.195.180:3000`, todos con el origen Prometheus:

| Dashboard | Origen | Qué muestra |
|---|---|---|
| **HAProxy** (12693) | Exportador integrado | Disponibilidad, latencia y errores por código |
| **Node Exporter Full** (1860) | `node_exporter` | CPU, memoria, disco y red, con selector de máquina |
| **MySQL/MariaDB** (14057) | `mysqld_exporter` | Conexiones, consultas por segundo, hilos, InnoDB |

Los dos últimos se importaron por número desde el catálogo de Grafana. El
selector de `Nodename` del 1860 permite alternar entre las cuatro VMs desde el
mismo panel.

## Acceso cifrado a Grafana

El proyecto exige que la administración remota use **solo canales seguros**.
Grafana se publicaba en `http://10.33.195.180:3000`, sin cifrar, con usuario y
contraseña viajando en claro.

Se habilitó TLS reutilizando el certificado de HAProxy, que ya incluye la IP de
VM1 entre sus nombres alternativos:

```
Nombres alternativos: DNS www.lab08.nodosur.cl, DNS lab08.nodosur.cl, IP 10.33.195.180
Vigencia: 22/10/2026 a 22/10/2027
Huella SHA-256: 1C:58:12:E9:...
```

El PEM de HAProxy contiene certificado y llave juntos; se separaron con `openssl`
en dos archivos que Grafana monta en solo lectura. Las variables
`GF_SERVER_PROTOCOL`, `GF_SERVER_CERT_FILE` y `GF_SERVER_CERT_KEY` se declaran en
el Compose.

**Incidente de permisos.** Grafana no arrancaba:

```
could not load SSL certificate: open /etc/grafana/certs/grafana.key: permission denied
```

El contenedor corre con **uid 472 pero gid 0**, de modo que asignar el grupo 472
no bastaba: el usuario no pertenece a ese grupo. Se corrigió haciéndolo dueño del
archivo con `chown 472:0`, lo que permite mantener el modo `640` sin exponer la
llave.

**Estado del sitio.** El sitio del proyecto ya servía por HTTPS desde la Entrega
3, verificado en esta sesión: `HTTP/2 200` por HTTPS y `302` de redirección desde
HTTP. El aviso del navegador se debe a que el certificado es **autofirmado**,
limitación declarada desde entonces: el dominio solo existe en el DNS privado,
por lo que una autoridad pública no puede validarlo.

## Métrica de salud de respaldos

El enunciado pide expresamente incluir la **salud de respaldos** entre las
señales del panel. Se resolvió con el patrón de archivo de texto de
`node_exporter`: el script de respaldo escribe sus propias métricas al terminar.

```
# HELP respaldo_ultimo_exito_timestamp Marca de tiempo del ultimo respaldo correcto
respaldo_ultimo_exito_timestamp 1795219560
# HELP respaldo_tamano_bytes Tamano del ultimo respaldo
respaldo_tamano_bytes 79495676
```

`node_exporter` se configuró para leer ese directorio mediante una unidad
suplementaria en `/etc/systemd/system/prometheus-node-exporter.service.d/`, que
no modifica el archivo original del paquete.

**Panel en Grafana:** un `Stat` con la consulta
`(time() - respaldo_ultimo_exito_timestamp) / 3600`, en horas, con umbrales en
24 (naranja) y 26 (rojo). De un vistazo indica si los respaldos están al día.

### Las dos alertas asociadas

| Alerta | Umbral | Duración | Severidad |
|---|---|---|---|
| `RespaldoNoEjecutado` | Más de 26 h sin respaldo correcto | 10 min | crítica |
| `RespaldoDemasiadoPequeno` | Tamaño por debajo de 50 MB | 10 min | crítica |

**Las 26 horas no son arbitrarias:** el respaldo corre a diario, y ese margen
absorbe el retraso aleatorio del temporizador sin alertar en falso.

**La segunda alerta cubre el caso que la rúbrica penaliza expresamente:** un
respaldo que se ejecuta pero sale vacío o truncado. Es exactamente lo que ocurría
con la tarea obsoleta de VM2, que corría cada noche sin producir nada.

## Alertas de recursos añadidas

Grupo `recursos`, que completa el grupo `disponibilidad` ya existente:

| Alerta | Umbral | Duración | Severidad |
|---|---|---|---|
| `MaquinaSinResponder` | `up{job="node"} == 0` | 2 min | crítica |
| `DiscoCasiLleno` | Uso de `/` > 85 % | 10 min | aviso |
| `CpuAlta` | CPU > 85 % | 10 min | aviso |

`MaquinaSinResponder` cubre un hueco importante: **VM4 no es backend**, así que
su caída no dispararía ninguna alerta de HAProxy. Con esta regla, cualquier
máquina que deje de responder se detecta en dos minutos.

Con las dos de respaldos, el total es de **nueve reglas en tres grupos**: `disponibilidad`, `recursos` y `respaldos`.

## Incidente: servicio duplicado por trabajo en paralelo

Al instalar `prometheus-mysqld-exporter` en VM4, el servicio no arrancaba:

```
err="listen tcp :9104: bind: address already in use"
```

**Otro integrante ya había montado un `mysqld_exporter`** esa misma tarde, con
unidad propia en `/etc/systemd/system/mysqld_exporter.service`, usuario dedicado
y credenciales en `/etc/mysqld_exporter/.my.cnf`. Llevaba corriendo desde las
22:07.

Se conservó el existente, mejor configurado, y se retiró el del paquete.

**Error derivado:** al limpiar, se eliminó la cuenta `exporter@localhost`
asumiendo que era la nuestra. **Ambos exportadores usaban la misma**, de modo que
el que funcionaba dejó de recolectar: pasó de 1084 métricas a 1. Se detectó de
inmediato por esa caída y se restauró recreando la cuenta con la contraseña del
archivo de credenciales existente.

**Lección para el runbook.** Comprobar qué hay antes de instalar, y nunca
eliminar una cuenta de servicio sin verificar quién la usa. Trabajando en
paralelo sin comunicarlo, se duplicó un servicio y se interrumpió otro que
funcionaba. Es el tipo de incidente que un runbook con responsables definidos
previene.

---

# Alertas y escalamiento

## Arquitectura

Se añadieron dos piezas al stack de VM1:

| Pieza | Función |
|---|---|
| **Alertmanager** (contenedor, `127.0.0.1:9093`) | Recibe las alertas de Prometheus, las agrupa y las enruta |
| **Postfix** (en el sistema, `127.0.0.1` y `172.18.0.1`) | Relay local de correo, el canal de notificación |

Se eligió el correo como canal porque atiende dos criterios a la vez: el de
alertas, que exige declarar un canal, y el de **correo/relay**, que pide
notificaciones funcionando de forma segura.

**Seguridad del relay.** Postfix se configuró con `inet_interfaces` limitado a
`127.0.0.1` y a la puerta de enlace de Docker. **Nunca escucha en `0.0.0.0`**,
de modo que no es un relay abierto. La rúbrica penaliza expresamente el
*"relay abierto o inseguro"*.

## Reglas definidas

En `/srv/monitoring/prometheus/alert.rules.yml`, grupo `disponibilidad`:

| Alerta | Umbral | Duración | Severidad | Responsable |
|---|---|---|---|---|
| `BackendCaido` | `haproxy_server_status{state="UP"} == 0` | 1 min | crítica | equipo-infraestructura |
| `TodosLosBackendsCaidos` | `haproxy_backend_active_servers == 0` | 1 min | crítica | equipo-infraestructura |
| `ErroresServidorAltos` | Tasa de 5xx > 0,1/s | 5 min | aviso | equipo-aplicación |
| `ExportadorSinDatos` | `up{job="haproxy-native"} == 0` | 2 min | aviso | equipo-infraestructura |

Cada regla lleva tres anotaciones: `resumen`, `detalle` y **`accion`**, que
enlaza con el runbook indicando qué revisar.

**La cuarta alerta vigila al propio monitoreo.** Sin ella, un fallo del
exportador se confundiría con "todo va bien": el panel se queda sin datos y
nadie recibe nada.

## Control del ruido

El criterio exige alertar *"sin ruido excesivo"*. La configuración de
Alertmanager lo gestiona así:

| Parámetro | Valor | Qué evita |
|---|---|---|
| `for` en cada regla | 1 a 5 min | Alertar por un parpadeo momentáneo |
| `group_wait` | 30 s | Un correo por cada backend si caen varios a la vez |
| `repeat_interval` | 4 h, 1 h para críticas | Repetir el mismo aviso continuamente |
| `send_resolved` | `true` | Dejar al equipo sin saber que se recuperó |

## Ensayo de degradación controlada

Se detuvo el contenedor de WordPress en VM3, igual que en las pruebas de falla
de la Entrega 3.

| Hora UTC | Evento | Fuente |
|---|---|---|
| 22:52:48 | Sin alertas activas | API de Prometheus |
| 22:52:56 | Contenedor `web2` detenido | VM3 |
| **22:54:09** | **Alerta en `firing`** | API de Prometheus |
| 23:00:30 | Correo `[FIRING:1] BackendCaido` entregado | `/var/log/mail.log` |
| 23:01:22 | Contenedor levantado | VM3 |
| 23:01:54 | Backend de vuelta en `UP` | Panel de HAProxy |
| 23:02 | Correo `[RESOLVED] BackendCaido` entregado | Buzón de `xavineta2026` |

| Medida | Resultado | Objetivo | |
|---|---|---|---|
| **Detección** | **73 segundos** | ≤ 5 min | Cumple |

La demora del correo entre las 22:54 y las 23:00 corresponde al incidente de
firewall descrito abajo, no al sistema de alertas.

**Evidencia de recepción y recuperación:** el buzón contiene la pareja
`[FIRING:1] BackendCaido aplicaciones_web` y `[RESOLVED] BackendCaido
aplicaciones_web`, originadas por una degradación real y no por inyección manual.

## Incidente: el firewall bloqueaba el puerto 25

**Síntoma.** La alerta se disparaba y llegaba a Alertmanager, pero el correo no
salía. Postfix no registraba ningún intento de conexión.

**Diagnóstico.** El log de Alertmanager lo mostró con precisión:

```
err="establish connection to server: dial tcp 172.18.0.1:25: connect: connection timed out"
```

El `connection timed out`, en lugar de `refused`, apunta a un descarte
silencioso: característico de un firewall. UFW tenía reglas para que los
contenedores alcanzaran los puertos 32500 y 8405, pero **ninguna para el 25**.

**Solución.**

```
sudo ufw allow from 172.16.0.0/12 to any port 25 proto tcp comment "Docker a Postfix (Alertmanager)"
```

Se usó `/12` para cubrir cualquier red que Docker cree, manteniendo el criterio
de las reglas existentes.

**Verificación.** Ambas notificaciones se entregaron en el **segundo intento**:

```
23:00:07 Notify success ... alertname="PruebaCorreo" ... attempts=2
23:00:26 Notify success ... alertname="BackendCaido" ... attempts=2
23:00:30 status=sent (delivered to mailbox)
```

**Lección registrada**, que repite la ya documentada con el puerto 8405: si algo
funciona desde el host pero no desde un contenedor, sospechar del firewall. Los
contenedores llegan desde `172.16.0.0/12`.

**Un acierto del diseño:** las notificaciones **no se perdieron**. Alertmanager
reintentó y entregó en cuanto se abrió el camino. Un sistema que solo intentara
una vez habría descartado la alerta en silencio.

## Error de diagnóstico registrado

El primer arreglo apuntó Alertmanager a `172.17.0.1`, la puerta de enlace de la
red por defecto de Docker. Pero el Compose crea su propia red, `monitor-net`,
cuya puerta es **`172.18.0.1`**. Se confirmó con:

```
sudo docker network inspect monitoring_monitor-net | grep -i gateway
```

Asumir la red por defecto en un entorno con redes propias de Compose es un error
fácil de cometer, y el síntoma no lo delata: ni Alertmanager ni Postfix
reportaban nada hasta revisar el log con detalle.

---

# Hallazgo: credencial en texto plano en el compose

El `compose.yaml` del stack de monitoreo contiene la contraseña del panel de
HAProxy en claro:

```
--haproxy.scrape-uri=http://admin:[clave omitida]@10.33.195.180:32500/;csv
```

El enunciado del proyecto lo prohíbe expresamente: *"No incluir claves, tokens ni
contraseñas en repositorios, capturas, scripts o imágenes."*

**Pendiente:** moverla a un archivo `.env` excluido del repositorio, igual que se
hizo con el Compose de los nodos web en la Entrega 3. El exportador afectado
(`haproxy-exporter`) es además redundante, porque el dashboard consume el
exportador integrado, de modo que otra opción es retirarlo del stack.

---

# Hallazgo: respaldo obsoleto activo en VM2

Al revisar el repositorio se comprobó que la tarea de la Entrega 2 **seguía
programada en VM2**. Su estado real:

| Tarea | Resultado |
|---|---|
| `mysqldump ... wordpress` | Falla: `mysql` ya no está instalado en VM2 |
| `rsync` a `/var/backups/wordpress/` | Falla: el directorio no existe |

El `2>/dev/null` de la línea ocultaba ambos errores, de modo que **el respaldo
llevaba meses sin producir nada sin que nadie lo notara**.

Es el escenario que la rúbrica penaliza de forma explícita: *"backup manual,
vacío, corrupto... o almacenado solo junto al origen"*. Y el argumento para la
defensa: un respaldo que falla en silencio es peor que no tener respaldo, porque
da una sensación falsa de seguridad.

Por eso el script nuevo registra cada paso con marca de tiempo y aborta con una
función `fallo()` en lugar de callarse.

La tarea se retiró de VM2, conservando copia del estado anterior como evidencia.

---

# Logs, tiempo y trazabilidad

## Arquitectura

Centralización con **rsyslog**, que ya viene en Ubuntu: VM1 actúa de receptor y
las otras tres de emisores.

```
web1, web2, db1  ──(TCP 5514, con cola en disco)──>  proxy1
                                                      │
                                      /var/log/nodosur/<maquina>/<fecha>.log
```

## Decisiones de diseño

| Decisión | Motivo |
|---|---|
| Puerto **5514**, no el 514 | El 514 está reservado y exige privilegios |
| El receptor escucha **solo en `10.33.199.65`** | La IP interna; no queda expuesto a la red universitaria |
| Firewall limitado a `10.33.199.64/29` | Solo las máquinas del proyecto pueden enviar |
| Un archivo **por máquina y por día** | El origen queda en la ruta, no hay que deducirlo |
| **Cola en disco** en los emisores | Si VM1 cae, los mensajes se guardan y se envían al volver |

La cola es lo que hace robusta la centralización. Sin ella, una caída del
receptor significaría perder los registros de ese período: justo lo que la
rúbrica penaliza con *"logs ausentes o eliminados"*.

Conviene precisar su alcance: **la cola protege de un corte de red, no de un
error en el destino.** Durante la puesta en marcha se perdieron algunos mensajes
porque el receptor los recibía y fallaba al escribirlos.

## Retención

`/etc/logrotate.d/nodosur`, con rotación diaria y **30 días** de retención,
compresión de los rotados y permisos preservados.

**Los 30 días no son arbitrarios:** coinciden con la retención de respaldos. Si
hay que investigar un incidente de hace tres semanas, existen tanto el respaldo
de ese día como sus registros.

## Hora consistente

Resuelto junto con el ensayo de restauración:

| Capa | Zona |
|---|---|
| Las cuatro máquinas | **UTC** |
| Presentación de WordPress | `America/Santiago` |

Los servidores operan en UTC para que los registros sean correlacionables entre
máquinas; la capa de presentación muestra hora local de Chile.

## Prueba de correlación

```
sudo bash -c 'grep -rh "23:4" /var/log/nodosur/*/2026-11-20.log | sort | tail -15'
```

Devuelve una secuencia ordenada por hora que cruza **tres máquinas distintas**:
las acciones de un integrante en VM3 junto a lo que ocurría simultáneamente en
VM4. Eso es la correlación que pide el criterio.

## Hallazgo inmediato de la centralización

En esa misma consulta apareció un error que nadie había visto, repetido cada seis
segundos en VM4:

```
err="Error 1227 (42000): Access denied; you need (at least one of)
     the SUPER, SLAVE MONITOR privilege(s) for this operation"
```

A la cuenta `exporter` le faltaba el privilegio `SLAVE MONITOR`, que
`mysqld_exporter` necesita para consultar el estado de réplica. No afectaba a las
demás métricas, pero llenaba el registro.

**Corregido** con `GRANT SLAVE MONITOR ON *.* TO 'exporter'@'localhost'`.

**El valor del hallazgo está en cómo se encontró:** el error ocurría en VM4 desde
hacía más de una hora y se detectó consultando el archivo central desde VM1, sin
saber de antemano qué buscar ni en qué máquina. Es exactamente el argumento para
centralizar registros.

---

# Revisión final y cierre de brechas

Antes de entregar se revisó la implementación con criterio exigente, buscando qué
marcaría un evaluador estricto. Aparecieron tres brechas, todas cerradas.

## 1. VM1 no enviaba sus registros al almacén central

El árbol contenía `db1`, `web1` y `web2`, pero **faltaba `proxy1`**: la regla del
receptor descartaba lo que llegaba desde `127.0.0.1`, de modo que sus propios
registros se quedaban solo en `/var/log/syslog`.

Era la omisión más seria, porque VM1 aloja HAProxy, el DNS y el monitoreo: una
correlación sin el balanceador queda coja.

**Corregido** con una regla adicional que escribe también los registros locales
en `/var/log/nodosur/proxy1/`. No lleva `stop`, así que el comportamiento
habitual de la máquina se conserva. Las cuatro máquinas aparecen ahora en el
árbol.

## 2. El respaldo solo cubría la configuración de VM4

El criterio pide respaldar base, archivos **y configuración**. Se respaldaban
`/etc/mysql`, `/etc/exports`, `/etc/netplan` y `/etc/fstab`, todos de VM4.
**Quedaban fuera `haproxy.cfg`, las zonas de BIND y el stack de monitoreo**: si
se perdía VM1, su configuración no existía en ningún respaldo.

**Corregido** ampliando el script para recoger la configuración de VM1 por SSH,
aprovechando la llave que ya existía. Para que el `tar` remoto no pida
contraseña se añadió una regla de `sudo` en VM1 **acotada a ese único comando**:

```
xavineta2026 ALL=(root) NOPASSWD: /usr/bin/tar -czf - /etc/haproxy /etc/bind /etc/ssl/haproxy /srv/monitoring
```

No es un permiso general: solo autoriza esa orden concreta.

El respaldo pasó de tres a **cuatro archivos verificados**, y el contenido se
comprobó listando el archivo resultante: `haproxy.cfg`, `named.conf.local`,
`prometheus.yml` y `alert.rules.yml` están dentro.

## 3. El escalamiento estaba documentado pero no implementado

Las reglas declaraban `responsable: equipo-infraestructura` o
`equipo-aplicacion`, pero **todas las notificaciones llegaban al mismo
destinatario**: el `route` de Alertmanager no usaba esa etiqueta. Un evaluador
podría considerarla decorativa.

**Corregido** con enrutamiento por etiqueta y dos receptores distintos. Las
alertas de aplicación llevan además un asunto diferenciado.

**El orden de las rutas importa**: Alertmanager las evalúa de arriba abajo y gana
la primera que coincide, por lo que la de responsable va antes que la de
severidad.

**Verificado** inyectando una alerta con `responsable=equipo-aplicacion`: llegó
con el asunto `[APLICACION] Prueba de enrutamiento por responsable`, distinto del
resto.

**Límite declarado:** ambos receptores apuntan al mismo buzón, porque en el
laboratorio no hay más destinatarios. El enrutamiento está implementado y es
funcional; en producción serían direcciones distintas por equipo.

---

# Runbook de operación

Documento completo en `runbook.md`. Trece secciones.

## Responsables y escalamiento

| Componente | Máquina | Primer responsable | Si no responde |
|---|---|---|---|
| Balanceador, DNS, monitoreo | VM1 `proxy1` | Xavi | Matías |
| Nodo web 1 | VM2 `web1` | Matías | Yovani |
| Nodo web 2 | VM3 `web2` | Yovani | Matías |
| Base de datos, NFS, respaldos | VM4 `db1` | Aníbal | Xavi |

**Criterio de escalamiento:** si el primer responsable no contesta en 15 minutos
ante una alerta crítica, actúa el segundo. Toda intervención se anota con hora
UTC.

Los dos nodos web se cubren entre sí porque son idénticos; VM1 y VM4 se respaldan
con los integrantes de más contexto en infraestructura.

## Estructura de cada procedimiento

Todos siguen la misma forma, que es la que pide el criterio:

**síntoma → evidencia → diagnóstico → acción → validación → reversión**

La regla de fondo: **recoger la evidencia antes de actuar.** Un servicio
reiniciado sin mirar los registros destruye la información que explica por qué
falló.

## Procedimientos incluidos

| # | Procedimiento | Tipo |
|---|---|---|
| 2 | Comprobación rápida del estado | General |
| 3 | `BackendCaido` | Por alerta |
| 4 | `TodosLosBackendsCaidos` | Por alerta |
| 5 | `ErroresServidorAltos` | Por alerta |
| 6 | `MaquinaSinResponder` | Por alerta |
| 7 | `DiscoCasiLleno` | Por alerta |
| 8 | `ExportadorSinDatos` | Por alerta |
| 9 | Restaurar desde respaldo | General |
| 10 | Cambios de configuración | General |
| 11 | Degradación controlada | Ensayo |

Cada alerta tiene su procedimiento, de modo que el correo que llega indica qué
leer. Las anotaciones `accion` de las reglas apuntan al mismo sitio.

## Secciones de contexto

**Límites conocidos y riesgo residual**, con los cuatro puntos únicos de falla
declarados: VM4, VM1, el host de Proxmox compartido y el destino del respaldo.
También el montaje NFS `hard`, el RPO de 24 h y la ventana de detección.

**Distinción conceptual**, que el proyecto pide diferenciar expresamente:

| Concepto | Qué tiene Nodo Sur |
|---|---|
| Balanceo de carga | Sí: HAProxy reparte entre dos nodos |
| Tolerancia a falla | Sí, en la capa web |
| Alta disponibilidad | **No**: balanceador, base, NFS y DNS son únicos |

**Qué no hacer en una demostración:** no reiniciar VM1, no apagar VM4, no
ejecutar `docker compose down -v` y no usar la base productiva para ensayos.

## Nota sobre credenciales

Los comandos del panel de HAProxy usan `admin:CLAVE` en lugar de la contraseña
real, de modo que el documento pueda subirse al repositorio sin exponer secretos.

---

# Estado por criterio

| Criterio | Peso | Estado | Qué falta |
|---|---|---|---|
| Cobertura de monitorización | 15 | **Hecho** | — |
| Alertas y escalamiento | 15 | **Hecho** | — |
| Logs, tiempo y trazabilidad | 10 | **Hecho** | — |
| Backup y retención | 15 | **Hecho** | Documentarlo como plan de backup |
| Restauración y RPO/RTO | 20 | **Hecho** | Documentado en `informe-restauracion.md` |
| Correo/relay y automatización | 10 | **Hecho** | Relay local seguro y respaldo automatizado, registrado y deshabilitable |
| Runbook y demostración | 15 | **Hecho** | Falta ejecutar la demostración ante el docente |

---

# Pendientes, por orden de retorno

1. **Demostración ante el docente**, con el panel capturado antes, durante y
   después de la degradación. Es la parte del criterio de runbook que no puede
   adelantarse.
2. **Subir la carpeta `entrega-4` al repositorio** con los tres documentos y
   las configuraciones versionadas.

## Tareas sobre el repositorio

- **Retirar o marcar como obsoleta** la tarea de `configs/crontab-root.txt`, y
  comprobar que no siga ejecutándose en ninguna máquina.
- **Faltan los archivos ocultos**: ni `.gitignore` de la raíz ni el de
  `entrega_3/compose/` llegaron a subirse, porque el navegador omite los
  archivos que empiezan con punto.
- **`entrega_3/compose/.env.example.`** subió con un punto de más al final del
  nombre. El contenido es correcto.
- **Crear la carpeta `entrega-4/`** con el script de respaldo, las unidades de
  `systemd`, el informe de restauración y esta bitácora.

## Arrastrados de entregas anteriores

- Método de medición de la disponibilidad del 99,5 %, pendiente desde la
  Entrega 1.
- Política de reinicio del contenedor de VM2, por confirmar.
- Unidades fallidas en VM1 (estado `degraded`), sin revisar.
- Contraseñas débiles: [clave omitida] en el panel de HAProxy y [clave omitida] en Grafana.
- Imágenes de contenedor con etiqueta `:latest`, sin versión fija.

---

# Registro de uso de inteligencia artificial

El enunciado lo exige: *"Mantener un registro breve: herramienta, propósito,
fragmento relevante, validación realizada y cambios aplicados."*

| Fecha | Propósito | Validación realizada |
|---|---|---|
| 16/11 | Diagnóstico del dashboard de Grafana sin datos | Cada hipótesis se comprobó con `docker logs`, `curl` a la API de Prometheus y el estado de los targets |
| 20/11 | Diseño del script de respaldo | Ejecutado a mano antes de automatizar; verificados los tres archivos y sus checksums en origen y destino |
| 20/11 | Procedimiento del ensayo de restauración | El primer intento falló; se detectó con la verificación de tablas y se corrigió el procedimiento |
| 20/11 | Reglas de alerta y configuración de Alertmanager | Las expresiones se escribieron sobre métricas comprobadas con `curl` al exportador, no supuestas. La entrega se verificó con una degradación real |
| 20/11 | Despliegue de exportadores de sistema y base de datos | Cada objetivo se verificó en la API de Prometheus; el servicio duplicado y la cuenta eliminada se detectaron y corrigieron en la misma sesión |
| 20/11 | Redacción del runbook | Los procedimientos recogen comandos ya ejecutados y verificados durante la sesión, no secuencias teóricas. El reparto de responsables lo definió el equipo |
| 20/11 | Centralización de registros con rsyslog | Verificada con mensajes de prueba desde las tres máquinas emisoras y una consulta de correlación real |
| 20/11 | Paneles y métrica de salud de respaldos | Los dashboards se importaron del catálogo oficial y se comprobó que muestran datos reales de las cuatro máquinas |
| 21/11 | Revisión crítica de la implementación | Se pidió una evaluación exigente que identificara brechas; las tres detectadas se verificaron una a una y se corrigieron con prueba funcional |

**El enunciado advierte que el código que ningún integrante pueda explicar se
considera no defendido.** Cada paso del script está justificado en la sección de
backup de esta bitácora.

---

# Sesión de correcciones posterior a la auditoría (22/11/2026)

> Esta sección **complementa** todo lo anterior. Donde contradice algo escrito
> más arriba, **manda esta sección** (ver "Correcciones a lo afirmado antes").
> Todas las horas son **UTC**. No contiene contraseñas: las claves nuevas se
> guardan fuera del repositorio.

## Contexto

El 22/11, entre las 00:48 y las 00:50 UTC, se hizo una auditoría de **solo
lectura** de las cuatro VMs contra la rúbrica de la Entrega 4. Las salidas
quedaron en `proxy1.txt`, `web1.txt`, `web2.txt` y `db1.txt`. Hallazgos
principales:

| # | Hallazgo | Criterio afectado |
|---|---|---|
| 1 | El `compose.yaml` real de VM1 tenía las claves escritas (no existía `.env`); el del repositorio no coincidía con la implementación | Secretos, documentación |
| 2 | La clave del panel de HAProxy era trivial y estaba en `haproxy.cfg`, legible por todos (644) | Secretos |
| 3 | La retención de logs con logrotate no borraba nada (archivos por día con nombre único) y recreaba archivos vacíos | Logs |
| 4 | El respaldo no incluía la configuración de VM2/VM3 ni parte de VM1, replicaba en espejo (`--delete`) y dependía de la cuenta personal de Xavi | Backup |
| 5 | La restauración no se había validado con el CMS funcionando | Restauración |
| 6 | Los segundos responsables del runbook no tenían cuenta en las VMs que debían cubrir | Runbook, accesos nominativos |
| 7 | db1 en estado `degraded`, con restos de entregas anteriores (base `wordpress`, cuentas `wp_user` y `wpuser`, reglas UFW sobrantes) | Superficie, deuda técnica |
| 8 | La notificación del ensayo del 20/11 llegó a los 7 min 34 s, sobre la meta de 5 min, y no se repitió | Alertas |
| 9 | Faltaba el panel antes, durante y después de una degradación | Monitorización |

Las correcciones se aplicaron paso a paso. En cada una se siguió la misma
regla: **copia de respaldo → validación de sintaxis → aplicar → verificar →
anotar la hora**.

---

## Paso 1 · Claves fuera del compose y rotación (VM1) · 01:01–01:03

| Acción | Detalle |
|---|---|
| Respaldos previos | `/etc/haproxy/haproxy.cfg.e4.bak`, `/srv/monitoring/compose.yaml.e4.bak` |
| `.env` | `/srv/monitoring/.env`, modo **600**, con `HAPROXY_STATS_PASS` y `GRAFANA_ADMIN_PASS` generadas con `openssl rand` |
| Compose | `scrape-uri` usa `${HAPROXY_STATS_PASS}`; Grafana usa `${GRAFANA_ADMIN_PASS}`; archivo en modo **640** |
| HAProxy | `stats auth` con la clave nueva; `haproxy.cfg` pasa a `root:haproxy 640`; `haproxy -c` válido y `reload` |
| Aplicación | `docker compose config --quiet && docker compose up -d`: se recrean `haproxy-exporter` y `grafana` |
| Grafana | `grafana cli admin reset-admin-password` con el valor del `.env` |

**Verificación:** la clave vieja da `401`; los jobs `haproxy` y
`haproxy-native` siguen en `up`; Grafana responde 200 por HTTPS; se comprobó el
ingreso con la clave nueva.

**Hallazgo técnico:** `GF_SECURITY_ADMIN_PASSWORD` solo se aplica la primera vez
que Grafana inicializa su base. La clave declarada en el compose ya no era la
real. En una instalación existente, la clave se cambia con `grafana cli`.

**Reversión:** restaurar los dos `.e4.bak`, `reload` de HAProxy y `docker compose up -d`.

---

## Paso 2 · Retención real de los logs centralizados (VM1) · 01:05–01:09

**Problema:** cada archivo es `/var/log/nodosur/<maquina>/<AAAA-MM-DD>.log`.
Como el nombre cambia cada día, `rotate 30` nunca eliminaba nada, y `create`
recreaba archivos vacíos (ya existían tres `2026-11-20.log` vacíos).

| Acción | Detalle |
|---|---|
| Vista previa | `find ... -print`: 3 vacíos para borrar, 3 rotados del día 20 para comprimir, ninguno de más de 30 días |
| Retiro de logrotate | `/etc/logrotate.d/nodosur` se movió a `/root/logrotate-nodosur.e4.bak` (fuera de `logrotate.d`, que también lee los `.bak`) |
| Script | `/usr/local/sbin/limpieza-logs-nodosur.sh`, modo 750 (ver anexo A) |
| Automatización | `limpieza-logs-nodosur.service` + `.timer`, diario a las **03:30**, `Persistent=true` |

**Verificación:** `systemd-analyze verify` sin errores; ejecución con
`status=0/SUCCESS`; los vacíos desaparecen; los del día 20 quedan en `.gz`
conservando su fecha; los del 21 y 22 quedan intactos; el timer queda
programado. El mensaje `limpieza-logs: retencion aplicada...` llega a
`/var/log/syslog` y al log central de proxy1.

**Lección para el runbook:** en los archivos de rsyslog, un mensaje de `logger`
aparece como `etiqueta:` y no como `etiqueta[pid]:`. Buscar `etiqueta\[` da un
falso negativo.

**Reversión:** `systemctl disable --now limpieza-logs-nodosur.timer`, borrar el
script y las unidades, y devolver `/root/logrotate-nodosur.e4.bak` a
`/etc/logrotate.d/nodosur`.

---

## Paso 3 · Respaldo con cuenta de servicio y configuración completa · 01:12–01:22

### 3A · Revisión previa (solo lectura)

Todas las rutas a respaldar existen en las cuatro VMs. Ninguna tiene
`AllowUsers` ni `AllowGroups` en SSH. `docker-user-rules.sh` está en
`/usr/local/sbin` de web1 y web2. Huellas de las llaves de host: web1
`SHA256:HUxJmNHFwCM8/D/60pRcQvZKGLpkCPxm4yZoznO/NR0`, web2
`SHA256:+NqxEY8EtEGqeaEaEo6Amu2WDzd3VGDZf1ThrWW5s0Y`.

### 3B · Cuenta de servicio `respaldo` en VM1, VM2 y VM3 · 01:13

| Elemento | Configuración |
|---|---|
| Usuario | `useradd --system`, contraseña **bloqueada** (`passwd -S` → `L`), home 700 |
| Llave | La pública de `root@db1` (`backup-db1`) con `from="10.33.199.68",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-user-rc` |
| sudo | `/etc/sudoers.d/respaldo`, modo 440, **un solo `tar` con argumentos fijos** (anexo B). Validado con `visudo -cf` **antes** de instalarlo |
| Destino (solo VM1) | `/home/respaldo/respaldos`, modo 700 |

### 3C · Pruebas desde db1 · 01:14–01:15

- Las huellas obtenidas con `ssh-keyscan` coinciden con las de 3A; se agregan a
  `/root/.ssh/known_hosts` (respaldo previo en `known_hosts.e4.bak`).
- db1 entra como `respaldo@proxy1`, `respaldo@web1` y `respaldo@web2`.
- El `tar` autorizado entrega 264 archivos de proxy1 y 401 de cada nodo web.
- **Un `tar` no autorizado se rechaza** (`sudo: a password is required`,
  código 1). Es la evidencia de mínimo privilegio.

### 3D · Historial copiado a la cuenta nueva (VM1) · 01:16

Los 5 respaldos existentes se copiaron (`cp -a`, conservando las fechas) a
`/home/respaldo/respaldos/db1`. El más reciente pasó `sha256sum -c`, ejecutado
como `respaldo`.

### 3E · Script nuevo de respaldo (db1) · 01:16–01:19

Respaldo previo: `/root/respaldo-nodosur.sh.e4.bak`. Cambios respecto del
anterior (el script completo está en el anexo C):

| Cambio | Motivo |
|---|---|
| Configuración de las **4 VMs**, con listas completas | Antes faltaban VM2 y VM3, y en VM1 faltaban UFW, Postfix, rsyslog, systemd, netplan, sudoers y los scripts |
| Cuenta de servicio `respaldo` en lugar de `xavineta2026` | El respaldo no debe depender de una persona |
| `rsync` **sin `--delete`** y rotación independiente en el destino | Un borrado en el origen ya no se propaga a la copia separada |
| `sha256sum -c` **también en el destino** | Verifica la copia, no solo el origen |
| Función `aviso()` y métrica `respaldo_avisos` | Un componente que falla se registra y se puede alertar; ya no hay `2>/dev/null` |
| Escritura atómica del archivo `.prom` | Evita que Prometheus lea un archivo a medio escribir |

**Incidente en la primera ejecución (01:17:44):** el servicio falló con
`tar: wp-content: file changed as we read it`. `tar` devuelve **código 1**
cuando un archivo cambia durante la lectura, algo normal con el sitio en uso:
la copia sirve igual. **El script original tenía la misma línea
(`|| fallo`)**, así que cualquier noche podía abortar y dejar el sitio un día
sin respaldo. Es un fallo latente que existía desde el 20/11.

**Corrección:** código 1 → se registra una nota y se continúa (no suma
avisos); código 2 o mayor → fallo. Se borró la carpeta incompleta
`20261122-011642`.

**Ejecución correcta (01:19:02–01:19:21):**

```
base de datos: 224K | archivos: 77M | configuracion de db1: 20K
configuracion de proxy1: 56K | web1: 52K | web2: 52K
checksums verificados en origen: 6 archivos
replicado y verificado en 10.33.199.65:respaldos/db1/20261122-011902
metrica de salud escrita (avisos: 0)
```

Contenido comprobado: 225 archivos de db1, 264 de proxy1, 401 de web1 y 401 de
web2. Del nodo web quedan el compose, el `.env`, `wp-config.php` y
`docker-user-rules` (script y unidad).

### 3F · Alerta `RespaldoIncompleto` (VM1) · 01:20–01:21

Se agregó con `tee -a`, no con `sed -i`: el archivo es un bind mount de un solo
archivo, y reemplazarlo cambia el inodo, con lo que el contenedor dejaría de
ver los cambios. `promtool check rules` respondió `SUCCESS: 10 rules found`;
después se hizo `POST /-/reload`. **Ahora son 10 reglas en 3 grupos.**
Respaldo previo: `alert.rules.yml.e4.bak`.

### 3G · Retiro del acceso por la cuenta personal (VM1) · 01:21–01:22

- Se eliminó `/etc/sudoers.d/respaldo-remoto` (respaldo en `/root/sudoers-respaldo-remoto.e4.bak`).
- Se quitó la llave `backup-db1` de `~xavineta2026/.ssh/authorized_keys` (respaldo en `.e4.bak`).
- Se eliminó la copia antigua `~xavineta2026/respaldos`, que ya estaba duplicada y verificada.
- **Prueba:** desde db1, `ssh xavineta2026@proxy1` responde `Permission denied`, código 255.

---

## Paso 4 · Restauración validada con el CMS funcionando · 01:24–01:29

Responde a la exigencia del enunciado: *"Comprobar integridad funcional del
CMS después de restaurar"*. **La producción no se tocó.**

| Hora | Evento |
|---|---|
| **T0 01:24:06** | Inicio, en db1 |
| 01:24:12 | Checksums OK; `restore_test` con **98 tablas**; ID 20 presente; usuario temporal `restore_test@10.33.199.66` (SELECT, INSERT, UPDATE, DELETE solo sobre `restore_test`); `.env` temporal y `archivos-wp-content.tgz` enviados por `scp` a `respaldo@web1` |
| 01:24:30 y 01:26:24 | Dos ejecuciones por error en la máquina equivocada (proxy1 y db1). Sin efecto más allá de una carpeta vacía en `/tmp`, que se eliminó |
| 01:25:23 | En web1, contenedor temporal `wp-restore-test` (misma imagen `wordpress:7.1.3-php8.3-apache`), solo en `127.0.0.1:8099`, con el `wp-content` restaurado y `WP_HOME` y `WP_SITEURL` sobrescritos (la base restaurada no se modifica) |
| **T1 01:27:56** | CMS verificado |

**Comprobaciones:**

| Prueba | Resultado |
|---|---|
| Portada | HTTP 200 |
| `?p=20` | 301 → `?product=prueba-restauracion-2026-11-20-2305`, con el título visible |
| REST `/wp/v2/product/20` | `"rendered":"Prueba restauracion 2026-11-20 23:05"` |
| REST raíz | `wc/v3` presente: **WooCommerce cargado desde los archivos restaurados** |
| `marca-restauracion.txt` | `marca de prueba 2026-11-20T22:37:36Z` servido por HTTP |

**RTO del servicio medido: 3 min 50 s** (T0 → T1), frente a la meta de 60 min.
Incluye los dos errores de ejecución. El tiempo técnico es unos 6 s de base más
unos 40 s de arranque de WordPress.

**Limpieza (01:28:58–01:29:06):** `docker rm -f -v wp-restore-test`; se borraron
`/tmp/restore_test`, el `.tgz` y el `.env` temporal; `DROP USER` y
`DROP DATABASE restore_test`. Solo queda el contenedor `web1`, en estado
`healthy`.

---

## Paso 5 · Cuentas nominativas de los segundos responsables · 01:32–01:34

| VM | Responsable | Reemplazo creado |
|---|---|---|
| VM1 proxy1 | xavineta2026 | `mgonzalez` |
| VM2 web1 | mgonzalez | `yovani` |
| VM3 web2 | yovani | `mgonzalez` |
| VM4 db1 | anibal | `xavineta2026` |

Todas en el grupo `sudo`, con contraseña temporal y **cambio obligatorio en el
primer ingreso** (`chage -d 0`). Cada VM queda con exactamente **dos**
administradores.

**Nota sobre db1:** ya existía una cuenta `xavineta2026` (shell
`/usr/sbin/nologin`, sin home, `lastlog` → *Never logged in*). **No era un
resto:** la bitácora de la Entrega 3 (clase 5) registra que se creó a propósito
con `useradd -M -s /usr/sbin/nologin` para la prueba de ACL de solo lectura
(`r-X`) sobre `/srv/proyecto/compartido`. Se habilitó (`/bin/bash` y home
desde `/etc/skel`) y se agregó a `sudo` como reemplazo de Xavi en VM4.

**Efecto sobre la prueba de la clase 5:** la ACL sigue aplicándose al usuario
(`sudo -u xavineta2026 touch .../prueba-xavi` debería seguir dando
`Permission denied`), pero el usuario ahora es administrador de VM4 y puede
saltarla con `sudo`. La demostración de "quien solo observa recibe una ACL
puntual" debe documentarse ahora con otro usuario, o declararse superada por
el cambio de rol. **Pendiente** decidir cuál de las dos.

**Pendiente:** el primer ingreso de cada reemplazo, para que defina su propia
contraseña. Desde ahí, ningún integrante debe entrar con la cuenta de otro.
Cuando falle la VPN se puede saltar desde otra VM, **pero con el usuario
propio**.

---

## Paso 6 · Limpieza de db1 · 01:35–01:40

| Acción | Resultado |
|---|---|
| `systemctl reset-failed prometheus-mysqld-exporter` (resto del exportador duplicado) | — |
| `systemctl disable --now openipmi` (driver de hardware que una VM no tiene) | db1 pasa de `degraded` a **`running`** |
| Base residual `wordpress` (12 tablas) | Respaldo en `/root/wordpress-residual.e4.sql.gz` (600) y luego `DROP DATABASE` |
| Cuentas `wp_user@.66`, `wp_user@.67`, `wpuser@localhost` | Eliminadas, tras confirmar que web1 y web2 usan `admin` y `lab08_db` |
| UFW: `111` desde `10.33.199.64/29` (pendiente H15 de la E3) y `9104` desde `10.33.199.68` (la propia máquina) | Eliminadas. Respaldo en `/root/ufw.e4.bak` |

**Verificación:** web1 y web2 siguen montando `nfs4`, ven `uploads` y
`health.php` responde 200. Queda confirmado que NFS 4.2 solo necesita el puerto
2049.

**Riesgo residual que no se tocó** (no se confirmó a quién pertenece):

- servicios de prácticas de clase en db1: Apache con `backend.anibal.test` y `cms.anibal.test`, el `backend.service` (FastAPI en `/opt/backend`) y un Prometheus nativo en el puerto 9090. UFW los bloquea;
- reglas de SSH desde `10.33.117.60` y `10.33.126.205`, de origen no confirmado;
- `PermitRootLogin` es `no` en web1 y `without-password` en proxy1 y web2.

---

## Incidente real: web1 sin servir la portada durante unos 73 minutos

Se detectó **por casualidad** al preparar la degradación controlada, no por el
monitoreo.

| Hora UTC | Evento | Evidencia |
|---|---|---|
| ~00:39 | En web1, una operación `unlink` sobre `wp-content/languages` (NFS) queda colgada, probablemente por una actualización automática de traducciones de WordPress. Con el montaje `hard` nunca termina y retiene el bloqueo de la carpeta | `dmesg`: `task apache2:117946 blocked for more than 1228 seconds` a las 00:59:39; `nfs_dentry_iput [nfs]` |
| 00:39–01:52 | Cada petición a la portada que cae en web1 queda en estado `D` en `iterate_dir` sobre `wp-content/languages`, porque WordPress lista esa carpeta para cargar los idiomas | `/proc/PID/stack`; `ls -l /proc/PID/fd`; hasta 10 procesos; `load average: 10.79` sin uso de CPU |
| 00:39–01:52 | **Sin alerta.** `health.php` responde en 3 ms (no carga WordPress), así que HAProxy mantiene a web1 en `UP`. Con `timeout server 10m` tampoco se generan 5xx | Logs de web1: `GET /health.php 200` cada 2 s |
| 00:49 | La auditoría ya registra `load average: 1.00` en web1 (el primer proceso trabado) | `web1.txt` |
| 01:47 | Síntoma: el registro de la prueba alterna `web=200` y `web=000` | Registro en VM1 |
| 01:48–01:50 | Diagnóstico: con `x-backend`, las peticiones a web2 dan 200 en 0,6 s y las de web1 no responden en 15 s; `health.php` da 200 en los dos | `curl` desde VM1 |
| 01:51:56 | Corrección mínima: `docker restart -t 20 web1`, con código 0. web2 atendió solo mientras tanto | — |
| 01:53 | Validación: sin procesos `D`; `ls languages` funciona; portada local en 0,3 s; **4/4 peticiones por HAProxy con 200, alternando web1 y web2** | — |

**Causa raíz:** una operación NFS colgada en el cliente de web1, que dejó
bloqueada una carpeta que lee toda petición de WordPress.

**Relación con la Entrega 3:** la sección "NFS de `wp-content`" de la bitácora
3 ya declaraba este riesgo: *"El montaje es `hard`: si VM4 deja de responder,
los procesos que accedan a `wp-content` se quedan esperando en vez de fallar
rápido"*. El incidente es la materialización de un riesgo documentado, aunque
la causa no fue la caída de VM4, sino una operación colgada en el cliente. La
misma bitácora afirmaba que `health.php` *"recorre la pila completa"*. Este
incidente demuestra que no es así: recorre PHP, pero no el NFS ni WordPress.

**Por qué no se detectó (brecha de observabilidad):**

1. El chequeo de salud no representa el servicio real. Era un pendiente de la E3: *"que `health.php` compruebe también el NFS"*.
2. No existe ninguna alerta de latencia ni una prueba del sitio de punta a punta.
3. `timeout server 10m` hace que una petición colgada no se convierta en un error 5xx alertable.

**Mejoras propuestas** (en evaluación):

- un `health.php` que toque el NFS y WordPress, con un tiempo de espera corto;
- una alerta por sesiones acumuladas o tiempo de respuesta por servidor en HAProxy;
- bajar `timeout server` para que una petición colgada termine en 504 y dispare `ErroresServidorAltos`.

**Nota de método:** la antigüedad de un proceso de Apache **no** es la duración
de un bloqueo, porque Apache reutiliza sus procesos durante horas. El inicio del
incidente se fija con `dmesg` (`blocked for more than N seconds`).

**Pendiente:** confirmar que existe `~/evidencia-e4/incidente-web1-*.txt` en
web1. Si no se generó, esta tabla y las salidas registradas en esta sesión son
la evidencia.

---

## Paso 7 · Degradación controlada medida · 02:05–02:13

Cubre las evidencias mínimas *"Panel con métricas antes, durante y después de
una degradación"* y *"Alerta recibida y vinculada con la evidencia de la
causa"*, y reemplaza la medición del 20/11.

**Método.** Grafana **Explore** en **UTC** con dos consultas:
`haproxy_server_status{proxy="aplicaciones_web",state="UP"}` (leyenda
`{{server}}`) y `ALERTS{alertname="BackendCaido"}`. En VM1, un registro cada
unos 2,5 s (`~/evidencia-e4/degradacion-20261122T020506Z.log`) anota el estado
de los backends (CSV de HAProxy), el nodo que atiende la portada por HTTPS
(`x-backend`), el estado de la alerta (API de Prometheus) y el conteo de
correos `FIRING` y `RESOLVED` en el buzón.

**Falla inyectada:** `docker compose stop` del contenedor `web2` en VM3.

### Línea de tiempo

| Hora UTC | Δ desde T0 | Evento | Fuente |
|---|---|---|---|
| **02:05:26** | **T0** | `docker compose stop` en web2 | Terminal de VM3 |
| 02:05:30 | +4 s | HAProxy cuenta chequeos fallidos (`UP 2/3`). **Una petición no recibe respuesta** (cayó en web2 mientras se detenía) | Registro |
| 02:05:29 | +3 s | `sudo: yovani ... COMMAND=/usr/bin/docker compose stop` (después de escribir la clave de sudo) | Log central de web2 |
| 02:05:30.6 | +4 s | Contenedor detenido; Docker no lo reinicia (`ShouldRestart failed ... hasBeenManuallyStopped=true`): `unless-stopped` actúa como corresponde | Log central de web2 |
| **02:05:34.6** | **+8,6 s** | **`Server aplicaciones_web/srv-2 is DOWN, reason: Layer4 connection problem, info: "Connection refused"`**, `1 active`. Retiro 4 s después de detenerse el contenedor. Desde aquí **todas las peticiones las atiende web1** | `/var/log/haproxy.log` y registro |
| 02:05:48 | +22 s | Alerta `BackendCaido` en `pending` | API de Prometheus |
| **02:06:49** | **+1 min 23 s** | Alerta en **`firing`** (tras el `for: 1m`) | API de Prometheus |
| **02:07:17** | **+1 min 51 s** | **Correo `[FIRING:1] BackendCaido ... srv-2 critica` entregado** | `mail.log` (`status=sent`) y cabecera `Date` |
| 02:08:45 | +3 min 19 s | `docker compose start` en web2 | Terminal de VM3 |
| 02:08:48.9 | +3 min 23 s | `srv-2 is UP, reason: Layer7 check passed, code: 200` | `/var/log/haproxy.log` |
| 02:08:52 | — | **Una petición no recibe respuesta** al reintegrar (web2 recién arrancado tarda más de 8 s en la primera portada: caché fría) | Registro |
| 02:09:02 | — | Alerta inactiva; web1 y web2 alternan de nuevo | Registro |
| **02:12:17** | — | **Correo `[RESOLVED] BackendCaido` entregado**, 3 min 32 s después de la recuperación (ciclo `group_interval: 5m` de Alertmanager) | `mail.log` y cabecera `Date` |

### Resultados contra los objetivos

| Indicador | Medido | Meta | Resultado |
|---|---|---|---|
| Retiro del nodo por HAProxy | 4 s desde que el contenedor se detuvo (8,6 s desde el T0 del terminal) | — | Consistente con la E3 (4 s con fallo de contenedor) |
| Detección (T0 → `firing`) | **1 min 23 s** | ≤ 5 min | Cumple |
| **Notificación recibida (T0 → correo entregado)** | **1 min 51 s** | ≤ 5 min | **Cumple** (el 20/11 fueron 7 min 34 s) |
| Continuidad del servicio | 164 de 166 peticiones atendidas (98,8 %); con srv-2 caído, el 100 % las atendió web1 | La caída de un backend no interrumpe el servicio | Cumple |
| Recuperación (`start` → `UP`) | ~4 s | — | — |
| Aviso de recuperación | 3 min 32 s tras recuperar | — | Lo determina `group_interval: 5m` |

### Capturas

| Archivo | Qué muestra |
|---|---|
| `E4_antes.png` | srv-1 y srv-2 en 1. Se ve además la caída breve de srv-1 a las 01:52 (reinicio de web1 por el incidente): la alerta llegó solo a `pending` y no notificó, porque srv-1 volvió antes de 1 min. Es evidencia del **control de ruido** |
| `E4_durante.png` | srv-2 en 0 desde las 02:05:30, srv-1 en 1, serie `alertstate="pending"` y luego `"firing"`; en *Raw*, `server="srv-2"` con valor 0 y `ALERTS{... alertstate="firing", severidad="critica", responsable="equipo-infraestructura"}` |
| `E4_despues.png` | El "valle" completo de srv-2 (02:05:30–02:08:50) y su vuelta a 1; la alerta terminada |

### Límites observados (para la defensa)

- **Dos peticiones sin respuesta en total**: una al detener el nodo (antes de que HAProxy lo retirara) y otra al reintegrarlo (caché fría). Coincide con los límites declarados en la E3, ahora medidos. Mitigaciones posibles: `option redispatch` con `retries` en HAProxy, `slowstart` al reintegrar un servidor, y un *warm-up* del nodo antes de marcarlo sano.
- **El aviso de recuperación tarda hasta 5 min** por `group_interval`. Si se necesita antes, se puede bajar ese valor para la ruta crítica.
- **El canal es un buzón local en VM1**: si cae VM1, no se notifica nada (declarado como punto único de falla).
- **Hallazgo de logs:** los eventos de HAProxy **no llegan al almacén central** (`/var/log/nodosur/proxy1/`). En VM1, `49-haproxy.conf` los envía a `/var/log/haproxy.log` y corta con `stop` antes de que se aplique `91-nodosur-local.conf`. La secuencia de esta prueba se reconstruyó cruzando `/var/log/haproxy.log`, el log central de web2 y `mail.log` (captura `E4_secuencia_logs.png`). **Pendiente:** renombrar `91-nodosur-local.conf` a un número menor que 49 (por ejemplo `45-`), validar con `rsyslogd -N1` y reiniciar rsyslog. Además, cada línea de HAProxy aparece duplicada en `haproxy.log`.
- **Nota de método:** el registro mostraba mal las líneas en pantalla porque el encabezado `x-backend` termina en `\r`. El archivo está completo y el análisis se hizo con `tr -d '\r'`.

---

## Correcciones a lo afirmado antes en esta bitácora

| Se dijo | Lo correcto |
|---|---|
| "Nueve reglas en tres grupos" | **Diez**: se agregó `RespaldoIncompleto` |
| Marca de restauración: "entrada publicada, ID 20" | Es un **producto de WooCommerce** (`post_type = product`) publicado |
| "Detección 73 s" como cumplimiento de la meta | 73 s es el tiempo hasta `firing`. El **correo** del 20/11 llegó a los **7 min 34 s** por el puerto 25 bloqueado. Medición nueva del 22/11 (paso 7): `firing` a 1 min 23 s y **correo entregado a 1 min 51 s** de la falla |
| El compose del repositorio usa `.env` | En VM1 no existía `.env` hasta el paso 1. Ahora sí coinciden |
| El respaldo replica a `xavineta2026@proxy1:respaldos/db1` | Replica a `respaldo@proxy1:respaldos/db1` (cuenta de servicio) |
| Retención de logs con logrotate | Script `limpieza-logs-nodosur` con un timer a las 03:30 |
| RTO de 32 s | 32 s es solo la extracción. **El RTO del servicio con el CMS funcionando es 3 min 50 s** |
| Pendiente arrastrado "contraseñas débiles" | Rotadas en el paso 1. **No volver a escribir claves en ningún documento** |
| El SSH del informe "exclusivamente con llaves" | Por criterio del docente, se mantiene la autenticación por contraseña, mitigada por UFW (solo la VPN y la red universitaria) |

---

## Pendientes para cerrar la entrega (paso 8)

**Repositorio y zip:**

- [ ] `monitoreo/compose.yaml`, `monitoreo/alert.rules.yml` (10 reglas) y `monitoreo/alertmanager.yml`: copiar las versiones reales de VM1
- [ ] `backup/respaldo-nodosur.sh`: reemplazar por el script del anexo C
- [ ] `backup/sudoers.d-respaldo-remoto`: reemplazar por las dos variantes de `sudoers.d/respaldo` (anexo B) y agregar `authorized_keys` de ejemplo con las restricciones
- [ ] `logs/logrotate-nodosur`: reemplazar por `limpieza-logs-nodosur.sh`, `.service` y `.timer`
- [ ] Nombres de archivo con el formato `E04_grupo08_descripcion.ext`
- [ ] Subir los archivos ocultos (`.gitignore`, `.env.example`) y etiquetar la versión

**Documentos (README, informe, runbook, guía de defensa):**

- [ ] Quitar toda contraseña escrita, incluidas las que aparecen en las secciones anteriores de esta misma bitácora
- [ ] 9 → 10 reglas; "entrada" → "producto"; RTO del servicio 3 min 50 s
- [ ] Reemplazar "detección 73 s" y "menos de dos minutos" por: detección 1 min 23 s, **notificación 1 min 51 s**, continuidad 98,8 % (paso 7)
- [ ] Agregar al zip las capturas `E4_antes.png`, `E4_durante.png`, `E4_despues.png`, `E4_alerta_correo.png`, `E4_secuencia_logs.png` y `E4_respaldo_checksum.png`, y el registro `degradacion-20261122T020506Z.log`
- [ ] VM1: llevar los eventos de HAProxy al almacén central (renombrar `91-nodosur-local.conf` a `45-nodosur-local.conf`)
- [ ] Runbook: procedimiento de restauración **a producción** (hoy solo existe a `restore_test`); procedimiento del paso 4 como ensayo; cuentas de escalamiento; búsqueda de `logger` con `etiqueta:`; incidente de web1 como caso de estudio
- [ ] Informe: SSH por contraseña según criterio docente; subred administrativa real `10.33.195.128/25`; hostnames reales (`proxy1`, `web1`, `web2`, `db1`); retroalimentación de la E1 (orden del plan, RNF-04, reservas)
- [ ] Bitácora de contribuciones por integrante para la E4
- [ ] Registro de IA con herramienta, fragmento relevante, validación y cambios

---

## Registro de uso de inteligencia artificial (esta sesión)

| Fecha | Herramienta | Propósito | Validación realizada |
|---|---|---|---|
| 22/11 | Claude (Anthropic) | Auditoría de solo lectura contra la rúbrica y guía paso a paso de las correcciones | Cada bloque se ejecutó en la VM correspondiente y su salida se revisó antes de continuar: `haproxy -c`, `visudo -cf`, `promtool`, `systemd-analyze verify`, `sha256sum -c` en origen y destino, pruebas de acceso permitido y denegado, y pruebas HTTP por HAProxy. Dos errores del asistente quedaron registrados y corregidos: el patrón `etiqueta\[` del `grep` y la interpretación inicial de la antigüedad de los procesos como duración del incidente |

---

## Anexo A · `/usr/local/sbin/limpieza-logs-nodosur.sh` (VM1)

```bash
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
```

Unidades: `limpieza-logs-nodosur.service` (`Type=oneshot`) y
`limpieza-logs-nodosur.timer` (`OnCalendar=*-*-* 03:30:00`, `Persistent=true`).

## Anexo B · Cuenta `respaldo`

`authorized_keys` (VM1, VM2 y VM3):

```
from="10.33.199.68",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-user-rc ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINQpIT4dhhINQTL+ob91xkCM03Cww0fr+Uv5W7LO01wy backup-db1
```

`/etc/sudoers.d/respaldo` en VM1:

```
respaldo ALL=(root) NOPASSWD: /usr/bin/tar -czf - -C / etc/haproxy etc/bind etc/ssl/haproxy srv/monitoring etc/ufw etc/postfix etc/aliases etc/rsyslog.d etc/netplan etc/systemd/system etc/sudoers.d usr/local/sbin usr/local/bin
```

`/etc/sudoers.d/respaldo` en VM2 y VM3:

```
respaldo ALL=(root) NOPASSWD: /usr/bin/tar -czf - -C / srv/tas var/www/html/wp-config.php etc/apache2 etc/ufw etc/rsyslog.d etc/netplan etc/fstab etc/systemd/system usr/local/sbin usr/local/bin
```

Regla de alerta agregada (`alert.rules.yml`, grupo `respaldos`):

```yaml
      - alert: RespaldoIncompleto
        expr: respaldo_avisos > 0
        for: 10m
        labels:
          severidad: aviso
          responsable: equipo-infraestructura
        annotations:
          resumen: "El ultimo respaldo no incluyo todos los componentes"
          detalle: "{{ $value }} componente(s) no se pudieron respaldar (configuracion remota o rotacion)."
          accion: "Revisar las lineas AVISO en /var/log/respaldo-nodosur.log de VM4"
```

## Anexo C · `/usr/local/sbin/respaldo-nodosur.sh` (db1), versión del 22/11

```bash
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
```

## Anexo D · Respaldos de configuración creados en esta sesión

| Máquina | Archivo |
|---|---|
| proxy1 | `/etc/haproxy/haproxy.cfg.e4.bak`, `/srv/monitoring/compose.yaml.e4.bak`, `/srv/monitoring/prometheus/alert.rules.yml.e4.bak`, `/root/logrotate-nodosur.e4.bak`, `/root/sudoers-respaldo-remoto.e4.bak`, `~xavineta2026/.ssh/authorized_keys.e4.bak` |
| db1 | `/root/respaldo-nodosur.sh.e4.bak`, `/root/.ssh/known_hosts.e4.bak`, `/root/wordpress-residual.e4.sql.gz`, `/root/ufw.e4.bak/` |

## Anexo E · Capturas de evidencia (`capturas-e4/`)

Todas las horas en UTC, del 22/11/2026.

| Archivo | Qué muestra | Evidencia mínima |
|---|---|---|
| `E4_antes.png` | Grafana Explore (UTC): srv-1 y srv-2 en 1 antes de la prueba. Se ve también la caída breve de srv-1 a las 01:52 (reinicio de web1 por el incidente) con la alerta solo en `pending`: control de ruido | Panel antes, durante y después |
| `E4_durante.png` | srv-2 en 0 desde las 02:05:30, srv-1 en 1, `ALERTS` en `pending` y luego `firing`; en *Raw*, `server="srv-2"` con valor 0 y la alerta con `severidad="critica"` y `responsable="equipo-infraestructura"` | Panel antes, durante y después; alerta vinculada a la causa |
| `E4_despues.png` | El "valle" completo de srv-2 (02:05:30–02:08:50) y su vuelta a 1; alerta terminada | Panel antes, durante y después |
| `E4_falla_web2_stop.png` | Terminal de web2: `docker compose stop` a las 02:05:26 (T0) | Falla inyectada con hora |
| `E4_falla_web2_start.png` | Terminal de web2: `docker compose start` a las 02:08:45 | Recuperación con hora |
| `E4_registro_correo_firing.png` | Registro de VM1: la alerta pasa a `firing` y `correos_firing` sube de 1 a 2 | Alerta recibida |
| `E4_registro_correo_resolved.png` | Registro de VM1: `correos_resolved` sube de 1 a 2 | Aviso de recuperación recibido |
| `E4_alerta_correo.png` | Buzón: `[FIRING:1] BackendCaido ... srv-2 critica` (02:07:17) y `[RESOLVED]` (02:12:17); Postfix `status=sent (delivered to mailbox)` | Alerta recibida y vinculada con la causa |
| `E4_secuencia_logs.png` | Una sola línea de tiempo con 3 fuentes y 2 máquinas: `docker compose stop` (web2, usuario `yovani`) → `ShouldRestart ... hasBeenManuallyStopped` → HAProxy `srv-2 is DOWN` (02:05:34.6) → correo FIRING (02:07:17.5) → `docker compose start` (02:08:45) → HAProxy `srv-2 is UP` (02:08:48.9) → correo RESOLVED (02:12:17.4) | Logs que permiten reconstruir una secuencia |
| `E4_respaldo_checksum_db1.png` | Log del respaldo `20261122-011902` (base, archivos y las 4 configuraciones, 6 checksums, `avisos: 0`); los 6 conjuntos y `sha256sum -c` con 6 `OK` en db1 | Inventario de respaldos, retención y checksum |
| `E4_respaldo_checksum_proxy1.png` | Destino separado en VM1, verificado como la cuenta de servicio `respaldo`: los 6 conjuntos y 6 `OK` | Copia separada verificada |
| `E4_incidente_web1_alternancia.png` | Terminal de VM1: el registro a las 01:47–01:48 alterna `web=200` y `web=000`, síntoma del incidente real de web1 | Detección y diagnóstico de incidente |

Las versiones sin recortar de estas dos capturas (con varias terminales a la
vez) se conservan en `capturas-e4/originales/`.

**Evidencias sin captura:** la restauración funcional (paso 4: producto ID 20
por REST, `wc/v3` y el archivo de marca servidos por un WordPress temporal) y el
RTO del servicio (3 min 50 s) están registrados como salida de terminal en el
paso 4 de esta bitácora.


---

## Paso 8 (complemento) · Certificado firmado por una CA propia · 22/11 ~03:00–03:06 UTC

**Motivo:** el docente pidió entrar por HTTPS. El certificado autofirmado
hacía que el navegador mostrara "No seguro", porque el cliente no puede
validarlo, y el enunciado pide *"certificados validados desde cliente y
servidor"*. Como `lab08.nodosur.cl` solo existe en el DNS privado, no es
posible un certificado público (por ejemplo, Let's Encrypt).

| Acción (VM1, como root) | Detalle |
|---|---|
| CA propia | `/root/ca/nodosur-ca.crt` ("Nodo Sur Lab CA", 10 años); llave `/root/ca/nodosur-ca.key` con modo 600. Huella SHA1 `61C714156FB078E85B8D828672BA70E6CD5C78EF` |
| Certificado del sitio | Firmado por la CA, 397 días, con SAN `www.lab08.nodosur.cl`, `lab08.nodosur.cl` e IP `10.33.195.180`; `serverAuth`; `openssl verify` → `OK` |
| HAProxy | Respaldo en `/etc/ssl/haproxy/lab08.nodosur.pem.e4-autofirmado.bak`; PEM nuevo con certificado + CA + llave (600); `haproxy -c` válido y `reload` |
| Grafana | Respaldos `grafana.crt.e4.bak` y `grafana.key.e4.bak`; certificado + CA y llave (`472:0`, 644/640); reinicio del contenedor |

**Verificación:** puerto 443 con `Verify return code: 0 (ok)` usando la CA, y
`curl --cacert` responde `HTTP/2 200` **sin `-k`**. Desde un cliente externo,
los dos puertos (443 y 3000) entregan la cadena `www.lab08.nodosur.cl` →
`Nodo Sur Lab CA`.

**En los clientes** (cada persona en su equipo): importar `nodosur-ca.crt` en
`Cert:\CurrentUser\Root` y agregar una regla NRPT para que solo
`lab08.nodosur.cl` se resuelva con `10.33.195.180`. No se usa el archivo
`hosts`, que el enunciado prohíbe como sustituto del DNS. Se probó en el PC del
alumno: el dominio resuelve y la CA quedó instalada.

**Reversión:** restaurar los `.e4-autofirmado.bak` y `.e4.bak`, `reload` de
HAProxy y reinicio de Grafana.

**Riesgo:** quien tenga la llave de la CA puede emitir certificados que los
equipos con la CA instalada aceptarán. **Pendiente:** sacar
`/root/ca/nodosur-ca.key` de VM1 y guardarla fuera del servidor.

---

## Incidente 2 · Conflicto de IP en 10.33.195.180 · detectado 22/11 03:09 UTC

| Hora UTC | Observación | Evidencia |
|---|---|---|
| ~03:05 | La verificación de la cadena TLS desde el cliente todavía llega a VM1 (cadena `Nodo Sur Lab CA`) | `openssl s_client` desde el PC |
| 03:09 | Desde el cliente, el puerto 80 de `10.33.195.180` responde **`Server: Apache/2.4.52 (Ubuntu)`** con `400 Bad Request`; el 443 no responde TLS; el 22 y el 3000 no responden | `curl -v` y prueba de puertos desde el PC (VPN `10.30.248.28`) |
| 03:10:35 | **VM1 está sana:** `ens18` con `10.33.195.180/25`, MAC `bc:24:11:b5:8f:77`; HAProxy `active`, escuchando en 80 y 443; Grafana en 3000; en local, `curl http://127.0.0.1/` → `302` a HTTPS | Sesión en VM1 |
| 03:10:41 | **Desde db1** (misma red de administración): `10.33.195.180` responde `Apache/2.4.52 (Ubuntu)`, y `ip neigh` muestra la MAC **`bc:24:11:87:a3:b3`**, distinta de la de VM1 | Sesión en db1 |

**Diagnóstico:** otra máquina usa la misma IP que VM1 en la red de
administración. El prefijo `bc:24:11` corresponde a las interfaces virtuales de
Proxmox, así que probablemente es otra VM del mismo entorno configurada con
`10.33.195.180`. **No fue causado por los cambios de la sesión:** un fallo de
HAProxy o del certificado no haría que respondiera un Apache de Ubuntu.

**Hipótesis descartadas, con su evidencia:**

- VM1 caída → descartada (servicios activos y respuesta local correcta).
- Error del certificado nuevo → descartado (en el 80 responde otro servidor web, sin TLS).
- Problema de la VPN del cliente → descartado (db1, dentro de la red, ve lo mismo).

**Contención:** no se cambió la IP de VM1, ni el firewall, ni se enviaron
anuncios ARP para disputar la dirección. Eso generaría inestabilidad para
ambos equipos sin resolver la causa.

**Escalamiento:** se reporta al docente o al encargado de Proxmox con la IP, las
dos MAC, la hora y la firma del servidor intruso, para que se identifique y
corrija la VM con la MAC `bc:24:11:87:a3:b3`.

**Pendiente:**

- confirmar la resolución (desde db1, `ip neigh show 10.33.195.180` debe mostrar `bc:24:11:b5:8f:77`);
- repetir desde el cliente la validación HTTPS sin `-k` y el candado en el navegador.


---

## Reversión del certificado con CA propia · 22/11 03:16 UTC (HTTPS queda pendiente)

Por decisión del equipo se volvió al estado anterior al cambio de certificado,
para no tener dos variables cambiando mientras dura el conflicto de IP. El
conflicto **no** fue causado por el certificado: la MAC que responde en
`10.33.195.180` no es la de VM1, y en el puerto 80 contesta un Apache de Ubuntu
que no existe en la plataforma.

| Acción | Resultado |
|---|---|
| HAProxy: se restauró `lab08.nodosur.pem.e4-autofirmado.bak`; `haproxy -c` válido y `reload` | Emisor `O=UTFSM, OU=TAS, CN=www.lab08.nodosur.cl` (autofirmado), vence el 22/10/2027; `HTTP/2 200` |
| Grafana: se restauraron `grafana.crt.e4.bak` y `grafana.key.e4.bak`; reinicio | El mismo certificado autofirmado de antes |
| PC del alumno: se quitó la CA "Nodo Sur Lab CA" de `Cert:\CurrentUser\Root` | Verificado: ya no está en el almacén |
| PC del alumno: regla NRPT de `lab08.nodosur.cl` hacia `10.33.195.180` | **Se mantiene**: es resolución por nombre, no HTTPS |

**Se conserva para retomarlo:** `/root/ca/` en VM1 (la CA, su llave en modo 600
y el certificado firmado). El procedimiento completo y su verificación están en
la sección "Certificado firmado por una CA propia".

**Pendiente:**

- **HTTPS sin aviso** (CA propia más su instalación en el equipo de la presentación). Confirmar con el docente si lo requiere.
- Resolución del **conflicto de IP** por parte del docente o de soporte.


**Comprobación posterior a la reversión (22/11, después de las 03:16 UTC):**
con el certificado autofirmado ya restaurado, se limpió la tabla ARP de db1
(`sudo ip neigh flush to 10.33.195.180`) y se consultó de nuevo. Respondió
otra vez `HTTP/1.1 400 Bad Request` (el Apache ajeno), con `10.33.195.180 dev
ens18 lladdr bc:24:11:87:a3:b3 REACHABLE`. **Queda confirmado que el conflicto
es externo y ajeno a los cambios de la sesión.** Es posible que existiera antes
de forma intermitente: horas antes hubo fallas de conexión SSH directa a esa IP,
atribuidas en su momento a la VPN. Sigue pendiente de corrección por el docente
o por soporte.


**Cierre del incidente 2 (22/11, ~03:27 UTC):** desde el cliente, la
`10.33.195.180` vuelve a responder con la plataforma propia: puerto 80
`302 Found` (HAProxy), puerto 443 `200 OK` con `x-backend: web1`, y los puertos
22 y 3000 abiertos. Desde db1, tras limpiar la tabla ARP:
`HTTP/1.1 302 Found` y `10.33.195.180 dev ens18 lladdr bc:24:11:b5:8f:77
REACHABLE`, que es la MAC de VM1. **La máquina ajena dejó de responder sin
ningún cambio de nuestra parte.** Duración observada: desde las 03:09 (o antes,
de forma intermitente) hasta cerca de las 03:27 UTC.

**Lecciones:**

1. En un conflicto de IP, cada equipo puede ver una máquina distinta al mismo tiempo, según su tabla ARP. Por eso el cliente y db1 dieron resultados diferentes durante unos minutos.
2. El diagnóstico se sostuvo comparando la MAC, no el síntoma.
3. Se descartó la propia configuración revirtiendo el último cambio (el certificado) y comprobando que el problema persistía.

**Recomendación:** informar igual al docente, con las dos MAC. La otra VM podría
volver a encenderse con la misma IP; si reaparece, el comando de verificación
es `sudo ip neigh flush to 10.33.195.180; curl -sI http://10.33.195.180/ | head -1; ip neigh show 10.33.195.180`
desde db1.


---

## Certificado con CA propia, reaplicado y verificado · 22/11 03:29 UTC (pendiente de HTTPS cerrado)

Resuelto el conflicto de IP, se volvió a aplicar el certificado firmado por la
CA propia, que se había conservado en `/root/ca`.

| Paso | Resultado |
|---|---|
| `openssl verify -CAfile nodosur-ca.crt lab08.crt` | `lab08.crt: OK` |
| Comprobación previa: el PEM activo era el autofirmado respaldado | `cmp` sin diferencias con `.e4-autofirmado.bak` |
| HAProxy: PEM nuevo (certificado + CA + llave, 600); `haproxy -c` válido y `reload` | — |
| Grafana: certificado + CA y llave (`472:0`); reinicio | — |
| Verificación en VM1 con la CA | **Puerto 443: `Verify return code: 0 (ok)` · Puerto 3000: `Verify return code: 0 (ok)`**; `curl --cacert` → `HTTP/2 200` |
| PC del alumno: CA importada en `Cert:\CurrentUser\Root` (huella `61C714156FB078E85B8D828672BA70E6CD5C78EF`); reglas NRPT activas | `curl --ssl-no-revoke https://www.lab08.nodosur.cl/` → `HTTP/1.1 200 OK` **sin `-k`** |
| Navegador (Opera) | `https://www.lab08.nodosur.cl` con **candado y sin "No seguro"** (captura `E4_https_candado.png`) |

**Notas técnicas:**

- `curl` en Windows (Schannel) exige comprobar la revocación, y una CA de laboratorio no publica lista de revocados (`CRYPT_E_NO_REVOCATION_CHECK`). Por eso las pruebas con `curl` usan `--ssl-no-revoke`. Los navegadores no bloquean por esa causa los certificados de una CA instalada localmente.
- En los servidores Linux, `curl` valida contra su propio almacén (`/etc/ssl/certs`), donde la CA no está instalada. Allí se verifica con `--cacert /root/ca/nodosur-ca.crt`.

**Para el equipo de la presentación**, el día anterior:

1. copiar `nodosur-ca.crt`;
2. `Import-Certificate -FilePath nodosur-ca.crt -CertStoreLocation Cert:\CurrentUser\Root`;
3. como administrador, `Add-DnsClientNrptRule -Namespace ".lab08.nodosur.cl" -NameServers 10.33.195.180` y lo mismo para `lab08.nodosur.cl`;
4. cerrar y abrir el navegador.

**Pendiente:** sacar `/root/ca/nodosur-ca.key` de VM1 y guardarla fuera del servidor.


**Verificación de Grafana (22/11):** `https://www.lab08.nodosur.cl:3000`
también abre con candado y sin aviso en el navegador del cliente, con el mismo
certificado firmado por la CA propia. La instalación de la CA y de las reglas
DNS en el notebook de la presentación queda programada para el día de la
defensa (ver `checklist-presentacion.md`).


**Notebook de la presentación preparado (CachyOS, 22/11):**

- `systemd-resolved` activo y `/etc/resolv.conf` apuntando a `127.0.0.53`. Se agregó `/etc/systemd/resolved.conf.d/lab08-nodosur.conf` con `DNS=10.33.195.180` y `Domains=~lab08.nodosur.cl`, de modo que solo ese dominio se consulta al DNS del proyecto (`google.com` sigue resolviendo por la red normal).
- **Hallazgo:** el `/etc/hosts` del notebook tenía dos líneas antiguas de la Entrega 2 que enviaban `lab08.nodosur.cl` y `www.lab08.nodosur.cl` a `10.33.195.234` (web1). Por eso `resolvectl` respondía `Data from: synthetic`. Es el mismo patrón del incidente 9 de la Entrega 3. Se respaldó en `/etc/hosts.bak-nodosur` y se eliminaron solo esas dos líneas.
- CA instalada con `trust anchor --store` y `update-ca-trust`.
- **Verificación:** `curl -sI https://www.lab08.nodosur.cl/` → `HTTP/2 200` y `https://www.lab08.nodosur.cl:3000/login` → `HTTP/1.1 200 OK`, **sin `-k`**. En el navegador aparece el candado (escudo con tick) en ambos.
- Para deshacerlo después de la presentación: `sudo rm /etc/systemd/resolved.conf.d/lab08-nodosur.conf && sudo systemctl reload systemd-resolved`, y `sudo trust anchor --remove ~/nodosur-ca.crt`.


---

## Primera ejecución automática del respaldo nuevo · 22/11 03:01 UTC

El temporizador `respaldo-nodosur.timer` ejecutó por sí solo el script del
paso 3, sin intervención:

```
2026-11-22T03:01:46Z === inicio 20261122-030146 ===
2026-11-22T03:01:46Z base de datos: 224K
2026-11-22T03:02:37Z archivos: 77M
2026-11-22T03:02:37Z configuracion de db1: 20K
2026-11-22T03:02:40Z configuracion de proxy1: 56K
2026-11-22T03:02:41Z configuracion de web1: 52K
2026-11-22T03:02:43Z configuracion de web2: 52K
2026-11-22T03:02:43Z checksums verificados en origen: 6 archivos
2026-11-22T03:02:45Z replicado y verificado en 10.33.199.65:respaldos/db1/20261122-030146
2026-11-22T03:02:46Z rotacion aplicada (retencion 30 dias en origen y destino)
2026-11-22T03:02:46Z metrica de salud escrita (avisos: 0)
2026-11-22T03:02:46Z === fin 20261122-030146 ===
```

Queda demostrada la **automatización completa**: base de datos, archivos y
configuración de las cuatro máquinas; integridad en origen y destino; copia
separada con la cuenta de servicio; retención; y métrica de salud, sin avisos.

## Hallazgo: tienda en modo "Próximamente" (WooCommerce) · 22/11

**Síntoma:** desde una ventana privada (sin sesión iniciada), la tienda muestra
*"Tenemos grandes proyectos por anunciar... Nuestra tienda está en obras"* y no
se ven los productos.

**Diagnóstico:**

- `lab08_db.wp_options`: `woocommerce_coming_soon = yes` y `woocommerce_store_pages_only = yes`. WooCommerce oculta las páginas de la tienda a los visitantes no autenticados.
- Productos en `lab08_db`: ID 13 "Taller" (19/10) e ID 20 "Prueba restauracion..." (20/11), ambos publicados.
- Conteo de coincidencias de `'product'` en los 7 respaldos desde el 20/11: 2 en el primero y 3 en los seis siguientes, lo que coincide con la creación del producto de prueba a las 22:37. **No se eliminó ningún producto.**
- La base residual `wordpress`, eliminada en el paso 6, tenía 0 productos (verificado en su respaldo).

**Conclusión:** no fue causado por los cambios de la sesión, que no tocaron la
configuración de WooCommerce. Es el modo de visibilidad que WooCommerce trae
activado por defecto en las instalaciones nuevas.

**Corrección propuesta:** *WooCommerce → Ajustes → Visibilidad del sitio →
"En vivo"*, para que un cliente sin sesión vea el catálogo, como se espera en
la demostración del flujo empresarial. Pendiente de decisión del equipo.


**Corrección aplicada (22/11):** en *WooCommerce → Ajustes → Visibilidad del
sitio* se cambió de "Próximamente" a **"En vivo"**. Verificación: desde una
ventana privada (sin sesión), `https://www.lab08.nodosur.cl/?post_type=product`
muestra el catálogo con los productos. **Reversión:** volver a seleccionar
"Próximamente" en la misma pantalla.


---

## Bitácora de contribuciones por integrante · Entrega 4

El enunciado exige *"bitácora de contribuciones y cambios verificables por
integrante"* en cada entrega. Cada integrante trabajó la máquina de la que es
responsable según el runbook. La verificación de cada cambio está en las
secciones correspondientes de esta bitácora y en los registros de las máquinas
(`journalctl`, `/var/log/auth.log` y los archivos `.e4.bak`).

| Integrante | Máquina | Contribuciones de la Entrega 4 |
|---|---|---|
| **Javier Saavedra (Xavi)** | VM1 `proxy1` | Stack de monitoreo en Docker (Prometheus, Grafana, Alertmanager) y exportador integrado de HAProxy (`:8405`); dashboards; reglas de alerta (10, en 3 grupos) y enrutamiento por responsable; relay Postfix restringido; receptor central de logs (rsyslog) y su retención; claves movidas a `.env` y rotadas; cuenta de servicio `respaldo` y destino de la copia separada; certificado firmado por la CA propia en HAProxy y Grafana |
| **Matías González** | VM2 `web1` | `node_exporter` y emisor de logs de web1; cuenta de servicio `respaldo` en web1; ensayo de restauración funcional con el CMS (WordPress temporal sobre la base y los archivos restaurados, RTO del servicio de 3 min 50 s); diagnóstico y corrección del incidente de la portada colgada en web1; coordinación de la auditoría, de las correcciones y de la documentación (bitácora, informe y capturas); preparación del equipo de la presentación |
| **Yovani Contreras** | VM3 `web2` | `node_exporter` y emisor de logs de web2; cuenta de servicio `respaldo` en web2; ejecución de las degradaciones controladas sobre web2 (20/11 y 22/11: detención y recuperación del contenedor, con marcas de tiempo) que sustentan la medición de detección (1 min 23 s) y notificación (1 min 51 s) |
| **Aníbal Villablanca** | VM4 `db1` | MariaDB y `mysqld_exporter` (con su cuenta y privilegios); script de respaldo, temporizador y métrica de salud; ensayos de restauración (20/11 en `restore_test` y la parte de base de datos del 22/11); limpieza de db1 (unidades fallidas, base y cuentas residuales, reglas UFW); diagnóstico del conflicto de IP desde la red de administración |

**Trabajo conjunto:** el runbook, la guía de defensa y la revisión cruzada de
los documentos. Cada integrante debe poder explicar las piezas de su máquina y
el flujo completo (ver `guia-defensa.md`, "Reparto por integrante").

> Nota: esta tabla se construyó a partir del reparto de máquinas del runbook y
> de las sesiones en que se ejecutó cada cambio. **El equipo debe revisarla y
> ajustarla antes de la entrega** si algún aporte no corresponde exactamente.


**Llave de la CA retirada de VM1 (22/11 ~04:41 UTC):** se copió
`/root/ca/nodosur-ca.key` al equipo del alumno
(`Documents\NodoSur-CA\`, junto con `nodosur-ca.crt`). SHA256 idéntico en
origen y destino: `f3e6d46dd1347b081286ab9d9ed320e03b55653f0920b298d0ac10092a7074bc`.
Después se eliminó del servidor con `shred -u`, junto con la copia temporal.
En `/root/ca/` quedan solo el certificado público de la CA y los archivos del
certificado del sitio. **Verificación posterior:** el sitio y Grafana siguen
validándose por HTTPS sin `-k` (`HTTP 200`), porque la conexión usa la llave
del sitio y el cliente solo necesita el certificado público de la CA. La llave
de la CA solo hará falta para emitir un certificado nuevo (vencimiento en 397
días o un cambio de nombres). **Pendiente:** una segunda copia de
`NodoSur-CA\` en un medio externo.


**Eventos de HAProxy en el almacén central (22/11 04:41 UTC):** en VM1 se
renombró `91-nodosur-local.conf` a `45-nodosur-local.conf` (respaldo en
`/root/91-nodosur-local.conf.e4.bak`), para que se cargue antes de
`49-haproxy.conf`, que termina con `stop`. `rsyslogd -N1` validó sin errores y
se reinició rsyslog. **Verificación:** las peticiones posteriores aparecen en
`/var/log/nodosur/proxy1/2026-11-22.log` con el servidor que atendió, los
tiempos y el código (por ejemplo,
`https~ aplicaciones_web/srv-2 0/0/1/3507/3535 200`); el contador pasó de 0 a
5. El almacén central reúne ahora los registros de las cuatro máquinas,
incluido el balanceador. Se observa además el efecto de caché fría: la primera
petición a srv-2 tardó 3,5 s y las siguientes unos 0,5 s. **Reversión:**
`mv /etc/rsyslog.d/45-nodosur-local.conf /etc/rsyslog.d/91-nodosur-local.conf && systemctl restart rsyslog`.


**Hallazgo de seguridad (22/11): clave trivial en la cuenta de base de datos
de WordPress.** La cuenta `admin@10.33.199.66` / `admin@10.33.199.67` sobre
`lab08_db` usa una clave trivial (definida en `wp-config.php` de los dos
nodos). **Mitigación vigente:** MariaDB escucha solo en `10.33.199.68` (red
interna), UFW permite el 3306 solo desde web1 y web2, y la cuenta solo acepta
esas dos IP de origen. **Riesgo residual:** quien comprometa un nodo web o la
red interna podría usarla. **Corrección propuesta, después de la defensa**
(cambio coordinado, para no dejar el sitio sin base de datos):

1. Generar una clave aleatoria.
2. En db1: `ALTER USER 'admin'@'10.33.199.66' IDENTIFIED BY '<nueva>'` y lo mismo para `.67`.
3. En web1 y web2, de inmediato: respaldar `wp-config.php` y actualizar `DB_PASSWORD`.
4. Verificar que la portada responda `200` por HAProxy en los dos nodos.

**Reversión:** restaurar la clave anterior en MariaDB y el `wp-config.php`
respaldado. También se recomienda rotar después de la defensa la clave del
usuario `exporter` (en `/etc/mysqld_exporter/.my.cnf` y en MariaDB).


**Reaparición del conflicto de IP (22/11, ~05:05 UTC):** desde el navegador,
`https://www.lab08.nodosur.cl/wp-admin` devolvió `ERR_SSL_PROTOCOL_ERROR`
("respuesta no válida"). Desde db1, tras limpiar la tabla ARP: `HTTP/1.1 400
Bad Request` y `10.33.195.180 dev ens18 lladdr bc:24:11:87:a3:b3 REACHABLE`, la
misma máquina ajena de las 03:09. En el mismo minuto (05:04:36), otro cliente
recibía respuestas de VM1 (`302` y `x-backend: web1`): el conflicto es
**intermitente** y cada equipo puede ver una máquina distinta. **Se clasifica
como recurrente** y se escala al docente con las dos MAC y las dos franjas
horarias.

**Plan B para la demostración**, si ocurre durante la defensa: acceder a VM1
por la red interna (sin conflicto) con un túnel SSH a través de web1,
`ssh -N -L 443:127.0.0.1:443 -J mgonzalez@10.33.195.234 mgonzalez@10.33.199.65`,
con el dominio resuelto a `127.0.0.1` solo en el navegador de la demostración
(ver `checklist-presentacion.md`, sección E).


**Hallazgo de seguridad (22/11): clave trivial en la cuenta administradora de
WordPress (`admin`).** El panel `wp-admin` es accesible para cualquier cliente
que llegue al sitio (puerto 443 abierto en VM1), así que la cuenta queda
expuesta a pruebas de contraseña. **Decisión del equipo:** mantenerla hasta la
defensa para no alterar el acceso a la demostración. **Corrección propuesta
después de la defensa:** *Usuarios → Perfil → Establecer nueva contraseña* (el
cambio no afecta la tienda ni la base de datos) y, como mejora, limitar
`/wp-admin` por origen en HAProxy o agregar un segundo factor. Se registra
como riesgo residual junto con la clave trivial de la cuenta de base de datos.


**Corrección a lo registrado sobre la tienda (auditoría final, 22/11 05:29
UTC):** la visibilidad **no** quedó en "En vivo". En db1,
`woocommerce_coming_soon = yes`, y desde un cliente anónimo la tienda sigue
mostrando la página "Tenemos grandes proyectos...", sin productos. Los productos
se habían visto en una ventana privada **con la sesión de `wp-admin`
iniciada**, y WooCommerce siempre muestra la tienda a los administradores. La
verificación anterior fue insuficiente: debió hacerse como visitante sin
sesión. **Pendiente**, por decisión del equipo, para el día de la presentación:
*WooCommerce → Ajustes → Visibilidad del sitio → "En vivo" → Guardar*, y
verificar en una ventana privada nueva **sin iniciar sesión**.


---

## Auditoría final de solo lectura · 22/11/2026, 05:29–05:34 UTC

Script de solo lectura ejecutado en las cuatro VMs. Nada se modificó.

| Revisión | proxy1 | web1 | web2 | db1 |
|---|---|---|---|---|
| Reloj en UTC y sincronizado | ✅ | ✅ | ✅ | ✅ |
| Estado del sistema | ⚠️ `degraded` (`fwupd` y `fwupd-refresh`, ajenos a la plataforma) | ✅ `running` | ✅ `running` | ✅ `running` |
| Cuenta `respaldo` (bloqueada, llave limitada a la IP de db1, sudo con un solo `tar`) | ✅ | ✅ | ✅ | — (es el origen) |
| Primer ingreso del reemplazo | ⏳ `mgonzalez` | ⏳ `yovani` | ⏳ `mgonzalez` | ⏳ `xavineta2026` |
| UFW según el diseño | ✅ | ✅ | ✅ | ✅ (2 IP de SSH sin confirmar, declaradas) |
| rsyslog y `node_exporter` activos | ✅ | ✅ | ✅ | ✅ |

**proxy1:**

- HAProxy activo con configuración válida; `haproxy.cfg` con permisos `640 root:haproxy`.
- Certificado del sitio y de Grafana emitido por "Nodo Sur Lab CA", vigente hasta el 24/12/2027.
- `/root/ca` **sin** la llave de la CA.
- `.env` 600 y compose 640 con variables.
- 4 contenedores con reinicio automático.
- **8/8 targets `up`, 10 reglas en 3 grupos, todas `ok`, sin alertas activas.**
- Respaldo: hace 2,5 h, 80 MB, `avisos 0`.
- Postfix solo en `127.0.0.1` y `172.18.0.1`.
- Logs centrales de las 4 máquinas al día, con 26 líneas de HAProxy hoy.
- **El timer de retención se ejecutó solo a las 03:30**; logrotate retirado.
- Copia separada con 7 conjuntos y checksum del último OK en el destino.
- La llave de db1 ya no está en la cuenta personal.

**web1 y web2:** contenedores `healthy` (4 h y 3 h), `unless-stopped` e
imagen `7.1.3`; **0 procesos en estado D** (web1 estable desde la corrección del
incidente); `health.php` responde `200` en unos 1 ms; la portada responde en
unos 3,3–3,5 s en la primera petición tras un período sin uso (caché fría); NFS
4.2 montado; regla `DOCKER-USER` activa; sin cron de root.

**db1:** MariaDB, NFS, `mysqld_exporter` y el timer de respaldo activos (próxima
ejecución el 23/11 a las 03:00); último respaldo automático (03:01) con 4
configuraciones, 6 checksums y `avisos: 0`; 7 conjuntos con checksum OK en
origen; `lab08_db` con 98 tablas y solo las cuentas necesarias; MariaDB escucha
solo en `10.33.199.68`.

**Pendientes detectados:**

1. **Tienda en modo "Próximamente"** (`woocommerce_coming_soon = yes`): se pasa a "En vivo" antes de la demostración (checklist, sección F).
2. **Conflicto de IP activo:** db1 ve otra vez la MAC ajena `bc:24:11:87:a3:b3` en `10.33.195.180`, mientras otro cliente llega a VM1 en el mismo minuto. Es intermitente y se escala al docente; hay plan B (checklist, sección E).
3. **Primeros ingresos** de las cuatro cuentas de reemplazo.
4. **`degraded` en proxy1** por `fwupd` (opcional: deshabilitar `fwupd-refresh.timer` y limpiar las unidades fallidas).


---

## Precisiones finales tras la revisión cruzada · 22/11/2026

Una revisión externa del informe v2 contra el enunciado y la rúbrica (un
compañero, con apoyo de otra IA) se contrastó punto por punto con el texto del
informe. Resultado:

- **Ya corregidos en E.8:** subred de administración, hostnames, SSH con
  contraseña, número de reglas, tiempos de alerta y archivos del ensayo.
- **Lectura equivocada de la revisión:** el "Parcial" de la tabla de SLO se
  refiere a los puntos únicos de falla, no a la restauración de configuraciones.
- **Pendientes reales, ahora agregados como Anexo E.13 del informe v2:**

| Punto | Corrección registrada en E.13 |
|---|---|
| **E.8 decía que las contraseñas de la tabla 4.1 "fueron rotadas y ya no son válidas"** | **Afirmación inexacta (error del asistente al redactar E.8).** Se comprobó, sin mostrar valores, que parte de esas contraseñas sigue vigente: el docente entra a las VMs con contraseña. Se rotarán al cierre de la evaluación. El informe no se publica en el repositorio |
| Sección 6: "ninguna credencial en repositorios..." | Se cumple en el repositorio (`.env` excluido, solo `.env.example`, carpeta revisada con búsqueda de patrones); no en el informe entregado al aula, por la tabla 4.1 |
| Panel de estadísticas en `10.33.199.65/haproxy?stats` (5.2 y 6) | El panel real está en `10.33.195.180:32500`, con autenticación; las métricas, en el exportador integrado `:8405` |
| logrotate (5.2, 6 y D.4) | Retención con `limpieza-logs-nodosur` (logs) y `find` dentro del script de respaldo (30 días); logrotate retirado |
| D.5 con la cuenta `xavineta2026` | El respaldo usa la cuenta de servicio `respaldo` |
| `wp_user` en la sección 6 | La base `wordpress` y las cuentas `wp_user`/`wpuser` se eliminaron; el sitio usa `lab08_db` |
| RTO de 32 s (8.5 y 9) | Los 32 s son solo de extracción; el RTO del servicio es de 3 min 50 s |
| **Registro de IA sin el "fragmento relevante"** (B, C y E.10) | Nueva tabla con los cinco campos que pide el enunciado: herramienta, propósito, fragmento relevante (saneado), validación y cambios |

No se corrigieron las tildes faltantes de la sección 8.1 ("operacion",
"maquinas", "codigo"), por la regla de no editar el texto existente.

**Verificación:** la extracción de texto del informe antes y después muestra que
todos los párrafos previos siguen idénticos (solo se agregó la entrada de E.13 al
índice). El informe v2 queda en **49 páginas**, y el PDF se regeneró.

**Auditoría de db1 hecha por Aníbal (22/11):** también de solo lectura. Coincide
con este registro: funciones críticas de db1 en "cumple" (MariaDB en
`10.33.199.68`, 98 tablas, NFS, exportadores, respaldo con 6/6 checksums y
rsyslog). Hallazgos menores ya declarados en E.9: servicios residuales de
prácticas, reglas de SSH amplias y eventos históricos en el journal, como el
respaldo que falló a las 01:17 por el `tar` de wp-content y se recuperó en las
ejecuciones siguientes. Se agrega un hallazgo nuevo: algunos conjuntos de
respaldo antiguos tienen modo `755`. No son accesibles, porque el directorio
padre es `700 root:root`, y los conjuntos nuevos ya se crean con `700`.


**Complemento (22/11, noche):**

- El equipo confirmó que en el proyecto **solo se ha usado Claude (Anthropic)**,
  lo que valida la herramienta asignada en el registro de E.13. Las dos
  revisiones recibidas el 22/11 (la revisión cruzada del informe, hecha por un
  compañero externo, y la auditoría de db1 hecha por Aníbal) se hicieron con
  **Gemini (Google)**. Se agregaron como dos filas al registro de IA de E.13,
  con su fragmento relevante, su validación y sus cambios.
- **Tildes de la sección 8.1:** a pedido del equipo, se corrigieron **solo en el
  informe v2** (8 reemplazos: "operación", "máquinas", "último", "códigos" y
  "elaboración", en el párrafo previo a las figuras y en las leyendas de las
  figuras 2 a 4). El informe original (`E01_E04_grupo08_informe.docx`) queda
  sin cambios. La comparación de texto antes y después muestra solo esas cuatro
  líneas y las dos filas nuevas. Las palabras sin tilde del Anexo D se dejaron
  así, porque son comentarios dentro de bloques de código.
- El informe v2 queda en **50 páginas**, y el PDF se regeneró.


---

## Primer ingreso de las cuentas de reemplazo · 22/11/2026

El equipo informa que las cuatro cuentas de reemplazo ya hicieron su primer
ingreso y cambiaron la contraseña temporal, como exigía `chage -d 0`:

| VM | Reemplazo (cuenta) | Primer ingreso |
|---|---|---|
| VM1 proxy1 | Matías (`mgonzalez`) | ✅ |
| VM2 web1 | Yovani (`yovani`) | ✅ |
| VM3 web2 | Matías (`mgonzalez`) | ✅ |
| VM4 db1 | Xavi (`xavineta2026`) | ✅ |

Con esto se cierra el pendiente 3 de la auditoría final. Comprobación, si se
pide en la defensa: `sudo chage -l <usuario> | head -1` muestra la fecha del
cambio. **Pendiente de seguridad declarado:** se recomendó usar en estas
cuentas una clave robusta y distinta por VM. El equipo decidió mantener la
actual durante la evaluación, con la mitigación ya documentada (UFW por
origen y cuentas nominativas).


---

## Anexo F del informe: antes y después · 23/11/2026

El docente aclaró que el informe de la Entrega 4 debe abarcar las cuatro
entregas y mostrar el antes y el después de la implementación. El informe v2
tenía el diseño de la Entrega 1 (secciones 1 a 7) y la operación de la
Entrega 4 (secciones 8 a 11 y Anexo E), pero lo construido en las Entregas 2
y 3 casi no aparecía. Se agregó al final del informe v2 el **Anexo F**, sin
modificar ninguna sección anterior (comprobado: 0 líneas originales
cambiadas):

| Sección | Contenido |
|---|---|
| F.1 | Recorrido por entrega: qué se hizo, resultado y qué motivó la etapa siguiente |
| F.2 | Antes y después por componente (17 filas), con dónde se demuestra cada uno |
| F.3 | Cada falla del incidente que dio origen al proyecto frente a la medición actual |
| F.4 | Lo que no cambió: puntos únicos de falla por el límite de cuatro máquinas |
| F.5 | Figura 16, arquitectura implementada, para comparar con la Figura 1 de la Entrega 1 |

Fuentes: el repositorio de la Entrega 2 (README y bitácora de instalación), la
bitácora de la Entrega 3 y esta bitácora. El informe v2 pasó de 50 a
**56 páginas**. El diagrama está en `capturas/E4_arquitectura_final.png`.
---

## Publicación en GitHub · 23/11/2026

Repositorio `waxoxico/lab08_nodosur`, rama `main`. Clon local en
`entrega4\repo-github\`.

| Commit | Contenido |
|---|---|
| `11ff6ef` | Entrega 3: el archivo `.env.example.` (con un punto final, un nombre que Windows no puede crear y que impedía clonar el repositorio) se renombró a `.env.example` sin cambiar su contenido, y se agregó el `.gitignore` que su README ya documentaba. Cierra el pendiente de la auditoría (sección 4) |
| `41292cf` | Entrega 4: carpeta `entrega-4/` (43 archivos) e índice por entrega agregado **al final** del README raíz, sin modificar su texto anterior |

Etiqueta **`E04`**, con el mismo formato que `E01` y `E02`. Antes del commit,
la carpeta se revisó contra los valores del archivo privado de credenciales:
ninguna clave aparece; las coincidencias son nombres de usuario, el nombre de
la base, la huella pública de la CA y palabras comunes. Se verificó con
`git ls-remote` que `main` y `E04` apuntan al commit `41292cf`.

---

## Revisión de todas las bitácoras y complementos · 23/11/2026

Para que el informe abarque las cuatro entregas sin contradicciones, se
revisaron todas las bitácoras del proyecto: las del repositorio (rama `main`
completa y todo su historial; no hay otras ramas, forks ni wiki) y las 25
copias encontradas en el equipo. Se compararon por contenido, sin contar los
saltos de línea.

| Bitácora | Resultado de la comparación |
|---|---|
| `entrega-1/decisiones.md` (E1, AD-01 a AD-08) | Idéntica a la copia local. No se había usado en el Anexo F: se agregó la sección F.5 |
| `bitacora-contribuciones.md` (E2) y `entrega-1/bitacora-e1.md` | Idénticas entre sí: la segunda es una copia de la primera, que es de la Entrega 2 |
| `bitacora-instalacion.md` (E2) | Solo existe en el repositorio; usada en el Anexo F |
| `entrega_3/bitacora-entrega-3.md` | Idéntica a las copias de octubre. La versión de trabajo del 16/11 tenía dos secciones más, que no se habían subido |
| Borradores de la E3 (`Downloads\TAS`, cuatro versiones de octubre) | Todo su contenido está en la versión final; las diferencias son títulos renombrados |
| `contexto-monitoreo-haproxy.md` (sesión del 16/11) | Ya cubierto por la tabla de incidentes de esta bitácora. Contiene claves: no se publica |
| Esta bitácora | Copia saneada idéntica en el repositorio |

**Complementos aplicados, todos agregando y sin modificar texto existente:**

| Dónde | Qué |
|---|---|
| Informe v2, Anexo F | **F.5** contrasta las ocho decisiones de la Entrega 1 con la implementación (seis se mantuvieron, AD-02 cambió y AD-05 se corrigió). **F.6** completa las contribuciones por integrante de la Entrega 3, que no estaban en el informe (el Anexo A cubre E1 y E2, y E.12 la E4). El diagrama pasa a F.7. El informe queda en **57 páginas**, con 0 líneas originales cambiadas |
| Informe v2, F.2 | La fila «Restauración» se precisó contra `evidencias/ensayo-restauracion.txt` de la Entrega 2: aquel ensayo verificó un pedido y la URL del sitio por consulta, pero no el CMS funcionando |
| Repositorio, `entrega_3/bitacora-entrega-3.md` | Se agregaron al final las secciones «Cierre de la Entrega 3» y «Hacia la Entrega 4», con una nota; el texto entregado quedó intacto (commit `753b291`) |
| Repositorio, etiqueta **`E03`** | Creada sobre `cf30198`, el último commit de la Entrega 3. Era un pendiente anotado al cierre de esa entrega |
| Repositorio, `README.md` | El índice por entrega indica la etiqueta `E03` (commit `f6850f0`) |

Las etiquetas quedan así: `E01`, `E02`, `E03` y `E04`, una por entrega.
---

> **Nota de la copia publicada en GitHub:** en esta copia se reemplazaron por
> `[clave omitida]` tres contraseñas antiguas del texto original (líneas 104,
> 651 y 950). Esas claves ya fueron rotadas y hoy se leen desde un `.env` que no
> se versiona (ver `monitoreo/.env.example`). El texto restante es idéntico a la
> bitácora entregada.
