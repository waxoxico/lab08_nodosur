# Bitácora técnica — Entrega 3

**Grupo Tas_08 · Proyecto Nodo Sur**
Período: 11 al 22 de octubre de 2026

---

## Contexto

Tras el resultado de la Entrega 2 (51,5/100), el equipo decidió reconstruir la plataforma siguiendo la arquitectura distribuida definida en la Entrega 1, en lugar de concentrar los servicios en una sola máquina.

Se descartó el uso de scripts de aprovisionamiento automatizado: las diferencias de estado entre las cuatro máquinas hacían que fallaran de formas distintas en cada una. Cada integrante configura su VM manualmente.

Las zonas horarias de las cuatro VMs están en UTC y sincronizadas, de modo que los registros de distintas máquinas se pueden ordenar en una sola línea de tiempo.

---

## Incidentes y correcciones

| # | Fecha | Problema | Causa raíz | Corrección | Verificación |
|---|---|---|---|---|---|
| 1 | 11/10 | Las cuatro VMs quedaron sin acceso SSH | Se deshabilitó la autenticación por contraseña sin haber instalado antes las llaves criptográficas. Ningún método de autenticación quedó disponible | Acceso por consola de Proxmox; eliminación de `/etc/ssh/sshd_config.d/99-hardening.conf` y restauración de `PasswordAuthentication yes` en `50-cloud-init.conf` | `sshd -T \| grep passwordauthentication` devuelve `yes`; conexión SSH exitosa desde los equipos del grupo |
| 2 | 11/10 | Las reglas de firewall para SSH no cubrían ninguna IP del equipo | El informe declaraba la red de administración como `10.33.195.0/25`, que abarca de `.0` a `.127`. Las IPs reales son `.170`, `.175`, `.180` y `.234` | Se corrigió a `10.33.195.128/25` y se amplió la regla de SSH a `10.33.0.0/16`, porque eduroam asigna direcciones dispersas dentro de `10.33.x.x` | `ip route` confirma `10.33.195.128/25 dev ens18`; acceso SSH restablecido desde todos los equipos |
| 3 | 12/10 | Servicios ajenos al rol consumían recursos en VM1 | Apache y MariaDB habían quedado instalados de la fase de nivelación técnica, ocupando el puerto 80 que necesita HAProxy | `systemctl disable --now apache2 mariadb` en VM1 | `ss -tlnp \| grep :80` muestra solo HAProxy |
| 4 | 16/10 | `rpcbind` activo en VM2 sin NFS instalado | Dependencia residual de una instalación previa de `nfs-common`, con el puerto 111 en escucha sin uso | `systemctl disable --now rpcbind rpcbind.socket` | `ss -tlnp` ya no muestra el puerto 111 |
| 5 | 16/10 | HAProxy no era alcanzable desde la red: `curl` quedaba en timeout | El firewall de VM1 no tenía reglas para los puertos 80 y 443. Los servicios corrían, pero el tráfico se descartaba antes de llegar | Se agregaron las diez reglas faltantes, cada una con comentario que identifica origen y propósito | `curl -I http://10.33.195.180` responde con el encabezado `x-backend: web1` |
| 6 | 16/10 | Relojes de VM1 y VM2 en zonas horarias distintas | VM2 estaba en `America/Santiago` y VM1 en UTC, lo que impedía correlacionar registros entre nodos | `timedatectl set-timezone UTC` en ambas | `date +%s` devuelve el mismo valor (`1792195904`) en las dos VMs, ejecutado de forma simultánea |
| 7 | 16/10 | El endpoint de salud reportaba `-03:00` pese a que el sistema estaba en UTC | `/etc/php/8.3/fpm/conf.d/99-timezone.ini` definía `America/Santiago`. Los archivos de `conf.d/` se cargan después del `php.ini` y lo sobrescriben. Solo existía para FPM, no para CLI, por eso `php -r` devolvía UTC | Se corrigió el valor en ese archivo y se reinició PHP-FPM | `php-fpm8.3 -i \| grep date.timezone` devuelve `UTC`; el health check responde con `+00:00` |
| 8 | 16/10 | Al instalar WordPress, Apache seguía sirviendo su página por defecto | El `index.html` de Apache tiene prioridad sobre `index.php` | `rm /var/www/html/index.html` tras copiar los archivos de WordPress | `curl -I http://localhost` devuelve `302` hacia `/wp-admin/setup-config.php` |
| 9 | 17/10 | El dominio resolvía a la IP de VM2 y las pruebas desde VM1 terminaban en timeout | Entradas residuales en `/etc/hosts`: en VM1, `10.33.195.234 lab08.nodosur.cl www.lab08.nodosur.cl` y `10.33.195.180 lab08.lan`; en VM2, `10.33.199.234 lab08.nodosur.cl` (dirección fuera del rango `/29`). `/etc/hosts` tiene prioridad sobre el DNS y, además, el enunciado no permite sustituir el DNS con ese archivo | Se eliminaron las entradas en ambas máquinas | `resolvectl query www.lab08.nodosur.cl` pasó de `Data from: synthetic` a `Data from: network` y devuelve `10.33.195.180`; `curl` por dominio responde con `302` hacia el asistente de WordPress |
| 10 | 17/10 | `resolvectl query` fallaba con `No route to host` en VM2 aunque `dig` sí resolvía | El DNS estaba declarado en `ens18` (red de administración) con la IP interna de VM1 (`10.33.199.65`), sin ruta desde esa interfaz | Se movió el bloque `nameservers` a `ens19` en netplan | `resolvectl status` muestra el servidor en Link 3 (ens19); `resolvectl query` responde con `-- link: ens19` y `Data from: network` |
| 11 | 21/10 | Se intentó montar `/srv/proyecto` por UUID y `findmnt --verify` informó `parse error at line 13` | La línea de `/etc/fstab` quedó duplicada y fusionada al guardar (`...0  21~UUID=...`) | Se restauró `/etc/fstab.b2.bak` y la línea se agregó con `tee -a` | `findmnt --verify`: `0 parse errors, 0 errors`; tras `daemon-reload`, `umount` y `mount -a` el volumen vuelve a montarse desde `fstab` |
| 12 | 21/10 | VM2 devolvía `403 Forbidden` en todas las rutas, incluso a `localhost` y desde HAProxy | Había dos `VirtualHost *:80`. El primero era el predeterminado de Apache (`000-default.conf`), sin `ServerName` y con `<Location /> Require all denied </Location>`; al ser el primero, atendía todo el puerto 80 y el de `lab08.conf` nunca se usaba. El `error.log` registraba `AH01630: client denied by server configuration` | `a2dissite 000-default.conf`, `apache2ctl configtest` y recarga | `apache2ctl -S` muestra un solo VirtualHost (`lab08.conf`); `curl -I http://localhost` devuelve `200` con el encabezado `Link` de la API REST de WordPress, señal de que carga con su configuración completa y conectado a VM4 |
| 13 | 21/10 | Se creyó que VM2 era accesible por IP directa desde fuera | La prueba se había ejecutado dentro de VM2 hacia su propia IP, y ese tráfico no atraviesa UFW | Se repitió la prueba desde un equipo externo por VPN | Desde Windows, `curl.exe -I http://10.33.195.234` no obtiene respuesta (bloqueado por UFW, como corresponde); por el balanceador sí responde |
| 14 | 22/10 | El certificado de HAProxy volvió a quedar sin SAN en disco, aunque el servido sí lo tenía | Tras regenerarlo y recargar, se restauró el respaldo. La instrucción decía «si marca un error, restaurar», sin aclarar que `Warnings were found` es una advertencia normal del bloque `stats` y no un error | Regenerado de nuevo; se comprobó que la huella del certificado servido coincide con la del archivo en disco, y se agregó esa comprobación al script de validación | `openssl x509 -fingerprint` idéntico en el servicio y en el archivo; el `.pem` con fecha del 22/10 y 4273 bytes |
| 15 | 22/10 | VM3 quedó con WordPress 7.1 en lugar de 7.1.3 | El paquete nunca se descargó: el `tar` falló, pero los comandos siguientes no estaban encadenados y el `cp` copió una carpeta de un intento anterior | Descarga encadenada con `&&`, verificada con `sha1sum -c` antes de copiar, y vaciado del directorio destino | `wordpress-7.1.3.tar.gz: OK` y `$wp_version = '7.1.3';` |

