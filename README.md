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

---

## Índice del repositorio por entrega

*Sección agregada el 23/11/2026 en la Entrega 4. Lo anterior de este README
corresponde a la Entrega 2 y se conserva sin cambios.*

| Entrega | Carpeta | Contenido | Etiqueta |
|---|---|---|---|
| 1 · Requerimientos y arquitectura | `entrega-1/` | Decisiones de arquitectura y bitácora | `E01` |
| 2 · Plataforma base y CMS | raíz (`configs/`, `evidencias/`, `inventario.txt`, bitácoras) | Instalación nativa en una VM, configuraciones saneadas y evidencias | `E02` |
| 3 · Publicación resiliente | `entrega_3/` | Nodo web en Docker Compose, regla `DOCKER-USER`, script de validación y bitácora | `E03` |
| 4 · Observabilidad y continuidad | `entrega-4/` | Monitoreo (Prometheus, Alertmanager, Grafana), alertas por correo, registros centralizados, respaldo y restauración, runbook, auditoría y bitácora | `E04` |

**Arquitectura actual:** cuatro VMs. VM1 `proxy1` (DNS, HAProxy con TLS,
monitoreo, correo, registros centrales), VM2 `web1` y VM3 `web2` (WordPress
7.1.3 en contenedores) y VM4 `db1` (MariaDB, NFS y respaldo automático). El
diagrama está en `entrega-4/capturas/E4_arquitectura_final.png` y el detalle
en `entrega-4/README.md`.

**Secretos:** ninguna carpeta contiene contraseñas, llaves privadas ni datos
personales. Los valores reales viven en archivos `.env` excluidos por
`.gitignore`; se publican solo los `.env.example`.
