# Auditoría Entrega 4 · Nodo Sur · Grupo 08

Revisión hecha como profesor: se revisa y no se corrige. **No se cambió nada en ninguna máquina.**
Material revisado: enunciado, rúbrica (Excel), informe E01_E04 (docx), bitácora 3, bitácora 4, informe de restauración, runbook, guía de defensa, configuraciones del zip, más pruebas de red, HTTPS y DNS de solo lectura hechas desde el PC del alumno (21/11/2026).
**Actualización (22/11/2026, 00:48–00:50 UTC):** el alumno ejecutó un script de solo lectura en las 4 VMs (proxy1, web1, web2, db1). Las salidas están en `entrega4/*.txt`. Los resultados están en la **sección 8**, que manda sobre los "verificar" de las secciones anteriores.

---

## 1. Nota estimada por criterio (rúbrica E4)

| # | Criterio | Peso | Nivel probable | Motivo principal |
|---|---|---|---|---|
| 1 | Cobertura de monitorización | 15 | **80** | Confirmado en VM1: 8/8 targets `up` y 9 reglas `ok`. Falta el panel "antes, durante y después" (evidencia mínima, marcada Pendiente). Los dashboards son genéricos importados. La latencia es solo `connect_time` |
| 2 | Alertas y escalamiento | 15 | **60–80** | Reglas bien hechas, pero el correo llegó **7,5 min** después de la falla, por sobre la meta de 5. No se repitió la prueba tras el arreglo. El canal es un buzón local en VM1. El escalamiento a un segundo responsable no se puede ejecutar, porque **esa persona no tiene cuenta en la VM** (sección 8) |
| 3 | Logs, tiempo y trazabilidad | 10 | **60–80** | Logs centralizados de las 4 VMs en UTC, confirmado. La retención de 30 días **no funciona como está escrita**: ya aparecen archivos vacíos recreados (sección 8) |
| 4 | Backup y retención | 15 | **80** | Confirmado: el timer ejecutó solo (21/11 03:04), hay 5 conjuntos y los checksums dan OK **también en el destino**. Brechas: falta la config de VM2/VM3 y parte de la de VM1, el `rsync --delete` hace espejo y depende de una cuenta personal |
| 5 | Restauración y RPO/RTO | 20 | **60–80** | Datos identificables recuperados con marcas de tiempo. No se validó el CMS funcionando sobre la base restaurada ni se restauró la configuración. El RTO medido es solo la extracción de datos |
| 6 | Correo/relay y automatización | 10 | **80** | Postfix no expuesto (confirmado: el 25 está cerrado desde fuera). Timer de systemd controlable. Imágenes `:latest` |
| 7 | Runbook y demostración | 15 | **80** | Runbook bien estructurado, pero no trae procedimiento de restauración **a producción** ni de reconstrucción de VM1, y afirma tiempos no medidos ("+30 s llega el correo"). Demo pendiente |

**Estimación global: unos 72–78 / 100**, si la demo sale bien. Los puntos que más bajan la nota están en las secciones 2, 3 y 8.

---

## 2. Hallazgos críticos (un profesor los detecta de inmediato)

### 2.1 Contradicción en el tiempo de detección y notificación
- El informe (sección 11) dice: *"alerta verificable que alcanza al responsable designado en menos de dos minutos"*.
- La propia bitácora 4 dice: falla a las 22:52:56, `firing` a las 22:54:09, **correo entregado a las 23:00:30**. Son 7 min 34 s, más que la meta de 5 min.
- El "73 s" mide el `firing` en Prometheus, no la recepción. El criterio pide una *"alerta recibida"* y la meta habla de *"alerta verificable"*.
- Después de abrir el puerto 25 **no se repitió el ensayo** de punta a punta. El runbook y la guía prometen "+30 s" sin medición que lo respalde.

### 2.2 Credenciales en los documentos
- **Informe E01_E04, tabla 4.1:** usuarios y contraseñas reales de las 4 VMs ([claves omitidas en esta copia]). Dice que se incluyen "por requerimiento del docente". Si es así, que no lleguen a GitHub. Además contradice la sección 6 del mismo informe ("ninguna credencial se incluye...") y la regla del enunciado.
- **Bitácora 4:** expone las claves del panel de HAProxy y de Grafana [omitidas en esta copia]. La bitácora irá al repositorio, y eso es una infracción directa de *"No incluir claves... en repositorios"*.
- Las contraseñas débiles siguen vigentes: la propia bitácora lo declara como pendiente arrastrado desde la E3.

### 2.3 Estado declarado inconsistente
- La bitácora 4 marca "Panel antes, durante y después" como **Pendiente**, pero la tabla final pone los 7 criterios como **Hecho**. La guía de defensa dice "La implementación está completa y verificada".
- El "Hallazgo: credencial en texto plano en el compose" figura **Pendiente**, pero el `compose.yaml` del zip ya usa `${HAPROXY_STATS_PASS}`. Hay que **verificar en VM1** cuál es el real. Si el de la máquina sigue con la clave escrita, el zip no representa la implementación.
- Informe 8.5: *"Los cuatro archivos del conjunto superaron la comprobación"*. Pero el respaldo usado (`20261120-223742`) tenía **3 archivos**; config-proxy1 se agregó después.
- El título de la entrada de prueba dice "23:05", pero `post_date_gmt` es 22:37:01. Es una evidencia de identidad confusa.