---

**Patrón de los incidentes 14 y 15.** Los dos nacen de lo mismo: una cadena de comandos que no se detiene cuando un paso falla, o un mensaje de advertencia leído como error. De ahí la regla que se aplicó después en cada cambio: encadenar con `&&` y distinguir advertencia de error antes de revertir.

---

## Hallazgos de diseño

Estos puntos no fueron fallas puntuales, sino configuraciones que funcionaban pero no cumplían lo esperado.

| # | Hallazgo | Estado |
|---|---|---|
| H1 | **El health check de HAProxy era de capa 4.** Solo comprobaba que el puerto 80 aceptara una conexión TCP, por lo que un nodo con Apache vivo y PHP caído seguía figurando sano. Confirmado con `tcpdump` en VM2: `SYN` y `RST` cada 2 s, sin datos HTTP | **Resuelto el 22/10**: `option httpchk` con `GET /health.php` y `http-check expect status 200`; `show stat` pasa de `L4OK` a `L7OK 200` |
| H2 | **El segundo backend (`srv-2`, VM3) figuraba `DOWN`** porque la máquina no estaba configurada | **Resuelto el 22/10**: VM3 operativa y en rotación; los dos backends en `UP, L7OK, 200` |
| H3 | **El panel de estadísticas de HAProxy cambió de puerto.** Se vio en `10.33.199.65:8080` y luego en `10.33.195.180:32500`, mientras el firewall tiene abierto el `8404` | **Resuelto el 22/10**: `ss` muestra el panel escuchando en `10.33.195.180:32500` y UFW abre `32500/tcp`; ver H13 por el origen permitido |
| H4 | **Dos patrones comparten causa:** un directorio `.d/` cargado después sobrescribe el archivo principal (`sshd_config.d` en SSH, `conf.d` en PHP). La verificación debe hacerse sobre el valor efectivo (`sshd -T`, `php-fpm -i`, `apache2ctl -S`), no sobre el archivo | Registrado |
| H5 | **Entradas de bloqueo de UFW en VM2** (`journalctl -k -g UFW`): VM4 hacia el puerto 80 de VM2 (esperado: solo VM1 puede), un host `10.33.21.6` hacia el 443, y una dirección `169.254.x.x` hacia el 22. Muestran que el firewall filtra y registra | Registrado como evidencia |
| H6 | **El certificado de HAProxy no tiene SAN.** `openssl x509 -ext subjectAltName` responde `No extensions in certificate`: la identidad está solo en el `CN`. Los navegadores modernos exigen el SAN y no usan el `CN` | **Resuelto el 22/10**: certificado regenerado con SAN (`www.lab08.nodosur.cl`, `lab08.nodosur.cl` e IP `10.33.195.180`), vigente hasta el 22/10/2027 |
| H7 | **WordPress se conecta a MariaDB como `admin` y a la base `lab08_db`**, no como `wp_user` a `wordpress`. La primera auditoría del 22/10 mostró la cuenta como `admin`@`%`, que acepta cualquier origen. Una consulta posterior la muestra como `admin`@`10.33.199.66`, con `USAGE` global y 19 privilegios de esquema solo sobre `lab08_db` (el conjunto de `ALL PRIVILEGES` de una base). Lo más probable es que el cambio de host se aplicara entre ambas consultas; no se registró quién ni cuándo. Es coherente con el `ERROR 1141` de `SHOW GRANTS FOR 'admin'@'%'`, porque esa cuenta ya no existía | **Resuelto**: host restringido a `10.33.199.66` y sin privilegios globales. Pendiente: cuenta equivalente para VM3 y revisar `IS_GRANTABLE` |
| H8 | **MariaDB escuchaba en `0.0.0.0:3306`** (`bind-address = 0.0.0.0`, línea 27 de `50-server.cnf`). El diseño pide la IP interna `10.33.199.68` | **Resuelto el 22/10**: `bind-address = 10.33.199.68` y `ss -lntp` muestra `10.33.199.68:3306` tras reiniciar el servicio. Respaldo previo de `/etc/mysql` (sin carpeta anidada) y volcado de `lab08_db` de 2,1 MB con permisos `600`. Desde VM2, `nc -zv 10.33.199.68 3306` es exitoso y el sitio responde `200` |
| H9 | **Regla de UFW en VM4 para `22/tcp` desde `10.33.195.0/25`**: es el rango erróneo del informe de la Entrega 1 y no contiene ninguna IP del equipo | **Resuelto el 22/10**: la regla ya no figura. Quedan `22/tcp` desde `10.30.248.0/24`, `10.33.195.128/25` y `10.33.117.60` (la regla `53/udp` no aparece en esa consulta porque se filtró por `22/tcp`) |
| H10 | **La base `wordpress` (12 tablas) y los usuarios `wp_user` y `wpuser` no son los que usa el sitio.** El sitio usa `lab08_db` (98 tablas). Las 12 tablas coinciden con el núcleo de WordPress sin WooCommerce, lo que sugiere un resto de una instalación anterior. Cualquier respaldo debe apuntar a `lab08_db` | Registrado |
| H11 | **`wp-config.php` de VM2 conserva las 8 frases de ejemplo** (`put your unique phrase here`): `grep -c` devuelve 8. Las claves y sales de autenticación deben ser únicas. Según el código de WordPress, el valor de ejemplo se trata como no definido y se usan claves aleatorias guardadas en la base de datos, lo que atenúa el efecto práctico (no verificado en esta instalación), pero el archivo no cumple lo que pide la clase | **Resuelto el 22/10**: las 8 frases se reemplazaron por claves obtenidas de `api.wordpress.org`. `php -l` sin errores, `grep -c` devuelve 0, el archivo conserva `www-data:www-data 640` y el sitio responde `200`. Respaldo previo en `/root/wp-config.php.b3.bak`. Las sesiones abiertas quedan invalidadas. Comprobado después: 8 líneas de claves presentes en el archivo y sin archivos temporales en `/tmp` |
| H12 | **El código de WordPress pertenece a `www-data` y 17.636 archivos `.php` son escribibles por ese usuario.** La clase propone `root:www-data` con `0750` y `0640`, y solo `uploads` escribible. El modelo actual permite instalar y actualizar plugins desde el panel (WooCommerce ya está instalado), pero un PHP comprometido podría reescribir el código del sitio | **Riesgo aceptado** por ahora; revisar después de la entrega |
| H13 | **El puerto `32500/tcp` de VM1 está abierto a `Anywhere` en IPv4 e IPv6.** Es el del panel de estadísticas de HAProxy: `ss` lo muestra escuchando solo en `10.33.195.180`, `curl` devuelve `401` (exige credenciales) y la configuración no incluye `stats admin`, por lo que el panel es de solo lectura. Las reglas anteriores del panel (`8404`) lo limitaban a `10.33.0.0/16` y a la VPN. Las reglas de `80/tcp`, `443/tcp` y `32500/tcp` perdieron además su comentario. El riesgo es menor que el de un panel sin credenciales, pero cualquier equipo que alcance esa IP puede intentar autenticarse | **Resuelto el 22/10**: el `32500` quedó restringido a `10.33.0.0/16` y a la VPN, con comentarios. `ss` confirma que el panel escucha solo en `10.33.195.180` y `curl` devuelve `401`. La contraseña sigue siendo débil y en texto plano |
| H14 | **BIND9 (`named`) está habilitado y activo en VM4**, con dos zonas: `anibal.test` (probablemente la práctica de la clase 8) y `199.33.10.in-addr.arpa`, que VM1 también declara como primaria. `ss` lo muestra en `127.0.0.1`, `10.33.199.68`, `[::1]` y las direcciones locales de enlace IPv6, puerto 53. El diseño ubica el DNS solo en VM1. UFW solo permite `53/udp` desde `10.33.192.0/22` (regla heredada de la configuración base inicial); la red interna del proyecto no tiene permiso para el 53. La propia VM4 usa `10.33.199.65` (VM1) como DNS, declarado en `ens18`, y no su `named`; apagarlo no afecta su resolución | **Resuelto el 22/10**: `systemctl disable --now named`. `ss` ya no muestra `named`, solo los resolutores locales de `systemd-resolved` en `127.0.0.53` y `127.0.0.54`. `dig +short google.com` y `resolvectl query` siguen resolviendo, y se eliminó la regla `53/udp`. Los archivos de `/etc/bind` se conservan |
| H15 | **NFS ofrece las versiones 3, 4, 4.1 y 4.2, y `rpcbind` escucha en `0.0.0.0:111`.** Con NFS 4 solo se necesita el puerto 2049. `rpc.statd`, también de la pila de NFS 3, escucha en un puerto UDP dinámico que UFW no permite | **Parcial**: los dos nodos montan con `vers=4.2`, comprobado con `findmnt`. Falta retirar la regla `111` |
| H16 | **VM4 repite el incidente 10: el DNS está declarado en `ens18` y `resolvectl query www.lab08.nodosur.cl` falla con `No route to host`.** El servidor es `10.33.199.65`, que está en la red interna (`ens19`), sin ruta desde la interfaz de administración. El netplan de VM4 coincide con la plantilla del script de configuración base que se descartó, que declaraba `nameservers` bajo `ens18`. La resolución del sistema funciona de todos modos: `getent hosts www.lab08.nodosur.cl` y `dig +short google.com` responden | **Resuelto el 22/10**: el DNS pasó a `ens19`. `resolvectl status` lo muestra bajo Link 3 y `resolvectl query www.lab08.nodosur.cl` responde `10.33.195.180` con `link: ens19` y `Data from: network`. Respaldo en `/root/netplan.b3.bak` |
| H17 | **VM3 tenía el firewall y el DNS con los errores de la configuración inicial.** UFW permitía `22/tcp` desde `Anywhere` (IPv4 e IPv6), conservaba el rango erróneo `10.33.195.0/25` y la `53/udp` heredada, y no tenía la regla de `10.33.0.0/16`. El DNS estaba bajo `ens18` | **Resuelto el 22/10**: UFW con SSH solo desde la VPN y `10.33.0.0/16`; DNS movido a `ens19` y verificado con `resolvectl query` |
| H18 | **VM3 cargaba `php_module` (`mod_php`) además de `proxy_fcgi_module`**, lo que obliga a `mpm_prefork` y contradice el informe de la Entrega 1 | **Resuelto el 22/10**, antes de dockerizar: `a2dismod php8.3`, `mpm_event` activo y `health.php` devolviendo `sapi=fpm-fcgi` |
| H19 | **Docker publica sus puertos sin pasar por UFW.** Comprobado el 22/10 con un contenedor en el `8081`: desde VM4 ese puerto respondía `succeeded` mientras el puerto 80 nativo daba timeout. Las reglas de Docker se insertan en `FORWARD`, no en la cadena de entrada donde UFW aplica las suyas | **Resuelto**: regla en `DOCKER-USER` que limita el origen a `10.33.199.65`, con una unidad de `systemd` que la reaplica en cada arranque |
| H20 | **El certificado de HAProxy volvió a quedar sin SAN en disco.** El 22/10 por la noche, el certificado servido tenía SAN pero el archivo de disco era el viejo: una recarga lo habría deshecho. Las tres copias del PEM compartían huella y fecha, lo que indica que el respaldo se restauró después de recargar | **Resuelto el 22/10 a las 22:56**: certificado regenerado, y huella del servido idéntica a la del disco. El script de validación ahora compara ambas |

