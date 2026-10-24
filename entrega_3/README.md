# Nodo web en contenedores — Entrega 3

**Grupo Tas_08 · Proyecto Nodo Sur · Taller de Administración de Sistemas**

Define el nodo web de WordPress como una aplicación de Docker Compose. La misma definición corre en VM2 (`web1`) y en VM3 (`web2`), y deriva de la instalación nativa que se hizo antes con Apache y PHP-FPM.

## Arquitectura

```
cliente ──HTTPS──▶ HAProxy (VM1) ──HTTP──▶ web1 (VM2, contenedor)  ─┐
                    TLS, health checks      web2 (VM3, contenedor)  ─┼──▶ MariaDB y NFS (VM4)
```

| VM | Rol | IP interna |
|---|---|---|
| VM1 | DNS (BIND9) y balanceador (HAProxy, con TLS) | 10.33.199.65 |
| VM2 | Nodo web `web1`, contenedor | 10.33.199.66 |
| VM3 | Nodo web `web2`, contenedor | 10.33.199.67 |
| VM4 | MariaDB y export NFS de `wp-content` | 10.33.199.68 |

## Contenido de esta carpeta

```
entrega-3/
├── README.md
├── compose/
│   ├── compose.yaml            servicio, red, volumen NFS, variables y chequeo de salud
│   ├── .env.example            variables sin secretos
│   ├── .gitignore              excluye .env
│   └── apache/                 encabezado X-Backend que identifica el nodo
├── host/
│   ├── docker-user-rules.sh        restringe el origen de los puertos publicados
│   └── docker-user-rules.service   lo reaplica en cada arranque, después de Docker
└── scripts/
    └── validar.sh                  validación de solo lectura: nodo y balanceador
```

## Dependencias externas

No son servicios de este Compose y por eso no hay `depends_on`. Estas son todas, y dónde vive cada una:

| Dependencia | Dónde | Cómo llega al contenedor | ¿En el repositorio? |
|---|---|---|---|
| Base de datos `lab08_db` | VM4, `10.33.199.68:3306`, cuenta `admin` restringida a la IP del nodo | `wp-config.php` del host | No: tiene la contraseña |
| `wp-content` compartido | VM4, export `/srv/nfs/wp-content` a `.66` y `.67`, con `rw` y `root_squash` | Volumen `wp_content` del Compose (NFS 4.2) | Sí: la definición |
| Núcleo de WordPress 7.1.3 | `/var/www/html` del host | Bind mount | No: se descarga con su suma de verificación |
| `wp-config.php` | `/var/www/html/wp-config.php` del host, modo `640` | Bind mount | No |
| Restricción de origen del puerto 80 | Regla de `DOCKER-USER` en el host | Unidad de `systemd` | Sí: carpeta `host/` |

## Variables (`.env`)

| Variable | Valor | Para qué |
|---|---|---|
| `WP_IMAGE_TAG` | `7.1.3-php8.3-apache` | Imagen con versión fija. Digest verificado: `sha256:d42f63cb89ad0eab272c4b393164e63830d0df270009907919f7dcce52b1a20b` |
| `NODE_NAME` | `web1` o `web2` | Nombre del contenedor y valor del encabezado `X-Backend` |
| `PUBLISH_IP` | `10.33.199.66` o `.67` | IP interna en que se publica el puerto |
| `PUBLISH_PORT` | `80` | Puerto publicado |
| `NFS_ADDR` y `NFS_PATH` | `10.33.199.68` y `/srv/nfs/wp-content` | Origen del volumen compartido |

## Reconstruir un nodo desde cero

Los pasos 1 a 6 son la línea base del host. El 7 en adelante es el Compose.

1. **Host.** Hora en UTC y sincronizada. DNS `10.33.199.65` declarado bajo `ens19`, y no bajo `ens18`. UFW con SSH desde `10.30.248.0/24` y `10.33.0.0/16`. No hay regla de UFW para el puerto 80, porque Docker lo publica sin pasar por UFW.
2. **Docker**, guardando antes el estado del firewall:
   ```
   sudo sh -c "iptables-save | grep -v '^#' > /root/iptables-antes-docker.txt"
   sudo apt install -y docker.io docker-compose-v2
   sudo docker pull wordpress:7.1.3-php8.3-apache
   ```