### 2.4 La retroalimentación de la Entrega 1 no se aplicó en el informe consolidado
| Retroalimentación E1 | Estado en E01_E04 |
|---|---|
| Corregir la subred administrativa | Sigue diciendo **10.33.195.0/25** (sección 3.2), pero las IP reales (.170, .175, .180, .234) están en **10.33.195.128/25** |
| Aclarar el acceso SSH ("se niega el acceso desde administración a nodos que deben administrarse por esa red") | Sigue diciendo que VM2–VM4 "no son alcanzables desde la red de administración". **Verificado desde el PC:** el puerto 22 está abierto en .234, .170 y .175, así que el texto contradice la realidad |
| Desagregar RNF-04 / medición de disponibilidad 99,5 % | Sigue pendiente (se declara "Parcial") |
| Solución concreta de reservas, licencias y costos | No aparece |
| BD y persistencia antes de validar WordPress (orden del plan) | El plan 3.3 sigue con WordPress (etapa 4, 11/09) antes que MariaDB/NFS (etapa 6, 23/10) |
| Cuantificar concurrencia, memoria y alertas | Sin cuantificar contra la demanda |

Además quedan secciones desactualizadas frente a lo implementado:
- 5.2 cita el panel `http://10.33.199.65/haproxy?stats`, cuando el real está en `10.33.195.180:32500`.
- 6 dice "logs centralizados en /var/log/syslog", "wp_user limitado a la base wordpress" y "rotación vía logrotate" de respaldos. En realidad es `admin@lab08_db`, respaldo con script y rsyslog.
- 4.1 usa hostnames `dnshaproxy` y `mariadbnfs`, mientras el runbook y las bitácoras usan `proxy1` y `db1`.

---

## 3. Hallazgos técnicos por criterio

### 3.1 Monitorización
- Ocho targets declarados. **Verificar en VM1** que estén `up` y que las 9 reglas estén cargadas.
- Faltan métricas de contenedores (cAdvisor estaba listado como faltante y no se agregó). No hay latencia de respuesta de la aplicación ni un sondeo de punta a punta tipo blackbox del sitio por HTTPS. Sí cubre la saturación del host.
- `haproxy-exporter` sigue corriendo sin uso. Es redundante y aumenta la superficie, porque lleva la contraseña del panel.
- Retención de Prometheus: 15 días, frente a 30 días de logs y respaldos. No está justificado.

### 3.2 Alertas
- **El canal de notificación es un buzón local en VM1.** Para enterarse, alguien tiene que entrar por SSH y leer `/var/mail`. En la práctica depende de que alguien mire, que es justo lo que la rúbrica penaliza. Además, si cae VM1 no llega ninguna alerta: Prometheus, Alertmanager y Postfix viven ahí, y la alerta `MaquinaSinResponder` no sirve para VM1.
- "Responsable" es un equipo (`equipo-infraestructura`), no la persona del runbook. Las dos rutas llegan al mismo buzón (declarado). `equipo-app@...` depende de un alias: **verificar `/etc/aliases`** en VM1.
- No hay alerta sobre la latencia ni sobre el certificado TLS (vence en 2027, pero no se vigila).
- No hay alerta de punta a punta sobre el sitio. `TodosLosBackendsCaidos` no detecta una falla de HAProxy en sí, porque si HAProxy cae el exportador `:8405` también cae y solo dispara `ExportadorSinDatos` (severidad *aviso*, no crítica).

### 3.3 Backup (`respaldo-nodosur.sh`)
- **Paso 3 (config de VM4):** no tiene `|| fallo` y además lleva `2>/dev/null`. Es exactamente el patrón que la bitácora critica del cron viejo de VM2.
- **Paso 3b (config de VM1):** si falla, solo registra un AVISO y la métrica igual marca el respaldo como exitoso.
- **No respalda la configuración de VM2/VM3:** compose, `.env`, `docker-user-rules`, fstab, netplan. El criterio pide la configuración de la plataforma.
- `rsync -a --delete-after` replica **en espejo**: si se borra o daña `/var/backups/nodosur` en VM4, la próxima ejecución lo borra también en VM1. No es una copia independiente con retención propia.
- El checksum se calcula y se verifica en el mismo instante en el origen. No se comprueba en el destino después del rsync.
- La copia y la llave dependen de la **cuenta personal `xavineta2026`**, con destino en su home y regla sudo a su nombre. Eso choca con "accesos nominativos y revocables": si se revoca a Xavi, se rompe el respaldo. Lo correcto sería una cuenta de servicio.
- La regla sudo permite que root de VM4 lea la **llave privada TLS** (`/etc/ssl/haproxy`) y el `.env` del monitoreo. Es aceptable si se declara, pero no está analizado.
- La métrica `.prom` se escribe sin reemplazo atómico (menor).
- Confirmar en VM4 que el script instalado es igual al del zip y que el timer ya ejecutó al menos una vez a las 03:00 por sí solo. Hasta ahora la evidencia solo muestra ejecuciones manuales del 20/11.