---

## Clase 5 — Volumen persistente y colaboración con mínimo privilegio (VM4)

**Desviación respecto del enunciado de clase.** El ejercicio asume un segundo disco físico. VM4 solo tiene `sda` (200 GB) y el equipo no tiene permisos para agregar hardware en Proxmox. El disco tenía 99 GB sin asignar dentro del grupo de volúmenes LVM (`ubuntu-vg`), por lo que se creó un volumen lógico con sistema de archivos y UUID propios. El resto del procedimiento no cambia.

| Paso | Resultado |
|---|---|
| 1. Inventario | `lsblk` y `blkid` muestran un único disco; `/srv/nfs` ya existía (24 KB) |
| 2. Volumen y sistema de archivos | `lvcreate -L 20G -n lv-proyecto ubuntu-vg` y `mkfs.ext4`; UUID `8fdcc54a-b117-4d68-b323-059b5e7ecc50` |
| 3. Montaje temporal | `findmnt /srv/proyecto` correcto; escritura y borrado de prueba sin errores |
| 4. Persistencia por UUID | Línea `UUID=... /srv/proyecto ext4 defaults,nofail 0 2` en `fstab`; validada con `findmnt --verify`, `daemon-reload`, `umount` y `mount -a` (ver incidente 11) |
| 5. Política de grupo | Grupo `cmsops`; directorio `/srv/proyecto/compartido` con modo `2770` (`drwxrws---`, `root:cmsops`) |
| 6. `umask` y ACL | `umask 0007` produce archivos `660`; ACL de solo lectura `r-X` para `xavineta2026` |

**Pruebas que respaldan la política**

- *Herencia de grupo:* un archivo creado por `anibal` (grupo primario `anibal`) quedó con grupo `cmsops`, lo que demuestra el efecto del bit setgid.
- *ACL de solo lectura:* `sudo -u xavineta2026 touch .../prueba-xavi` devuelve `Permission denied`. El usuario se creó en VM4 sin directorio personal y sin shell (`useradd -M -s /usr/sbin/nologin`), ya que su cuenta real está en VM1.

**Criterio de diseño:** los miembros de `cmsops` tienen acceso completo; quien necesita solo observar recibe una ACL puntual, sin ingresar al grupo.

**Por confirmar:** que la cuenta de Matías (`mgonzalez`) exista en VM4 y esté efectivamente en `cmsops`, y que se agregue la de Yovani cuando exista VM3.

**Relación con el proyecto:** este volumen aún no es el origen del NFS. El directorio exportable que se vio es `/srv/nfs/wp-content`. Falta decidir si se unifican.

---

## Clase 6 — Servicio, socket y firewall (VM2)

No se creó el servicio de prueba de la clase (`python3 -m http.server` en el puerto 8080). Los mismos objetivos se verificaron sobre los servicios reales.

| Objetivo de la clase | Evidencia en VM2 |
|---|---|
| Línea base de red | `ip -br address`, `ip route` y `resolvectl status`: `ens18` `10.33.195.234/25`, `ens19` `10.33.199.66/29`, DNS `10.33.199.65` |
| Servicio, proceso y socket | `ss -lntup`: Apache en `*:80`, SSH en `:22`; `systemctl --failed` sin unidades fallidas |
| UFW restringido y comentado | Permite `22/tcp` desde `10.30.248.0/24` y `10.33.0.0/16`, y `80/tcp` solo desde `10.33.199.65` (HAProxy) |
| Validación desde ambos extremos | Local: `200 OK` con `x-backend: web1`. Remoto: sin respuesta directa desde fuera; `200` por el balanceador |
| Registro del firewall | `journalctl -k -g UFW` muestra bloqueos reales (incidente 13 y hallazgo H5) |

---

## Clase 7 — DHCP con Kea

**Diferida.** El ejercicio requiere una interfaz aislada con un cliente (`srv-infra` y `cli-linux`), que no existe en las VMs del proyecto. Instalar un servidor DHCP en `ens18` podría repartir direcciones en la red de administración de la universidad, y `ens19` tiene una sola dirección libre (`10.33.199.69`).

La Entrega 3 no incluye DHCP en ninguno de sus criterios. Si se retoma, la alternativa propuesta es simular el aislamiento con un par `veth` y un espacio de nombres de red. Esa simulación **no se ejecutó**.

---

## Clase 8 — DNS autoritativo (VM1)

El DNS ya funcionaba. Se verificó contra el ejercicio y se endureció.

### Antes y después

| Aspecto | Antes (respaldo en `/etc/bind.b2.bak`) | Después |
|---|---|---|
| Escucha | `listen-on { any; }`, `listen-on-v6 { any; }` | `127.0.0.1`, `10.33.199.65` y `10.33.195.180`; IPv6 desactivado |
| Consultas | `allow-query { any; }` | `localhost`, `10.33.0.0/16` y `10.30.248.0/24` |
| Recursión | `recursion yes` sin límite | `allow-recursion { localhost; 10.33.199.64/29; }` |
| Transferencias | sin restricción declarada | `allow-transfer { none; }` |
| TTL | 604800 (una semana) | 300 |
| Serial | `2026101101` | `2026102201` |
| Registros | NS, A (`ns1`, `@`, `www`) | + `web1`, `web2`, `db`, `mail`, CNAME `app`, MX y TXT |
| Zona inversa | inexistente | `199.33.10.in-addr.arpa` |