3. **Núcleo de WordPress**, con comprobación de la suma:
   ```
   cd /tmp && curl -fLO https://wordpress.org/wordpress-7.1.3.tar.gz && curl -fLO https://wordpress.org/wordpress-7.1.3.tar.gz.sha1 && echo "$(cat wordpress-7.1.3.tar.gz.sha1)  wordpress-7.1.3.tar.gz" | sha1sum -c - && tar -xzf wordpress-7.1.3.tar.gz && sudo cp -a wordpress/. /var/www/html/ && sudo chown -R www-data:www-data /var/www/html
   ```
4. **Endpoint de salud**, que usan el chequeo del contenedor y el de HAProxy:
   ```
   printf '%s\n' '<?php' 'header("Content-Type: text/plain");' 'echo "OK " . gethostname() . " " . date("c") . " sapi=" . php_sapi_name() . "\n";' | sudo tee /var/www/html/health.php >/dev/null
   ```
5. **`wp-config.php`.** Se copia desde otro nodo con `scp`, y no pasa por el repositorio ni por el chat. Queda con dueño `www-data`, modo `640`, y con **las mismas sales** que el otro nodo. Si no, una sesión iniciada en un nodo no vale en el otro.
6. **Cuenta de base de datos**, en VM4. Se clona la de otro nodo cambiando solo el host, sin escribir la contraseña:
   ```
   S=$(sudo mariadb -N -e "SHOW CREATE USER 'admin'@'10.33.199.66'") && echo "$S" | sed 's/10\.33\.199\.66/10.33.199.67/; s/$/;/' | sudo mariadb && sudo mariadb -e "GRANT ALL PRIVILEGES ON lab08_db.* TO 'admin'@'10.33.199.67';"
   ```
   VM4 también debe exportar `/srv/nfs/wp-content` a la IP del nodo y tener la regla de UFW para el `2049` desde ella.
7. **Regla de origen del puerto**, desde esta carpeta:
   ```
   sudo install -m 755 host/docker-user-rules.sh /usr/local/sbin/docker-user-rules.sh
   sudo install -m 644 host/docker-user-rules.service /etc/systemd/system/docker-user-rules.service
   sudo systemctl daemon-reload && sudo systemctl enable --now docker-user-rules.service
   ```
8. **Variables y arranque:**
   ```
   cd compose && cp .env.example .env && chmod 0600 .env
   # editar NODE_NAME y PUBLISH_IP
   sudo docker compose config --quiet && sudo docker compose up -d
   ```

## Verificación

```
sudo docker compose ps                                  # Up ... (healthy)
curl -sI -H "Host: www.lab08.nodosur.cl" http://IP_DEL_NODO/ | head -5    # 200 y X-Backend del nodo
sudo iptables -S DOCKER-USER                            # regla del puerto 80
```

Desde VM4, que no es el balanceador, `nc -zv -w3 IP_DEL_NODO 80` debe terminar en `timed out`, y `nc -zv -w3 IP_DEL_NODO 22` en `succeeded`. Desde VM1, el nodo debe aparecer `UP`, `L7OK` y `200` en el panel de HAProxy.

**Validación automática, de solo lectura:** `./scripts/validar.sh nodo` en VM2 o VM3, y `./scripts/validar.sh balanceador` en VM1. Cada comprobación imprime `[ OK ]` o `[FALLA]`, y el script termina con código distinto de cero si alguna falla.

## Reversión

```
cd compose && sudo docker compose down && sudo systemctl enable --now apache2
```

El Apache nativo sigue instalado y configurado, pero deshabilitado. El montaje NFS del host en `/etc/fstab` se conserva, justo por esto: es el de la línea base nativa, y el contenedor no lo necesita.

## Decisiones y límites

- **Una sola imagen, con `mod_php`.** El informe de la Entrega 1 justificó PHP-FPM sobre `mod_php`. Los nodos nativos usaban PHP-FPM, y el contenedor usa el Apache de la imagen oficial (`sapi=apache2handler`). Es una desviación declarada.
- **Los secretos no están en el Compose, en el `.env` ni en una imagen.** Viven en `wp-config.php` del host.
- **Docker publica los puertos sin pasar por UFW.** Se comprobó: desde VM4, el puerto publicado respondía y el nativo no. La regla de `DOCKER-USER` lo corrige, y se reaplica en cada arranque.
- **Ventana al arrancar.** El contenedor podría publicar el puerto unos instantes antes de que `systemd` aplique la regla. No se midió.
- **VM4 es un punto único de falla** de la base y del NFS. El montaje es `hard`: si VM4 no responde, el contenedor no arranca y el balanceador lo retira, en vez de servir un sitio sin sus plugins.
- **Las pruebas de falla y de reinicio** de ambos nodos están en `evidencia-e3/`.