### 3.4 Logs
- **La retención probablemente no funciona:** cada archivo es `<fecha>.log` con nombre único, así que `rotate 30` cuenta generaciones *por archivo* y nunca borra días viejos. Además, `create` vuelve a crear archivos vacíos. Haría falta `maxage 30` o un `find -mtime`. **Verificar en VM1** (`ls /var/log/nodosur/*`).
- Transporte TCP sin TLS y `%HOSTNAME%` tomado del mensaje, que se puede falsificar. Ambos son menores en un laboratorio aislado, pero no están declarados.
- La correlación está demostrada con un solo `grep`. Está bien, pero no existe una consulta guardada ni un ejemplo vinculado al ensayo de degradación (logs de HAProxy, VM3 y Alertmanager en una sola línea de tiempo).

### 3.5 Restauración y RPO/RTO
- Bien: marcas creadas antes del respaldo, checksum previo, restauración en `restore_test` y en `/tmp`, y la falla silenciosa del primer intento documentada.
- **Falta la integridad funcional del CMS** (el enunciado lo pide explícitamente): no se levantó WordPress apuntando a `restore_test`. Solo hubo `COUNT` y `SELECT`.
- **La configuración no se restauró** ni se verificó su contenido en el ensayo.
- La restauración se hizo **en la misma instancia MariaDB productiva**, con `DROP DATABASE` sobre ese servidor. Es aceptable, pero no es un "ambiente de prueba" separado.
- El "RPO 0 s" sale de respaldar 41 s después de crear el dato. No es una medición útil (lo aclaran a medias). El RTO de **servicio web** no se midió: 32 s es solo la extracción.
- Durante el ensayo se **cambió la zona horaria de WordPress en producción**, pero el informe dice "no alteró el ambiente productivo". Ese cambio debería figurar como cambio con su reversión.
- Verificar en VM4 que se limpiaron `restore_test` y `/tmp/restore_files`.

### 3.6 Correo y automatización
- Postfix: **verificar** `mynetworks` y `smtpd_relay_restrictions`. Escuchar en 172.18.0.1 no basta: cualquier contenedor de esa red puede retransmitir correo.
- Imágenes del monitoreo con `:latest`: no son reproducibles (pendiente arrastrado).
- El cron obsoleto de VM2 se declara retirado. Verificar en VM2 y VM3 que tampoco está en VM3.
- Unidades fallidas en VM1 (`degraded`) "sin revisar": es mala señal para la E5.

### 3.7 Runbook
- Restaurar a producción: solo existe la restauración a `restore_test`. Falta el paso a `lab08_db`, el modo mantenimiento y la validación del sitio.
- No hay procedimiento para "VM1 caída" ni para reconstruir VM1 desde `config-proxy1.tgz`, que es el SPOF más serio.
- No hay procedimientos para las alertas `CpuAlta`, `RespaldoNoEjecutado` ni `RespaldoDemasiadoPequeno`, aunque el texto dice "cada alerta tiene su procedimiento".
- La guía de defensa pide `systemctl is-active named apache2` "en VM1". ¿Apache en VM1? Revisarlo.

---

## 4. Documentación y forma
- **Bitácora de contribuciones por integrante:** el Anexo A solo cubre actividades de E1/E2. En la E4 no queda claro quién hizo qué (la bitácora dice "otro integrante"). El enunciado lo exige en **cada** entrega.
- **Registro de IA:** a la tabla de la bitácora 4 y al Anexo C les falta la *herramienta* (en la bitácora), el *fragmento relevante* y los *cambios aplicados*. Son los campos que exige el enunciado. El texto tiene marcas claras de redacción asistida ("Se pidió una evaluación exigente..."). Revisé el detector del "párrafo sobre amarillo": **no aparece en ningún documento**, así que está bien.
- **Repositorio:** según la propia bitácora, falta subir `entrega-4`, los archivos ocultos (`.gitignore`) y la etiqueta de versión. También hay que corregir el `.env.example.` con un punto de más.
- **Nombres de archivo:** `runbook.md`, `informe-restauracion.md` y los demás no siguen el formato `E04_grupo08_descripcion.ext` que pide el enunciado.
- **El Excel de rúbricas es inconsistente:** la hoja Resumen pondera la E4 al 20 %, mientras la hoja E4 y el enunciado dicen 25 %. Es para tenerlo presente, no es error del grupo.

---

## 5. Verificado desde este PC (solo lectura)

