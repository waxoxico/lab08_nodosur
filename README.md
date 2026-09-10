# Nodo Sur — Entrega 2: Plataforma base y CMS funcional

**Grupo:** Tas_08
**Asignatura:** EIN-090B · Taller de Administración de Sistemas
**Docente:** José Antonio Arellano V.
**Fecha:** 10 de septiembre de 2026

---

## Resumen

Implementación de la plataforma base para Nodo Sur sobre Ubuntu Server 24.04, con CMS WordPress + WooCommerce, DNS autoritativo propio, publicación HTTPS y administración remota segura.

## Infraestructura

| Elemento | Valor |
|---|---|
| Hostname | `web1` |
| Sistema operativo | Ubuntu Server 24.04.5 LTS (kernel 6.8.0-139) |
| Recursos | 2 vCPU · 2 GB RAM · 97 GB disco |
| Red de administración | `10.33.195.234/25` (estática) |
| Red interna del proyecto | `10.33.199.66/29` (estática) |
| Gateway | `10.33.195.129` |
| Dominio | `www.lab08.nodosur.cl` |

## Servicios desplegados

| Servicio | Versión | Puerto | Alcance |
|---|---|---|---|
| Apache HTTP Server | 2.4.58 | 80, 443 | Público |
| PHP-FPM | 8.3.6 | socket | Local |
| MariaDB | 10.11.14 | 3306 | Solo `127.0.0.1` |
| BIND9 | 9.18.39 | 53 | Redes autorizadas |
| OpenSSH | — | 22 | Red de administración y VPN |

## Decisiones técnicas

**PHP-FPM sobre mod_php.** Permite administrar los procesos PHP de forma independiente de Apache y limitar su consumo de memoria, relevante dado el límite de 2 GB de RAM por nodo.

**Certificado TLS autofirmado.** No se dispone de una autoridad certificadora institucional; el certificado se genera localmente y se documenta como deuda técnica a resolver con una CA interna o Let's Encrypt.

**MariaDB restringida a `127.0.0.1`.** En esta entrega la base de datos reside en la misma VM que el servidor web; la separación física corresponde a la arquitectura objetivo definida en Entrega 1 y se implementará en Entrega 3.

**Dominio `.cl` en lugar de `.local`.** El sufijo `.local` está reservado por RFC 6762 para mDNS y genera conflictos con Avahi, detectados durante la configuración inicial.

## Estructura del repositorio
clear

## Verificación rápida

```bash
# Resolución DNS
dig @10.33.195.234 www.lab08.nodosur.cl +short

# Redirección HTTP → HTTPS
curl -I http://www.lab08.nodosur.cl

# Sitio en HTTPS
curl -k -I https://www.lab08.nodosur.cl

# SSH con contraseña (debe ser rechazado)
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no mgonzalez@10.33.195.234
```

## Respaldo y recuperación

- **Base de datos:** `mysqldump` diario a las 02:00 vía cron
- **Archivos:** `rsync` de `wp-content` diario a las 02:30
- **Retención:** 30 días con rotación (`logrotate`)
- **Integridad:** checksums SHA-256 en `evidencias/checksums.txt`
- **Ensayo de restauración:** documentado en `evidencias/ensayo-restauracion.txt` — 97 tablas restauradas, RTO < 1 min (objetivo ≤ 60 min), RPO < 24 h

## Deuda técnica

| Pendiente | Entrega prevista |
|---|---|
| Separación física de la base de datos en VM dedicada | Entrega 3 |
| Balanceo de carga con HAProxy y segundo nodo web | Entrega 3 |
| Terminación TLS en el balanceador | Entrega 3 |
| Certificado emitido por CA reconocida | Por definir |
| Monitorización (Prometheus/Grafana o equivalente) | Entrega 4 |
| Servidor de correo para notificaciones de WooCommerce | Por definir |

## Nota sobre credenciales

Ninguna configuración de este repositorio contiene contraseñas, llaves privadas ni datos personales. El archivo `configs/wp-config.php.ejemplo` tiene sus credenciales reemplazadas por `REDACTADO`.