Archivos modificados, según `diff -rq` contra el respaldo: `db.lab08.nodosur.cl`, `named.conf.local` y `named.conf.options`. Archivo nuevo: `db.199.33.10`.

### Pruebas

| Prueba | Resultado |
|---|---|
| `named-checkconf -z` | Ambas zonas cargan con serial `2026102201` |
| `dig www A +norecurse` | `10.33.195.180`, bandera `aa`, TTL 300 |
| `dig -x 10.33.199.66` | `web1.lab08.nodosur.cl.` (antes `NXDOMAIN` de la zona vacía integrada de BIND) |
| `dig MX` y `dig TXT` | Registros publicados |
| `dig +tcp` desde VM1 | Responde |
| `dig +tcp` desde VM2, a través del firewall | `10.33.195.180` |
| `dig -x 10.33.199.68` desde VM2 | `db.lab08.nodosur.cl.` |
| `nslookup www.lab08.nodosur.cl 10.33.195.180` desde Windows por VPN | Resuelve |
| `nslookup google.com 10.33.195.180` desde Windows por VPN | `Query refused` |
| `dig @10.33.199.65 google.com` desde VM2 | Resuelve (la recursión interna se mantiene) |

Las dos últimas pruebas, contrapuestas, demuestran que `allow-query` y `allow-recursion` actúan por separado.

**Nota sobre la evidencia.** El `ss -lntup` de VM1 no sirve como prueba de la restricción de escucha: con `listen-on { any; }` BIND también abre un socket por cada dirección de interfaz, y la opción `-4` de `/etc/default/named` ya excluía IPv6. La prueba válida es el archivo de configuración y las pruebas de acceso anteriores.

### Decisiones distintas del enunciado de clase

- **Recursión:** la clase pide `recursion no`. VM2 y VM3 usan a VM1 como único DNS y necesitan resolver nombres externos (`apt`, `docker pull`), por lo que se restringió con `allow-recursion` en lugar de apagarla.
- **Dominio:** se aplicó sobre `lab08.nodosur.cl`, el dominio real del proyecto, en lugar del marcador `equipoXX.tas.test`.

### Pendientes menores

- La carpeta `/etc/bind.b2.bak/bind` es una copia anidada de la configuración original, producto de ejecutar `cp -a` dos veces. El respaldo principal sí contiene la configuración original. Falta eliminar la carpeta anidada para que la restauración quede limpia.
- `db.lab08.lan` no está referenciado en `named.conf.local`. Verificar con `grep -r "lab08.lan" /etc/bind/named.conf*` antes de borrarlo.
- VM3 debe declarar su DNS (`10.33.199.65`) en `ens19`, no en `ens18` (ver incidente 10).

---

## Clase 9 — Servidor web con VirtualHosts por nombre (VM2)

Se aplicó en VM2 con dos sitios de práctica, `portal.lab08.nodosur.cl` y `soporte.lab08.nodosur.cl`, y se revirtió al terminar. Los nombres se publicaron en la zona de VM1 apuntando al balanceador, igual que `www`.

| Paso | Resultado |
|---|---|
| Raíces con permisos mínimos | `/var/www/portal` y `/var/www/soporte` con `root:www-data` y modo `0750`; `index.html` con `0644` |
| VirtualHosts | `portal.conf` y `soporte.conf` habilitados; `apache2ctl configtest` devuelve `Syntax OK` |
| Servidor por defecto | `apache2ctl -S` lista tres `namevhost` y marca como default a `www.lab08.nodosur.cl` (`lab08.conf` carga primero por orden alfabético) |
| Validación | Cada nombre devuelve su propio contenido |

**Pruebas**

| Prueba | Resultado |
|---|---|
| `curl -H "Host: portal.lab08.nodosur.cl" http://127.0.0.1/` | `Portal Nodo Sur` |
| `curl -H "Host: soporte.lab08.nodosur.cl" http://127.0.0.1/` | `Soporte Nodo Sur` |
| `curl -k https://portal.lab08.nodosur.cl/` por el balanceador | `Portal Nodo Sur` |
| `portal_access.log` | Una petición con cliente `10.33.199.65` (HAProxy), que prueba el paso por el balanceador |
| Un log de acceso por sitio | Cada VirtualHost registra por separado |

La misma IP, el mismo puerto y la misma máquina sirven contenido distinto según el encabezado `Host`.

**Desviaciones respecto del enunciado de clase**

- **Regla de UFW no aplicada.** La clase abre el puerto 80 a una red de clientes. En VM2 el puerto 80 solo acepta a `10.33.199.65` (HAProxy), y abrirlo permitiría saltarse el balanceador.
- **Validación ajustada.** El puerto 80 de HAProxy responde `302` hacia HTTPS, así que la prueba se hizo con el encabezado `Host` contra VM2 y, de punta a punta, por HTTPS. Los registros por sitio reemplazan al `journalctl -u apache2`, que solo muestra mensajes del servicio y no las peticiones.

**Hallazgos**

- HAProxy reenvía el encabezado `Host` sin modificarlo: los nombres nuevos llegaron al VirtualHost correcto sin tocar `haproxy.cfg`.
- Una de las pruebas previstas para VM1 se ejecutó en VM2: el log muestra cliente `10.33.199.66`, es decir, VM2 hablándose a sí misma, y no prueba el firewall (mismo error de origen del incidente 13).

**Reversión y verificación posterior.** Se deshabilitaron los sitios y se borraron los directorios. `apache2ctl -S` muestra una sola línea `*:80` apuntando a `lab08.conf`, y `sites-enabled/` contiene únicamente ese enlace. Con `Host: www.lab08.nodosur.cl`, VM2 devuelve `200` con el encabezado `Link` de la API REST de WordPress.

---

## Clase 10 — TLS y confianza (HAProxy en VM1)

La clase construye un VirtualHost HTTPS en Apache. En este proyecto el TLS se termina en HAProxy y los backends reciben HTTP, por lo que de esta clase solo se aplicó la inspección del certificado (paso 6), contra el balanceador real. El laboratorio con Apache en VM2 **no se ejecutó**.

**Inspección del certificado publicado por HAProxy**

```
echo | openssl s_client -connect 10.33.195.180:443 -servername www.lab08.nodosur.cl 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

| Campo | Resultado | Lectura |
|---|---|---|
| `subject` | `C=CL, ST=Biobio, L=Concepcion, O=UTFSM, OU=TAS, CN=www.lab08.nodosur.cl` | La identidad declarada |
| `issuer` | Igual al `subject` | Autofirmado: no hay autoridad certificadora que respalde la identidad |
| `notBefore` / `notAfter` | 19/10/2026 / 19/10/2027 | Vigencia de un año |
| `subjectAltName` | `No extensions in certificate` | **Sin SAN** (hallazgo H6) |

**Corrección (22/10).** Se respaldó `/etc/ssl/haproxy/lab08.nodosur.pem` como `.b3.bak`, se generó un certificado nuevo con SAN, se reemplazó el archivo y se recargó HAProxy. La misma inspección después del cambio:

| Campo | Antes | Después |
|---|---|---|
| `notBefore` / `notAfter` | 19/10/2026 / 19/10/2027 | 22/10/2026 / 22/10/2027 |
| `subjectAltName` | `No extensions in certificate` | `DNS:www.lab08.nodosur.cl`, `DNS:lab08.nodosur.cl`, `IP Address:10.33.195.180` |
| `curl -skI https://www.lab08.nodosur.cl` | — | `HTTP/2 200` |

Esa primera corrección se perdió más tarde esa misma noche: el certificado quedó cargado en memoria pero el archivo de disco volvió al viejo. Ver hallazgo H20.

**Decisiones de diseño relacionadas**

- **La redirección HTTP a HTTPS vive en HAProxy y no en los backends.** Si Apache redirigiera a HTTPS mientras HAProxy le reenvía por HTTP, la petición volvería una y otra vez al mismo punto, porque Apache nunca ve la conexión cifrada. El `302` del puerto 80 de HAProxy evita ese bucle. Es un razonamiento de diseño; no se provocó el bucle para comprobarlo.
- **Certificado autofirmado en laboratorio.** Let's Encrypt necesita validar el dominio desde internet, y `lab08.nodosur.cl` solo existe en el DNS privado del proyecto.