| Prueba | Resultado | Juicio |
|---|---|---|
| DNS `www.lab08.nodosur.cl` @10.33.195.180 | 10.33.195.180 | OK |
| HTTP :80 | 302 → https | OK |
| HTTPS :443 | 200, `x-backend: web2` | OK. Expone `server: Apache/2.4.69 (Debian)` (menor) |
| Certificado | SAN www, raíz e IP; vence el 22/10/2027 | OK |
| Grafana :3000 | HTTPS 200; HTTP rechazado (400) | OK |
| Panel de stats :32500 | Accesible desde la VPN, 401 sin credenciales | OK, pero con contraseña débil |
| :9090 :9093 :9100 :9101 :8405 :5514 :25 en VM1 | Cerrados desde la red de administración | OK |
| :80 :3306 :9100 :9104 en VM2–VM4 (red adm.) | Cerrados | OK |
| :22 en VM2–VM4 (red adm.) | **Abiertos** | Correcto en la práctica, pero **contradice el informe 3.2** |

---

## 6. Qué queda por verificar dentro de las VMs (script de solo lectura listo)
VM1: targets y reglas en Prometheus, compose real (¿clave escrita?), `mynetworks` de Postfix, aliases y buzones, árbol `/var/log/nodosur`, copia en `~xavineta2026/respaldos`, unidades fallidas.
VM2/VM3: restart policy de los contenedores, cron obsoleto retirado, NFS montado, `DOCKER-USER`.
VM4: el timer ya ejecutó solo, el script instalado es igual al del zip, `sha256sum -c` del último respaldo, contenido de `config-proxy1.tgz`, restos de `restore_test` y `/tmp/restore_files`, grants de `exporter`, zona horaria de WP.

---

## 7. Prioridad sugerida antes de presentar (el grupo decide; aquí no se toca nada)
0. **(Agregado tras revisar las VMs)** Asegurar que el `compose.yaml` y el script del zip sean **los mismos** que corren en las máquinas. Preparar una respuesta honesta sobre cuentas compartidas, SSH por contraseña y el escalamiento sin cuentas (sección 8.2, puntos 1 y 3 a 5).
1. Sacar las contraseñas de la bitácora 4 y decidir qué hacer con la tabla 4.1 del informe antes de subir a GitHub.
2. Repetir la degradación con captura del panel antes, durante y después, midiendo **hasta la recepción del correo**, y corregir "menos de dos minutos".
3. Alinear los estados (Pendiente / Hecho) y los números (3 o 4 archivos) entre bitácora, informe y guía.
4. Aplicar la retroalimentación E1 en el informe consolidado (subred, SSH, orden del plan, RNF-04, reservas).
5. Agregar la bitácora de contribuciones E4 por integrante y completar el registro de IA.
6. Preparar respuestas para la defensa: buzón local como canal, VM1 como SPOF del monitoreo, espejo rsync, config de VM2/VM3 sin respaldo, CMS no validado tras restaurar, retención de logrotate.

---

## 8. Verificación dentro de las VMs (solo lectura, 22/11 00:48–00:50 UTC)

### 8.1 Lo que está BIEN (confirmado en la implementación)
| Qué | Evidencia |
|---|---|
| Hora | Las 4 en UTC, `System clock synchronized: yes` |
| Monitoreo | 8/8 targets `up`; 9 reglas en 3 grupos, todas `ok`/`inactive`; sin alertas activas |
| Métrica de respaldo | 6,3 h desde el último respaldo; 79,9 MB (sobre el umbral de 50 MB) |
| Aislamiento del stack | Prometheus en `127.0.0.1:9090`, Alertmanager en `127.0.0.1:9093`; Postfix solo en `127.0.0.1` y `172.18.0.1` |
| Grafana | HTTPS 200, `/api/health` ok; llave `472:root` con modo `640` |
| Respaldo automático | `respaldo-nodosur.timer` habilitado; **ejecución automática el 21/11 a las 03:04:17**, exit 0; próxima 22/11 03:02 |
| Inventario de respaldos | 5 conjuntos en VM4 y los mismos 5 en VM1; el último tiene 4 archivos y `sha256sum -c` da OK **en origen y en destino** |
| Contenido | El dump tiene 98 `CREATE TABLE` y la entrada de prueba; `config-proxy1.tgz` incluye `haproxy.cfg`, `named.conf.local`, `compose.yaml`, `prometheus.yml` y `alert.rules.yml` |
| Limpieza del ensayo | `restore_test` ya no existe; `/tmp/restore_files` tampoco |
| Zona horaria de WP | `timezone_string = America/Santiago`; la entrada ID 20 tiene `post_date_gmt 22:37:01` |
| Logs | Árbol `/var/log/nodosur/` con proxy1, web1, web2 y db1, con líneas de hace segundos en las 4 |
| Nodos web | Contenedores `healthy`, `restart=unless-stopped` en ambos (cierra el pendiente "política de reinicio de VM2"); NFS v4.2 montado; regla `DOCKER-USER` activa; Apache nativo inactivo; `.env` en `600` |
| Cron obsoleto | No hay crontab de root en web1, web2 ni proxy1 |
| MariaDB | Escucha solo en `10.33.199.68:3306`; `exporter` con `SLAVE MONITOR` (corrección aplicada) |
| Copia remota | Llave `backup-db1` en VM1; logins por llave desde `10.33.199.68` a las 03:04 y 18:30 |

