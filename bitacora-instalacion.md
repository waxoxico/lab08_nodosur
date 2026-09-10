# Bitácora de instalación — Entrega 2

**Grupo Tas_08 · VM `web1` (10.33.195.234 / 10.33.199.66)**

| # | Fecha | Problema | Causa raíz | Corrección | Verificación |
|---|---|---|---|---|---|
| 1 | 28/08 | Apache mostraba su página por defecto en vez de WordPress | `index.html` tiene prioridad sobre `index.php` | `rm /var/www/html/index.html` | Cargó el asistente de WordPress |
| 2 | 28/08 | Error de conexión a la base de datos | Contraseña de `wp_user` no coincidía | `ALTER USER 'wp_user'@'localhost' IDENTIFIED BY '...'` | `mysql -u wp_user -p wordpress` conectó |
| 3 | 31/08 | `ping` al dominio fallaba aunque `dig @IP` resolvía | La VM usaba el DNS de la universidad, no su propio BIND | `nameservers` + `use-dns: false` en netplan | `resolvectl status` mostró `10.33.199.66` |
| 4 | 31/08 | `Temporary failure in name resolution` | BIND intentaba resolver vía IPv6 sin conectividad | `listen-on-v6 { none; }` y `resolver-query-timeout 2000` | `ping` respondió en 0,039 ms |
| 5 | 31/08 | Advertencia `.local is reserved for Multicast DNS` | RFC 6762 reserva `.local` para mDNS/Avahi | Migración a `lab08.nodosur.cl`, serial incrementado | `dig` sin advertencias, flag `aa` |
| 6 | 09/09 | SSH inaccesible desde VPN pese a que `ping` respondía | UFW permitía solo `10.33.195.0/25`; la VPN asigna `10.30.248.x` | Consola de Proxmox + `ufw allow from 10.30.248.0/24 to any port 22` | Conexión exitosa desde fuera del campus |
| 7 | 09/09 | `wp-config.php` con permisos 666 | Permisos heredados de la copia inicial | `chmod 640`, propietario `www-data:www-data` | `ls -l` muestra `-rw-r-----` |
| 8 | 09/09 | Usuario genérico `user` sin trazabilidad | Cuenta por defecto de la plantilla | Creación de `mgonzalez` con sudo; eliminación de `user` | `/etc/passwd` lista solo `mgonzalez` |
| 9 | 09/09 | `PasswordAuthentication no` no tomaba efecto | `sshd_config.d/50-cloud-init.conf` sobrescribía el valor | Corrección en el archivo de cloud-init | `sshd -T` devuelve `no` |
| 10 | 09/09 | Apache respondía a cualquier nombre | No existía VirtualHost con `ServerName` | Creación de `lab08.conf`, desactivación de `000-default.conf` | `apache2ctl -S` muestra el FQDN |
| 11 | 09/09 | Informe declaraba PHP-FPM pero corría mod_php | Instalación inicial con `libapache2-mod-php` | `a2enmod proxy_fcgi` + `a2enconf php8.3-fpm` + `a2dismod php8.3` | `apache2ctl -M` muestra `proxy_fcgi_module` |
| 12 | 09/09 | WordPress generaba enlaces con la IP | `siteurl` y `home` tenían la IP desde la instalación | `UPDATE wp_options SET option_value='https://www.lab08.nodosur.cl'` | Header `Link:` usa el FQDN |
| 13 | 10/09 | UFW bloqueaba respuestas DNS de la universidad | Faltaba permitir el origen del servidor DNS | `ufw allow from 10.33.192.0/22 to any port 53 proto udp` | Sin nuevos `[UFW BLOCK]` |
| 14 | 10/09 | BIND consultaba raíces por IPv6 sin conectividad | Configuración por defecto habilita IPv6 | `OPTIONS="-u bind -4"` en `/etc/default/named` | Sin errores `network unreachable` |
| 15 | 10/09 | DNS no respondía a clientes externos | BIND escuchaba solo en `10.33.199.66` | `listen-on { 127.0.0.1; 10.33.199.66; 10.33.195.234; }` + ACL ampliada | `dig @10.33.195.234` responde desde el cliente |
| 16 | 10/09 | SSH no arrancaba automáticamente tras reinicio | Servicio en estado `disabled` | `systemctl enable ssh` | `is-enabled` devuelve `enabled` |

## Procedimiento de reversión

En todo cambio crítico se aplicó:

1. **Respaldo previo** de la configuración (`cp -r /etc/bind /etc/bind.backup-FECHA`)
2. **Validación de sintaxis** antes de aplicar: `named-checkconf`, `apache2ctl configtest`, `sshd -t`
3. **`netplan try`** con reversión automática a los 120 segundos para cambios de red
4. **`reload` en lugar de `restart`** cuando el servicio lo permitía, para no interrumpir el servicio
5. **Sesión SSH paralela abierta** durante los cambios de SSH, para no perder acceso
6. **Consola de Proxmox** como vía de recuperación cuando el acceso remoto se perdió (incidente 6)