**Desviaciones respecto del enunciado de clase**

- No se aplicó la regla de UFW del paso 4: abrir el 443 de un backend a una red de clientes permitiría saltarse el balanceador.
- El certificado de la clase dura 30 días; el de HAProxy dura un año y, tras la corrección del 22/10, también declara SAN.

---

## Clase 11 — MariaDB (VM4)

MariaDB ya estaba instalado y en uso, por lo que no se repitió la instalación: se auditó contra los controles de la clase. El laboratorio con base y usuario de práctica **no se ejecutó**.

| Control | Observado en VM4 | Esperado | Resultado |
|---|---|---|---|
| Servicio | `active` y `enabled`; `systemctl --failed` sin unidades | Activo | Correcto |
| Versión | 10.11.14 | — | — |
| Escucha | `bind-address = 0.0.0.0`; tras la corrección, `10.33.199.68` | IP interna `10.33.199.68` | H8 resuelto |
| Firewall | `3306/tcp` y `2049/tcp` solo desde `10.33.199.66` y `.67` | Origen restringido a los nodos web | Correcto |
| Firewall, SSH | Incluía `22/tcp` desde `10.33.195.0/25` | Rango correcto: `.128/25` | H9 resuelto: regla eliminada |
| Usuarios | Primera consulta: `admin`@`%`. Consulta posterior: `admin`@`10.33.199.66`. Además `wp_user`@`.66` y `.67` y `wpuser`@`localhost` | Usuario exclusivo, con host restringido | H7: host restringido |
| Bases | `lab08_db` (98 tablas), `wordpress` (12 tablas) | — | Hallazgo H10 |
| NFS | `nfs-kernel-server` activo | Activo | Correcto |

`SHOW GRANTS FOR 'admin'@'%'` devolvió `ERROR 1141` aunque la primera consulta listaba esa cuenta. Las consultas a `information_schema` posteriores la muestran como `admin`@`10.33.199.66`, con `USAGE` global y los 19 privilegios de esquema sobre `lab08_db`: la cuenta con host `%` ya no existía cuando se ejecutó `SHOW GRANTS`. El conjunto de privilegios corresponde a lo que WordPress necesita para instalar y actualizar plugins (`CREATE`, `ALTER`, `DROP`), acotado a una base y a un host. No se consultó `IS_GRANTABLE`.

**Exportación NFS verificada con `exportfs -v`**

```
/srv/nfs/wp-content  10.33.199.66(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
/srv/nfs/wp-content  10.33.199.67(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
```

La política de acceso queda así: exportación por host, y no por red; lectura y escritura solo para los dos nodos web; `root_squash`, de modo que un `root` remoto se mapea a un usuario sin privilegios.

---

## Clase 12 — WordPress sobre Apache y PHP-FPM (VM2)

WordPress ya estaba instalado y en uso, por lo que no se repitió la instalación: se auditó contra los pasos de la clase. La clase usa otros nombres (`portal.equipoXX.tas.test`, `/var/www/portal`, `cms_equipoXX`, `cms_app`); en VM2 los equivalentes son `www.lab08.nodosur.cl`, `/var/www/html`, `lab08_db` y `admin`.

| Paso de la clase | Estado en VM2 |
|---|---|
| 1. Dependencias | DNS, Apache y conexión al puerto 3306 de VM4 verificados antes |
| 2. PHP-FPM y extensiones | `php-fpm8.3 -m` lista `curl`, `gd`, `intl`, `mbstring`, `mysqli`, `xml`, `zip` (los siete de la clase) |
| 3. Apache con FPM | Solo `proxy_fcgi_module`; sin `php_module`. No se borró `health.php`, porque es el endpoint de salud del balanceador |
| 4. Obtener WordPress | Instalado, versión 7.1.3. No se comparó la suma de verificación del paquete original |
| 5. Propiedad y escritura mínima | Difiere de la clase (H12) |
| 6. Configuración | `wp-config.php` con modo `640` y conexión a VM4; sales únicas desde el 22/10 (H11 resuelto) |

**Auditoría de solo lectura**

| Comprobación | Resultado |
|---|---|
| `stat` de `/var/www/html`, `wp-content` y `uploads` | `www-data:www-data`, modo `755` |
| `stat` de `wp-config.php` | `www-data:www-data`, modo `640` (no legible por otros usuarios) |
| Archivos `.php` escribibles por `www-data` | 17.636 |
| Frases de ejemplo en `wp-config.php` | 8 antes de la corrección; 0 después |

---

## Clase 13 — Firewall y NAT

La clase asigna una sola herramienta por host (nftables en una pasarela, UFW en servidores de acceso simple, reglas de Docker en un `docker-host`). En Nodo Sur ninguna VM cumple función de pasarela: el gateway `10.33.199.70` pertenece a la infraestructura del laboratorio, y HAProxy termina las conexiones y abre otras hacia los backends, por lo que no necesita `ip_forward`. Los pasos 4 a 6 (habilitar el reenvío y la traducción de direcciones) **no se aplican**. Las cuatro VMs usan UFW como única autoridad.

**Paso 1 — inventario (22/10).** VM1, VM2 y VM4 dieron el mismo resultado estructural:

| Elemento | Resultado |
|---|---|
| `net.ipv4.ip_forward` | `0` en las tres |
| nftables | Solo `table ip filter` y `table ip6 filter`, ambas marcadas `managed by iptables-nft, do not touch!`. No hay tablas nativas |
| Políticas de cadena | `INPUT` y `FORWARD` en `drop`, `OUTPUT` en `accept`, en IPv4 e IPv6 |
| iptables | v1.8.10 (nf_tables); `update-alternatives` apunta a `iptables-nft` |
| Servicio `nftables` | `disabled` e `inactive` |

`/etc/nftables.conf` comienza con `flush ruleset`. Mientras el servicio siga deshabilitado no tiene efecto, pero iniciarlo borraría las reglas que escribe UFW (y luego las de Docker). Por eso el paso 6 de la clase (`enable` y `reload` de `nftables`) no se aplica en hosts que usan UFW.

El inventario de VM1 dejó el hallazgo H13 (el puerto `32500/tcp` abierto a cualquiera), y el de VM4 los hallazgos H14, H15 y H16.

**Paso 3 — ubicar el tráfico en el recorrido.** Captura en VM2 sobre la interfaz interna:

```
sudo tcpdump -ni ens19 -c 5 'tcp port 80 and src host 10.33.199.65'
```

Resultado: cada 2 segundos llega un `SYN` desde `10.33.199.65` hacia el puerto 80 y, aproximadamente 1 ms después, un `RST` con `ACK` desde el mismo origen y puerto. Los cuatro paquetes tienen `length 0`. Es la firma de un chequeo de capa 4: HAProxy abre la conexión TCP y la cierra de inmediato, sin enviar ninguna petición HTTP. Confirma el hallazgo H1 y que el chequeo llega por la red interna, que es el origen permitido por UFW.

**Relación con Docker.** Los puertos que Docker publica no pasan por las reglas de UFW. Se comprobó al contenerizar los nodos: ver hallazgo H19 y la sección de las clases 14 y 15.

---

## NFS de `wp-content` (persistencia)

**Verificación previa, 22/10**

| Elemento | Resultado |
|---|---|
| VM4, `/srv/nfs/wp-content` | `33:33`, modo `755`; contiene `plugins`, `themes`, `upgrade` y `uploads`, sin contenido (20 KB) |
| VM2, `/var/www/html/wp-content` | 332 MB en disco (261 MiB reales), con `plugins`, `themes`, `uploads`, `languages`, `upgrade`, `jetpack-waf` e `index.php` |
| Cliente NFS en VM2 | `mount.nfs` instalado (`/usr/sbin/mount.nfs`) |
| Versión a usar | NFS 4.2 (`vers=4.2`); solo requiere el puerto 2049 |

**Ejecución, 22/10**