### 8.2 Lo que está MAL o contradice la documentación
1. **El `compose.yaml` real no es el del zip.**
   - En `/srv/monitoring` **no existe ningún `.env`**, y el comentario de la línea del exportador es distinto al del zip.
   - Por lo tanto, en la máquina las contraseñas (panel de HAProxy y admin de Grafana) siguen **escritas en el compose**. Además el archivo es legible por todos (`664`), igual que `compose.yaml.bak`.
   - El zip entrega una configuración "saneada" que **no es la que corre**. La rúbrica E5 penaliza que la documentación *"contradiga la implementación real"*.
   - Tampoco calzan los tamaños: script de respaldo 2794 B en la VM contra 3147 B en el zip; compose 2173 contra 2278; alertmanager 787 contra 1243. Pueden ser solo comentarios, pero no están verificados como iguales.
2. **`haproxy.cfg` tiene la clave del panel (`stats auth`) en texto plano.** Contraseña trivial, en texto plano, y además copiada en cada respaldo (`config-proxy1.tgz`).
3. **No hay cuentas nominativas y se comparte la cuenta de administración.**
   - Cada VM tiene **un solo usuario humano**: xavineta2026, mgonzalez, yovani o anibal.
   - En VM1 hay ingresos como `xavineta2026` desde **6 IP de VPN distintas** (10.30.248.3, .10, .11, .23, .28) y saltando desde db1. Todo indica que varios integrantes usan la cuenta de Xavi; esta misma auditoría entró así.
   - Eso contradice la meta *"Accesos nominativos, revocables"* del informe 4.2 y el criterio E2 *"se comparten cuentas"*.
4. **El escalamiento del runbook no se puede ejecutar.** El segundo responsable de VM2 es Yovani, pero en web1 solo existe `mgonzalez`. El de VM4 es Xavi, pero en db1 solo existe `anibal`. Lo mismo con Matías en VM1 y VM3. Sin cuenta propia, el "si no responde en 15 min actúa el segundo" queda solo en el papel.
5. **El SSH se usa con contraseña en las 4 VMs** (`Accepted password`, incluido un `Failed password` en db1). El informe 5.2 afirma acceso *"exclusivo vía SSH nominativo con llaves criptográficas"*. Es falso en la implementación.
6. **La retención de logs está mal implementada (confirmado).** En web1, web2 y db1 ya existe `2026-11-20.log` **vacío, recreado por `create`**, junto a `2026-11-20.log-20261122`. Cada día genera nombres nuevos, así que `rotate 30` nunca borra nada: la retención efectiva es infinita, no 30 días.
7. **Servicios sobrantes en db1 (VM4), el servidor de datos:**
   - `apache2` escuchando en `*:80`, un resto de la E2.
   - **otro `prometheus` nativo** en `*:9090`, no documentado.
   - `uvicorn` en `127.0.0.1:8000`, una aplicación desconocida.
   - la pila NFSv3 completa (`rpcbind`, `rpc.mountd` y `rpc.statd` en puertos dinámicos).

   UFW los bloquea (desde el PC el 80 aparece cerrado), pero es superficie y consumo innecesarios, y nada de esto figura en el inventario.
8. **Unidades fallidas, sistema `degraded`:**
   - **db1:** `prometheus-mysqld-exporter.service not-found failed`, un resto del incidente del exportador duplicado, y `openipmi`.
   - **proxy1:** `fwupd` y `fwupd-refresh`.

   La bitácora deja "unidades fallidas sin revisar" como pendiente, pero en db1 la causa es el propio trabajo de la E4.
9. **UFW de db1 con reglas sin documentar o inútiles:**
   - `22/tcp` desde `10.33.117.60` y `10.33.126.205` (IP sueltas);
   - `9104/tcp` desde `10.33.199.68` (la propia máquina);
   - `111` desde `10.33.199.64/29` (pendiente H15 de la E3, aún sin retirar).
10. **Restos de la base anterior:** siguen la base `wordpress` y las cuentas `wp_user@.66`, `wp_user@.67` y `wpuser@localhost`. Son cuentas válidas que nadie usa (pendiente desde la E3).
11. **Respaldo de configuración incompleto (confirmado):**
    - Los conjuntos de VM4 y VM1 no incluyen `/etc/ufw`, `/etc/rsyslog.d`, `/etc/logrotate.d`, `/etc/postfix`, las unidades systemd (ni la del propio respaldo), `/etc/sudoers.d` ni netplan de VM1.
    - De VM2 y VM3 no se respalda nada: compose, `.env`, `docker-user-rules`, fstab.
12. **Las tareas antiguas de alerta por `wall` siguen activas** (`* * * * * check_haproxy_status.sh`, crontab de xavineta2026). No es grave, pero es una automatización no inventariada en la E4.
13. **El permiso de `exporter` es amplio:** `SELECT ON *.*` le da lectura de todas las tablas, incluidos los hashes de `wp_users`. Es el permiso estándar del exportador, pero no está justificado.
14. **Observación en web2:** a las 00:47:37 hubo un `UFW BLOCK` de respuestas desde `10.33.195.180:443` hacia `10.33.195.170`. Indica que alguna petición de web2 al sitio (por ejemplo, el loopback de WordPress o wp-cron) sale por una interfaz y la respuesta llega por otra. Conviene revisarlo para la E5.