| Paso | Resultado |
|---|---|
| 1. Respaldo de `wp-content` de VM2 | `/root/wp-content-previo.tgz`, 76 MB, modo `600` |
| 2. Montaje temporal en `/mnt/wp-nfs` con `vers=4.2` | `findmnt` muestra `nfs4`; escritura como `www-data` exitosa, y el archivo aparece en VM4 con dueño `www-data` |
| 3. Copia con `rsync` como `www-data` | 22.539 archivos, 261 MiB. Comparación posterior sin diferencias; 26.486 entradas y 261M en ambos lados |
| 4. Montaje definitivo sobre `/var/www/html/wp-content` | `findmnt` correcto; el sitio responde `200` con el encabezado `Link` de la API REST |
| 5. Persistencia en `fstab` | `findmnt --verify`: `0 parse errors, 0 errors`; probado con `umount` y `mount -a` |
| 6. Coherencia entre nodos | Un archivo creado en VM2 aparece en VM3 y viceversa, con dueño `www-data` |

La línea agregada a `/etc/fstab` en los dos nodos:

```
10.33.199.68:/srv/nfs/wp-content /var/www/html/wp-content nfs vers=4.2,_netdev 0 0
```

**Por qué se comparte todo `wp-content` y no solo `uploads`.** La base de datos es única y compartida: cuando se activa un plugin desde un nodo, la activación se guarda en la base. Si el otro nodo no tuviera los mismos archivos, WordPress no los encontraría y desactivaría el plugin.

**Riesgos a documentar**

- VM4 pasa a ser dependencia también del código de los plugins y temas (ya lo era de la base de datos).
- Cargar archivos PHP por red añade latencia; la caché de código de PHP la atenúa.
- Con `root_squash`, el usuario `root` de los nodos web no puede modificar el contenido; los cambios deben hacerse como `www-data`.
- El montaje es `hard`: si VM4 deja de responder, los procesos que accedan a `wp-content` se quedan esperando en vez de fallar rápido.

---

## Verificación de la cadena completa

Prueba del 21/10 desde un equipo Windows conectado por VPN, sin pasar por SSH:

```
curl.exe -IL -k --max-time 5 https://www.lab08.nodosur.cl

HTTP/1.1 200 OK
x-backend: web1
set-cookie: SRVNAME=srv-1; path=/
```

| Evidencia | Qué demuestra |
|---|---|
| El dominio resuelve por el DNS de VM1 | El nombre es verificable sin `/etc/hosts` |
| `302` hacia HTTPS en el puerto 80 | Redirección segura en el balanceador |
| `HTTP/2 200` | TLS operativo en HAProxy, con terminación en VM1 |
| `x-backend: web1` | Backend identificable |
| `set-cookie: SRVNAME=srv-1` | Persistencia de sesión insertada por HAProxy |
| Registro de HAProxy | Peticiones `https~ aplicaciones_web/srv-1` con código 200 y WordPress sirviendo tema y recursos |

### Sobre el endpoint de salud

`health.php` devuelve el nombre del host, una marca de tiempo ISO 8601 y el intérprete en uso:

```php
echo "OK " . gethostname() . " " . date("c") . " sapi=" . php_sapi_name();
```

Incluir `php_sapi_name()` es deliberado: un chequeo contra un archivo estático devolvería `200` aunque PHP estuviera caído. Este endpoint recorre la pila completa. Con los nodos nativos devolvía `sapi=fpm-fcgi`; con los contenedores devuelve `sapi=apache2handler`.

### Flujo principal y sesiones (22/10)

| Prueba | Resultado |
|---|---|
| Catálogo de WooCommerce forzando cada nodo con la cookie `SRVNAME` | `200` en ambos, con el mismo producto |
| Inicio de sesión en `wp-login.php` | `302` hacia `/wp-admin/` |
| La misma cookie de sesión contra cada nodo | `200` en los dos, sin redirección al formulario |

La última prueba demuestra que una sesión iniciada en un nodo es válida en el otro, porque los dos `wp-config.php` comparten las mismas claves de autenticación.

---

## Health check de capa 7 (VM1)

Aplicado el 22/10 sobre el bloque `backend aplicaciones_web`, con respaldo previo en `/etc/haproxy/haproxy.cfg.b3.bak`:

```
option httpchk
http-check send meth GET uri /health.php ver HTTP/1.1 hdr Host www.lab08.nodosur.cl
http-check expect status 200
```

El `grep` sobre el archivo completo confirmó que antes no existía ningún chequeo HTTP, y que las dos líneas `server` ya tenían `check`. `haproxy -c` devolvió `Configuration file is valid` antes de recargar. La advertencia `log format ignored for proxy 'stats'` es previa al cambio y no afecta.

Tras la recarga, `show stat` pasó de `L4OK` a `srv-1,UP,L7OK,200`. El chequeo usa los valores por defecto de HAProxy —cada 2 s, 3 fallos para caer y 2 aciertos para volver—, porque las líneas `server` solo declaran `check`.

---

## VM3 puesta en servicio (22/10)

Se replicó VM2 por configuración, no por clonación: el clon de Proxmox sigue bloqueado por `permission check failed`, y además arrastraría hostname, IPs y llaves.

| Paso | Resultado |
|---|---|
| Firewall corregido | SSH solo desde la VPN y `10.33.0.0/16`; eliminadas las reglas `Anywhere`, `10.33.195.0/25` y `53/udp` (H17) |
| PHP-FPM y extensiones | Los mismos siete módulos de VM2, más `OPcache`; pool con los valores de fábrica, idénticos a VM2 |
| `mod_php` retirado, `mpm_event` activo | `apache2ctl -M` sin `php_module` (H18) |
| VirtualHost y `ServerName` | `lab08.conf` igual al de VM2; `servername.conf` con `web2.lab08.nodosur.cl`; `000-default` deshabilitado |
| WordPress 7.1.3 | Descargado por número de versión y verificado con `sha1sum -c`: `OK`. Antes había quedado una copia de la 7.1, que se reemplazó |
| `health.php` y `X-Backend` | `OK web2 ... sapi=fpm-fcgi` y `X-Backend: web2` |
| `wp-config.php` | Copiado desde VM2 con `scp`, modo `640`, dueño `www-data`; `php -l` sin errores. Mismas claves de sesión que VM2 |
| Cuenta de base de datos | Clonada de la de VM2 cambiando solo el host, sin exponer la contraseña: `admin@10.33.199.67`, 19 privilegios sobre `lab08_db` |
| NFS montado y persistido | `findmnt` con `nfs4` y `vers=4.2`; los 11 elementos de `plugins` visibles |
| Puerto 80 abierto a `10.33.199.65` | **Último paso**, para que HAProxy no enviara tráfico a un nodo a medio armar |

A las 17:29 UTC los dos backends figuraban `UP, L7OK, 200` por primera vez. Veinte peticiones por el balanceador se repartieron 9 y 11 entre `web1` y `web2`.

---

## Clases 14 y 15 — contenedores y Compose

### Instalación de Docker

En VM3 primero y en VM2 al final, siempre guardando antes la línea base del firewall con `iptables-save`. Ambas máquinas quedaron idénticas:

| Comprobación | VM2 | VM3 |
|---|---|---|
| Línea base previa | 105 líneas | 105 líneas |
| `diff` tras instalar | 32 líneas | 32 líneas |
| Digest de la imagen | `sha256:d42f63cb89ad...` | `sha256:d42f63cb89ad...` |
| `ip_forward` | pasó de `0` a `1` | pasó de `0` a `1` |

El `diff` muestra las cadenas nuevas (`DOCKER`, `DOCKER-BRIDGE`, `DOCKER-CT`, `DOCKER-FORWARD`, `DOCKER-INTERNAL`, `DOCKER-USER`), dos saltos al final de `FORWARD` y una tabla `nat` con `MASQUERADE` para `172.17.0.0/16`. Está guardado en `~/evidencia-e3/` de cada nodo.

### Prueba del paso 4 de la clase 14: Docker frente a UFW

Con un contenedor publicado en `10.33.199.67:8081`, desde VM4:

| Puerto | Resultado |
|---|---|
| `8081` (publicado por Docker) | `succeeded` |
| `80` (Apache nativo, restringido por UFW) | `timed out` |

Mismo origen, misma máquina, dos resultados: **los puertos publicados por Docker no pasan por UFW** (H19). El contenedor de prueba se eliminó enseguida.

### El proyecto Compose

En `/srv/tas/wordpress-compose/` de cada nodo: `compose.yaml`, `.env` (modo `0600`), `.env.example`, `.gitignore` y `apache/` con los dos archivos del encabezado `X-Backend`.