### 8.3 Pendientes de la bitácora que se confirman como abiertos
Contraseñas débiles (panel de HAProxy); imágenes `:latest` en las 4 del monitoreo; `haproxy-exporter` redundante sigue corriendo; regla `111` en db1; restos de `wordpress`, `wp_user` y `wpuser`; retención de Prometheus de 15 días.

### 8.4 Pendientes que se confirman como cerrados
El timer ejecuta solo; la copia remota se verifica íntegra; la limpieza del ensayo está hecha; el cron obsoleto fue retirado; la política de reinicio de los contenedores está aplicada; la zona horaria de WP está corregida; proxy1 ya escribe en el árbol central.


---

## 9. Estado tras las correcciones (22/11/2026, 01:01–02:13 UTC)

> Esta sección **se agrega** a la auditoría. Lo anterior describe el estado
> encontrado a las 00:48 y se conserva tal cual. Aquí se registra, hallazgo por
> hallazgo, qué se corrigió y cómo se verificó. Detalle en
> `bitacora-entrega-4.md`, sección "Sesión de correcciones posterior a la
> auditoría". **Nota de esta copia:** se omitieron las claves antiguas citadas
> en las secciones 2.2 y 8.2. Ya no son válidas, porque se rotaron.

### 9.1 Hallazgos y su estado

| Hallazgo (sección) | Estado | Verificación |
|---|---|---|
| Claves escritas en el compose real; el zip no coincidía (8.2-1) | ✅ Corregido (paso 1) | `.env` 600; compose con variables y 640; clave vieja → 401; targets `up`; ingreso a Grafana con la clave nueva |
| Clave del panel de HAProxy trivial y `haproxy.cfg` 644 (8.2-2) | ✅ Corregido (paso 1) | Clave rotada; `root:haproxy 640`; `haproxy -c` válido |
| Retención de logs que no borraba nada (3.4 y 8.2-6) | ✅ Corregido (paso 2) | Script y timer a las 03:30; vacíos eliminados; día 20 comprimido; ejecución registrada en el log central |
| Respaldo sin configuración de VM2/VM3 y parcial de VM1 (3.3 y 8.2-11) | ✅ Corregido (paso 3) | 4 configuraciones respaldadas (225 / 264 / 401 / 401 archivos) |
| Copia en espejo (`--delete`) (3.3) | ✅ Corregido (paso 3) | Sin `--delete`; retención independiente en origen y destino |
| Checksum solo en origen (3.3) | ✅ Corregido (paso 3) | `sha256sum -c` en el destino dentro del script; captura `E4_respaldo_checksum_proxy1.png` |
| El respaldo dependía de la cuenta personal de Xavi (3.3) | ✅ Corregido (paso 3) | Cuenta de servicio `respaldo`; llave limitada a la IP de db1; sudo limitado a un `tar`; un `tar` no autorizado se rechaza; la llave antigua fue retirada (código 255) |
| Errores silenciados (`2>/dev/null`) en el paso de configuración (3.3) | ✅ Corregido (paso 3) | Función `aviso()`, métrica `respaldo_avisos` y alerta `RespaldoIncompleto` (10 reglas) |
| **Fallo latente nuevo:** `tar` con código 1 abortaba el respaldo | ✅ Corregido (paso 3) | Detectado en la primera ejecución (01:17:44); código 1 → nota; código ≥ 2 → fallo |
| CMS no validado tras restaurar (3.5) | ✅ Corregido (paso 4) | WordPress temporal sobre lo restaurado: producto ID 20 por REST, `wc/v3`, archivo de marca; **RTO del servicio de 3 min 50 s** |
| Configuración no restaurada en el ensayo (3.5) | ⚠️ Parcial | La configuración ya se respalda y su contenido se listó, pero no se restauró en un ensayo |
| Escalamiento no ejecutable (8.2-4) | ✅ Corregido (paso 5) | Cuentas de reemplazo en las 4 VMs, con cambio de contraseña obligatorio |
| Cuenta compartida en VM1 (8.2-3) | ✅ Corregido (paso 5) | Matías tiene su cuenta en VM1. **Pendiente:** primer ingreso de cada reemplazo |
| db1 en `degraded` (8.2-8) | ✅ Corregido (paso 6) | `running`, sin unidades fallidas |
| Restos de la base y cuentas sin uso (8.2-10) | ✅ Corregido (paso 6) | Respaldo en `/root` y `DROP`; web1 y web2 confirmados con `admin` y `lab08_db` |
| UFW de db1 con reglas sobrantes (8.2-9) | ✅ Parcial (paso 6) | Se retiraron `111` y `9104` desde la propia máquina; las dos IP sueltas de SSH quedan como riesgo residual |
| Notificación a 7 min 34 s, sin repetir (2.1) | ✅ Corregido (paso 7) | Nueva medición: **correo entregado a 1 min 51 s** de la falla |
| Faltaba el panel antes, durante y después (1) | ✅ Corregido (paso 7) | Capturas `E4_antes`, `E4_durante` y `E4_despues` en Explore (UTC) |
| Eventos de HAProxy fuera del almacén central (hallazgo del paso 7) | ⏳ En curso | Renumerar `91-` → `45-nodosur-local.conf` en VM1 |
| SSH con contraseña (8.2-5) | ➖ Se mantiene **por criterio del docente** | Mitigado con UFW; corrección del texto del informe en el capítulo de actualización |
| Servicios de prácticas de Aníbal en db1 (8.2-7) | ➖ Riesgo residual declarado | No se tocaron porque no se confirmó su dueño; UFW los bloquea |
| Claves antiguas escritas en los textos originales (2.2) | ➖ Se conservan por la regla de no modificar lo existente | Ya no son válidas (rotadas). **Recomendación:** no publicar esos archivos originales en el repositorio, o publicarlos saneados |

### 9.2 Incidente real detectado durante la sesión

Entre las **00:39 y las 01:52 UTC**, web1 no sirvió la portada: una operación
`unlink` sobre `wp-content/languages` (NFS) quedó colgada y bloqueó la carpeta.
Ninguna alerta lo detectó, porque `health.php` no carga WordPress ni el NFS, y
con `timeout server 10m` no hubo 5xx. Se corrigió con un `docker restart` de
web1 y se verificó. Es la materialización de un riesgo que ya declaraba la
bitácora 3 (montaje `hard`), y demuestra un punto ciego de la observabilidad
con su mejora propuesta (`runbook.md` §15).

### 9.3 Nota estimada después de las correcciones

| # | Criterio | Peso | Antes | Ahora (estimado) | Qué sostiene el cambio |
|---|---|---|---|---|---|
| 1 | Cobertura de monitorización | 15 | 80 | **80–100** | Panel antes, durante y después; 8 targets y 10 reglas. Sigue sin métrica de latencia de aplicación (el incidente lo demostró) |
| 2 | Alertas y escalamiento | 15 | 60–80 | **80–100** | Notificación a 1 min 51 s, con correo y recuperación evidenciados; responsables con cuenta; control de ruido evidenciado (`pending` sin correo a las 01:52). Límite: buzón local en VM1 |
| 3 | Logs, tiempo y trazabilidad | 10 | 60–80 | **80–100** | Retención real; secuencia de 3 fuentes y 2 máquinas en UTC; incidente reconstruido con `dmesg` y `/proc` |
| 4 | Backup y retención | 15 | 80 | **100** | 4 VMs; destino separado no espejo; checksum en origen y destino; cuenta de servicio; métrica y alerta de respaldo incompleto |
| 5 | Restauración y RPO/RTO | 20 | 60–80 | **80–100** | CMS validado sobre lo restaurado, con producto, WooCommerce y archivo; RTO del servicio medido con marcas de tiempo |
| 6 | Correo/relay y automatización | 10 | 80 | **80–100** | Correo entregado y verificado; timers idempotentes y registrados; claves fuera de los archivos |
| 7 | Runbook y demostración | 15 | 80 | **80–100** | Procedimientos de restauración a producción, del incidente real, de respaldo y de escalamiento; la nota final depende del dominio del equipo en la defensa |

**Estimación global: unos 85–95 / 100.** Llegar a 100 depende sobre todo de la
**demostración en vivo y del dominio individual** (criterio 7) y de cómo el
docente pondere los límites declarados: buzón local, punto ciego de latencia y
SSH con contraseña.


---

## 10. Evaluación final contra la rúbrica de la Entrega 4 (22/11/2026, 05:15 UTC)

> Se agrega a lo anterior. Evaluación hecha como docente, con la evidencia
> verificada en las máquinas durante la sesión. La nota real depende del
> criterio del evaluador y de la demostración en vivo.