Decisiones, con su motivo:

- **Sin servicio `db`**: la base vive en VM4, porque el profesor pidió contenerizar solo los nodos web. La dependencia se declara en el encabezado del `compose.yaml`.
- **Bind mount de `/var/www/html`**: el contenedor usa el código y el `wp-config.php` del host. Así deriva de la línea base, los secretos no entran al Compose y el contenedor no escribe al arrancar, lo que evita chocar con `root_squash`.
- **Volumen `wp_content` declarado como NFS** dentro del propio Compose, en vez de depender del montaje del host.
- **Puerto publicado en la IP interna** del nodo, nunca en todas las interfaces.
- **Una sola imagen `-apache`**, que usa `mod_php`. Es la forma de la clase 15, y se declara como desviación respecto del informe de la Entrega 1.

VM2 se armó copiando el proyecto de VM3 con `scp` y editando solo el `.env`, lo que demuestra la reproducibilidad.

### Restricción de origen y persistencia

`/usr/local/sbin/docker-user-rules.sh` agrega la regla si falta y no la duplica si ya está; `/etc/systemd/system/docker-user-rules.service` la ejecuta después de Docker, con `PartOf=docker.service`. Se probó borrando la regla y reiniciando la unidad: la repuso.

La regla filtra por el destino original con `conntrack`, porque al llegar a `DOCKER-USER` el paquete ya tiene el destino cambiado al del contenedor.

### El cambio al puerto 80

En cada nodo, en este orden: primero la regla del puerto 80, luego `systemctl stop apache2` y `docker compose up -d`, con la reversión encadenada por si Docker fallaba. Después `systemctl disable apache2`, para que un reinicio no los haga pelear por el puerto.

Diez peticiones por el balanceador pasaron a responder todas con `Server: Apache/2.4.69 (Debian)`, alternando `web1` y `web2`: los dos nodos son contenedores. El Apache nativo sigue instalado y configurado, deshabilitado, como reversión.

---

## Pruebas de falla y recuperación

Tres ejecuciones, dos tipos de falla. Todas las horas en UTC del 22/10.

### Falla de PHP-FPM, con los nodos nativos

| Hora | Evento | Fuente |
|---|---|---|
| 17:57:44 | `Stopping php8.3-fpm` en VM3 | journal de VM3 |
| 17:57:46 y :48 | Dos chequeos fallidos (`UP 2/3`, `UP 1/3`, `L7STS 503`); el cliente recibe un `503` en cada uno | VM1 y VM2 |
| 17:57:50 | `srv-2 DOWN`, `Layer7 wrong status, code: 503`, `1 active ... servers left` | log de HAProxy |
| 17:57:51 a 17:58:17 | 21 peticiones seguidas, todas `200` desde `web1` | cliente en VM2 |
| 17:58:13 | `Started php8.3-fpm` | journal de VM3 |
| 17:58:16 | `srv-2 UP`, `Layer7 check passed`, `2 active ... servers online` | log de HAProxy |
| 17:58:24 | `web2` vuelve a responder al cliente | cliente en VM2 |

Una segunda ejecución a las 18:00 dio tiempos idénticos: 6 s de detección y 3 s de reintegración.

### Falla del contenedor

| Hora | Evento | Fuente |
|---|---|---|
| 22:18:27.58 | Contenedor `web2` detenido con `docker compose stop` | `docker inspect` |
| 22:18:31.56 | `srv-2 DOWN`, `Layer4 connection problem: Connection refused` | log de HAProxy |
| 22:18:33 a 22:18:57 | 19 peticiones seguidas, todas `200` desde `web1` | cliente en VM2 |
| 22:18:54.10 | Contenedor iniciado | `docker inspect` |
| 22:18:57.61 | `srv-2 UP`, `Layer7 check passed` | log de HAProxy |

El síntoma dentro del nodo fue `curl` con código 7 (no se pudo conectar), frente al `503` de la falla anterior.

### Comparación

| Medida | PHP-FPM | Contenedor |
|---|---|---|
| Motivo del `DOWN` | `L7STS 503` | `L4CON` |
| Detección | 6 s | 4 s |
| Reintegración | 3 s | 3,5 s |
| Respuestas `503` al cliente | 2 | 0 |

**Límites declarados.** La detección no es instantánea: en la primera prueba, dos peticiones recibieron `503` antes de que el balanceador retirara el nodo. Hubo además peticiones sin respuesta dentro del tiempo de espera de 3 s justo después de reintegrar, probablemente por la caché fría del nodo recién arrancado; no se midió. La alerta programada de VM1 corre cada minuto y no registró la caída del contenedor, de 26 s.

---

## Pruebas de reinicio

| | VM3 | VM2 |
|---|---|---|
| Hora del `DOWN` | 21:35:56 | 22:07:09 |
| Motivo | `Layer4 timeout` | `Layer4 timeout` |
| Hora del `UP` | 21:36:24 | 22:07:33 |
| Fuera de rotación | 28 s | 24 s |

En ambos casos, al volver: el contenedor arrancó solo por `restart: unless-stopped`, el NFS se montó desde `fstab`, la regla de `DOCKER-USER` se reaplicó sola, `apache2` quedó inactivo, y el sitio respondió `200`. Desde VM4 el puerto 80 siguió dando timeout y el 22 `succeeded`, lo que demuestra que la restricción sobrevive al reinicio.

---

## Script de validación y repositorio

`entrega-3/scripts/validar.sh`, de solo lectura, con dos modos:

- `validar.sh nodo`, en VM2 y VM3 — Compose válido, contenedor `healthy`, `health.php`, `X-Backend`, el NFS dentro del contenedor, la regla de `DOCKER-USER`, la unidad activa, Apache nativo apagado, permisos y claves del `wp-config.php`, `.env` en `600`, digest de la imagen y reloj sincronizado.
- `validar.sh balanceador`, en VM1 — `haproxy -c`, el chequeo de capa 7, los dos backends, la redirección a HTTPS, HTTP/2, el SAN y la vigencia del certificado, que el certificado servido coincida con el de disco, diez peticiones repartidas y el panel pidiendo credenciales.

La ejecución del 22/10 en VM1 devolvió 12 comprobaciones en `[ OK ]`, guardada en `~/evidencia-e3/validacion-vm1.txt`. La comprobación de «servido contra disco» se agregó después de que el script detectara el hallazgo H20.

**Estructura del repositorio:**

```
entrega-3/
├── README.md
├── compose/{compose.yaml, .env.example, .gitignore, apache/}
├── host/{docker-user-rules.sh, docker-user-rules.service}
└── scripts/validar.sh
```

---

## Estado de la plataforma

Al cierre del 22/10. Las cuatro VMs en UTC y sincronizadas.

### VM1 · proxy1 · 10.33.195.180 / 10.33.199.65 — Javier Saavedra

| Componente | Estado |
|---|---|
| BIND9 autoritativo, zonas directa e inversa | Activo y restringido (clase 8) |
| HAProxy en `:80` y `:443` | Activo; redirige HTTP a HTTPS |
| TLS | HTTP/2; certificado autofirmado con SAN, vigente hasta el 22/10/2027; servido y disco comprobados idénticos (H6, H20) |
| Backends | `srv-1` y `srv-2` en `UP, L7OK, 200` |
| Health checks | **Capa 7**: `GET /health.php` con `expect status 200` (H1 resuelto) |
| Sesiones persistentes | Cookie `SRVNAME` |
| Firewall | SSH, DNS, 80, 443 y el panel `32500` restringido a universidad y VPN (H13 resuelto) |
| Panel de estadísticas | `10.33.195.180:32500`, con `stats auth`, solo lectura. Contraseña débil y en texto plano: sanear antes de entregar |
| Alertas | Tarea programada cada minuto que avisa por `wall` cuando un backend cae |
| Registros | `/var/log/haproxy.log` |

### VM2 · web1 · 10.33.195.234 / 10.33.199.66 — Matías González

| Componente | Estado |
|---|---|
| Contenedor `web1` | `wordpress:7.1.3-php8.3-apache`, `healthy`, publicado en `10.33.199.66:80` |
| Proyecto Compose | `/srv/tas/wordpress-compose/`, con `.env` en modo `0600` |
| Apache y PHP-FPM nativos | Instalados y **deshabilitados**: son la reversión |
| WordPress | 7.1.3, con `wp-config.php` en el host, modo `640`, claves únicas (H11) |
| `wp-content` por NFS | Montado y persistido en `fstab`, con `vers=4.2` |
| `/health.php` | `OK web1 <fecha ISO> sapi=apache2handler` |
| Firewall | SSH restringido; el puerto 80 lo controla `DOCKER-USER`, no UFW (H19) |
| `docker-user-rules.service` | Habilitado y activo |
| Reinicio probado | 24 s fuera de rotación, con vuelta automática |

### VM3 · web2 · 10.33.195.170 / 10.33.199.67 — Yovani Contreras

Idéntica a VM2, salvo las IPs y el nombre del nodo. Mismo `compose.yaml`, misma imagen y mismo digest; el `.env` solo cambia `NODE_NAME` y `PUBLISH_IP`. `/health.php` devuelve `OK web2 ... sapi=apache2handler`. Reinicio probado: 28 s fuera de rotación.

### VM4 · db1 · 10.33.195.175 / 10.33.199.68 — Aníbal Villablanca

| Componente | Estado |
|---|---|
| MariaDB 10.11.14 | Activo, escuchando solo en `10.33.199.68` (H8) |
| Base y cuentas | `lab08_db`; `admin@10.33.199.66` y `admin@10.33.199.67`, con `USAGE` global y 19 privilegios de esquema (H7) |
| Exportación NFS | `/srv/nfs/wp-content` a `.66` y `.67`, con `rw` y `root_squash`; montado en los dos nodos |
| Volumen LVM `lv-proyecto` | Operativo, montado por UUID (clase 5) |
| Grupo `cmsops`, setgid y ACL | Verificados |
| BIND9 | **Deshabilitado**; los archivos de `/etc/bind` se conservan (H14) |
| Firewall | SSH restringido; 3306 y 2049 solo desde `.66` y `.67`; queda la regla `111`, que NFS 4.2 no usa (H15) |
| Respaldos fuera del host | **Pendiente** |

### Evidencia guardada

En `~/evidencia-e3/` de cada VM: los dos bucles de cada prueba de falla, la ventana del log de HAProxy, el journal de PHP-FPM, los eventos de los reinicios, el `diff` del firewall de cada nodo y la salida del script de validación.

---

## Procedimientos de reversión

| Cambio | Reversión |
|---|---|
| Configuración de red | Respaldo en `/root/netplan.b3.bak`; `netplan try` revierte sola a los 120 segundos |
| Reglas de UFW | `ufw status numbered` y `ufw delete <n>`, o por especificación |
| Zona horaria | `timedatectl set-timezone America/Santiago` |
| Configuración de BIND | `sudo cp -a /etc/bind.b2.bak/. /etc/bind/ && sudo systemctl restart named` |
| Montaje del volumen LVM | `/etc/fstab.b2.bak`; `umount /srv/proyecto` y retirar la línea de `fstab` |
| Volumen lógico | `lvremove ubuntu-vg/lv-proyecto` (destruye su contenido) |
| VirtualHost de Apache | `a2ensite 000-default.conf` y recarga |
| Configuración de MariaDB | `sudo cp -a /etc/mysql.b3.bak/. /etc/mysql/ && sudo systemctl restart mariadb` |
| `wp-config.php` | `sudo cp -a /root/wp-config.php.b3.bak /var/www/html/wp-config.php` |
| Nodo web a su estado nativo | `cd /srv/tas/wordpress-compose && sudo docker compose down && sudo systemctl enable --now apache2` |
| Configuración de HAProxy | `sudo cp -a /etc/haproxy/haproxy.cfg.b3.bak /etc/haproxy/haproxy.cfg && sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy` |
| Certificado TLS | `sudo cp -a /etc/ssl/haproxy/lab08.nodosur.pem.con-san.bak /etc/ssl/haproxy/lab08.nodosur.pem` (el `.b3.bak` es el viejo **sin** SAN: no restaurar desde ahí) |
| Montaje NFS de un nodo | `sudo umount /var/www/html/wp-content` deja visible la copia local, que no se borró; `/etc/fstab.b3.bak` tiene el archivo previo |
| `wp-content` de VM2 | `/root/wp-content-previo.tgz` (76 MB) |
| Regla de `DOCKER-USER` | `sudo systemctl disable --now docker-user-rules.service` y `sudo iptables -D DOCKER-USER ...` |
| BIND9 de VM4 | `sudo systemctl enable --now named` |

Antes de modificar red, firewall o SSH se mantuvo abierta la consola de Proxmox, única vía de acceso independiente de la red.

---

## Pendientes

### Documentación, que es lo que más pesa hoy

- [ ] Informe de avance con el análisis de disponibilidad: distinguir balanceo, tolerancia a falla y alta disponibilidad; identificar HAProxy, MariaDB, el NFS y el DNS como puntos únicos de falla; riesgo residual y evolución (criterio de 5 pts, hoy sin evidencia)
- [ ] Matriz de flujos permitidos, contrastada con las reglas reales de UFW y de `DOCKER-USER`
- [ ] Sanear `haproxy.cfg` antes de incluirlo: la contraseña de `stats auth` va reemplazada por un marcador
- [ ] Subir la carpeta `entrega-3`, etiquetar el commit y entregar el enlace **junto con** la demostración

### Técnicos, que suben nivel en un criterio

- [ ] Escribir los riesgos de persistencia: dependencia de VM4, latencia del NFS y montaje `hard`
- [ ] Probar qué ocurre si VM4 deja de responder con los nodos encendidos
- [ ] Que `health.php` compruebe también el NFS: hoy vive en el disco local, así que un nodo sin NFS podría seguir figurando sano
- [ ] Retirar la regla `111` de UFW en VM4, que NFS 4.2 no usa (H15)
- [ ] Medir la ventana entre que el contenedor publica el puerto y `systemd` aplica la regla al arrancar
- [ ] Cambiar la contraseña del panel de estadísticas por una generada al azar

### Menores

- [ ] Consultar `IS_GRANTABLE` de las cuentas `admin` en VM4
- [ ] Apuntar cualquier respaldo a `lab08_db` y no a la base residual `wordpress` (H10)
- [ ] Eliminar los restos de VM4: base `wordpress`, usuarios `wp_user` y `wpuser@localhost`
- [ ] Confirmar que el usuario de Matías exista en VM4 y esté en `cmsops`
- [ ] Eliminar `/etc/bind.b2.bak/bind` y, si corresponde, `db.lab08.lan`
- [ ] Decidir cuándo eliminar `/root/wp-config.php.b3.bak`, que contiene la contraseña de la base
- [ ] Dejar el `.env.example` del repositorio con valores neutros
- [ ] Respaldo con copia fuera del host
- [ ] El código de WordPress es escribible por `www-data` (H12): riesgo aceptado para poder actualizar plugins desde el panel

### Heredados de la Entrega 1

- [ ] Método de medición de disponibilidad, no solo la meta del 99,5 %
- [ ] Extensión concreta de reservas para WooCommerce, con licencia y costo
- [ ] Capacidad cuantificada contra demanda estimada
- [ ] Destino independiente para los respaldos
- [ ] Centralización de logs

---

## Qué se demostró, criterio por criterio

| Criterio de la Entrega 3 | Evidencia en la implementación |
|---|---|
| Multicontenedor reproducible | `compose.yaml` con servicio, red, volumen y variables; VM2 armada copiando el proyecto y editando solo el `.env` |
| Dos backends funcionales | Misma imagen y digest; catálogo de WooCommerce y sesión de administración funcionando en cada nodo; `X-Backend` los identifica |
| HAProxy, TLS y health checks | HTTP a HTTPS, HTTP/2, certificado con SAN, `haproxy -c` antes de recargar, chequeo de capa 7, retiro y reintegración probados |
| Persistencia y coherencia | Una base, NFS compartido, archivos coherentes en los dos sentidos, sesión válida en ambos nodos, `down` y reinicios sin pérdida |
| Segmentación, firewall y secretos | UFW por origen, base y NFS restringidos por host, `DOCKER-USER` con antes y después, secretos fuera del Compose y del repositorio |
| Prueba de falla y recuperación | Tres ejecuciones, dos tipos de falla, línea de tiempo de tres fuentes y reversión de un comando |
| Análisis de disponibilidad | Puntos únicos de falla identificados; **falta el documento** |