| # | Criterio (peso) | Lo que exige el 100 según la rúbrica | Evidencia verificada | Brechas que un evaluador estricto puede marcar | Nivel estimado |
|---|---|---|---|---|---|
| 1 | **Cobertura de monitorización** (15) | Proxy, backends, DB y hosts con señales de disponibilidad, latencia, errores, saturación y capacidad vinculadas a decisiones | 8 targets `up` (HAProxy integrado y CSV, node en las 4 VMs, mysqld); 3 dashboards; métrica de salud de respaldos; panel antes, durante y después en Explore (UTC) | La latencia es solo `connect_time`; no hay señal del servicio de punta a punta (el incidente de web1 lo demostró); sin métricas de contenedores | **80** |
| 2 | **Alertas y escalamiento** (15) | Reglas con umbral, duración, severidad, responsable y canal; recepción y recuperación probadas sin ruido excesivo | 10 reglas completas; correo `FIRING` a 1 min 51 s y `RESOLVED` recibidos; ruteo por responsable; control de ruido evidenciado (`pending` sin correo a las 01:52); responsables con cuenta nominativa | El canal es un buzón local en VM1, que es punto único de falla; no hay alerta de latencia | **100** (riesgo de 80) |
| 3 | **Logs, tiempo y trazabilidad** (10) | Logs consultables, hora consistente, origen, retención y correlación para reconstruir eventos | rsyslog central con las 4 VMs, incluido HAProxy; todo en UTC; retención de 30 días verificada; secuencia reconstruida con 3 fuentes y 2 máquinas; incidente reconstruido con `dmesg` y `/proc` | Transporte sin TLS (red interna) | **100** |
| 4 | **Backup y retención** (15) | Automatiza DB, archivos y configuración; retención, destino separado y verificación de integridad | Ejecución automática del timer (03:01, `avisos: 0`); 4 configuraciones; checksum en origen y destino; copia no espejo; cuenta de servicio con mínimo privilegio; métrica y alerta | El destino separado está en el mismo host de Proxmox (declarado) | **100** |
| 5 | **Restauración y RPO/RTO** (20) | Restaura datos identificables en ambiente controlado, valida función e integridad y mide RPO/RTO con marcas de tiempo | Restauración en `restore_test` + WordPress temporal; producto ID 20 por REST, WooCommerce cargado, archivo de marca servido; RTO del servicio de 3 min 50 s; limpieza verificada | La configuración no se restauró en un ensayo; la restauración a producción solo está documentada | **100** (riesgo de 80) |
| 6 | **Correo/relay y automatización** (10) | Notificaciones seguras; tareas idempotentes, registradas y controlables | Postfix solo en 127.0.0.1 y en la red de Docker; entrega verificada en `mail.log`; timers de systemd con log; scripts que se pueden reejecutar | `mynetworks` permite que cualquier contenedor de esa red use el relay; SMTP sin TLS (laboratorio) | **100** (riesgo de 80) |
| 7 | **Runbook y demostración** (15) | Runbook con síntomas, evidencia, responsables, escalamiento, validación y reversión; demostración con dominio | Runbook de 21 secciones (incluidos el incidente real, la restauración a producción y el escalamiento); checklist de la presentación con plan B | Depende de la **defensa en vivo**; faltan los primeros ingresos de las cuentas de reemplazo | **80–100** |

**Puntaje estimado:** entre 86 (escenario estricto) y 100 (escenario
favorable). **Valor central: unos 94/100.**

### Factores transversales que pueden restar

1. **Claves en los textos originales** (tabla 4.1 del informe y secciones antiguas de la bitácora). Se conservaron por la regla de no modificar lo existente; si se publican en el repositorio, contradicen *"no incluir claves en repositorios"*.
2. **Claves triviales vigentes:** la cuenta de base de datos de WordPress y la administradora de WordPress (declaradas como riesgo residual, con su corrección planificada).
3. **Conflicto de IP externo y recurrente en `10.33.195.180`:** puede interrumpir la demostración. Está documentado, escalado y con plan B.
4. **Tabla de contribuciones:** el equipo debe validarla.
5. **Volumen de documentación asistida por IA:** está declarado, pero cada integrante debe poder explicar su parte (*"lo que nadie pueda explicar se considera no defendido"*).

### Lo que más sube la nota desde aquí

- Ensayar la demostración completa con el checklist, incluido el plan B.
- Que cada integrante haga su primer ingreso y explique su máquina.
- Decidir qué se publica en el repositorio: no publicar los originales con claves, o publicarlos saneados.
- Que el docente corrija el conflicto de IP antes de la defensa.

---

## 11. Auditoría final en las máquinas (22/11, 05:29–05:34 UTC)

Se agrega a lo anterior. El detalle está en la bitácora, sección "Auditoría final de solo lectura". **Resultado:** la implementación verificada coincide con todo lo documentado: monitoreo 8/8, 10 reglas, respaldo y retención ejecutándose solos, HTTPS con la CA propia, cuenta de servicio y logs centrales con HAProxy. Pendientes: tienda en "Próximamente" (se activa antes de la demostración), conflicto de IP externo activo, primeros ingresos de los reemplazos y `degraded` por `fwupd` en proxy1. **La evaluación de la sección 10 se mantiene (unos 94/100).**


---

## 12. Precisión sobre las claves de los documentos originales (22/11)

Se agrega a lo anterior. En la tabla 9.1, la fila "Claves antiguas escritas en
los textos originales (2.2)" dice que **"Ya no son válidas (rotadas)"**. Eso es
cierto para las claves de HAProxy y Grafana, pero **no** para todas las
contraseñas de cuentas de la tabla 4.1 del informe: parte de ellas sigue
vigente, porque el docente accede a las VMs con contraseña. Se rotarán al cierre
de la evaluación. La corrección quedó en el **Anexo E.13** del informe v2, junto
con otras precisiones pendientes y el registro de IA con los cinco campos del
enunciado. La recomendación de la tabla 9.1 se mantiene: el informe no se publica
en el repositorio. La copia publicada contiene solo los `.md` saneados y las
configuraciones.

**Efecto en la evaluación de la sección 10:** el registro de IA con el
"fragmento relevante" y la precisión sobre las credenciales cierran dos
observaciones de forma. La estimación se mantiene en **unos 94/100**: el margen
restante depende de la defensa y de la exigencia del docente sobre la tabla 4.1.
