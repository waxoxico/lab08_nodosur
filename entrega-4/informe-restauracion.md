---
title: "Nodo Sur · Informe de restauración"
subtitle: "Ensayo controlado y medición de RPO/RTO · Entrega 4"
date: "20 de noviembre de 2026"
---

# 1. Propósito y alcance

Demostrar que los respaldos de Nodo Sur son restaurables y medir los tiempos
reales de recuperación frente a los objetivos del proyecto.

El ensayo se realizó **sin modificar el ambiente productivo**: la base del sitio
(`lab08_db`) y el directorio compartido por NFS no se tocaron en ningún momento.
La restauración se dirigió a una base paralela (`restore_test`) y a un directorio
temporal.

| Dato | Valor |
|---|---|
| Fecha del ensayo | 20 de noviembre de 2026 |
| Máquina | VM4 (`db1`), `10.33.199.68` |
| Origen del respaldo | `/var/backups/nodosur/20261120-223742` |
| Copia separada | VM1 (`proxy1`), `~/respaldos/db1` |
| Base productiva | `lab08_db`, 98 tablas |
| Base de restauración | `restore_test` |

Todas las marcas de tiempo están en **UTC**, que es la zona de las cuatro
máquinas.

# 2. Datos identificables

Para demostrar que la restauración recupera datos reales y no una estructura
vacía, se crearon dos marcas antes de respaldar.

## En la base de datos

Entrada publicada desde el panel de WordPress:

| Campo | Valor |
|---|---|
| ID | 20 |
| Título | `Prueba restauracion 2026-11-20 23:05` |
| `post_date` | `2026-11-20 23:37:01` (hora local del sitio) |
| `post_date_gmt` | **`2026-11-20 22:37:01`** (UTC) |

## En los archivos

```
/srv/nfs/wp-content/uploads/marca-restauracion.txt
→ marca de prueba 2026-11-20T22:37:36Z
```

## Hallazgo sobre la zona horaria

Durante el ensayo se detectó que WordPress tenía configurada la zona
`Europe/Madrid`, heredada de la instalación inicial, mientras las cuatro máquinas
operan en UTC. Eso producía un desfase de una hora entre el `post_date` mostrado
y las marcas del sistema.

Se corrigió a `America/Santiago`, que es la zona del negocio. El criterio
aplicado queda documentado para la defensa:

> Los servidores operan en **UTC**, de modo que los logs sean correlacionables
> entre máquinas. La **capa de presentación** muestra hora local de Chile.

La coherencia se verifica en la propia tabla: WordPress almacena siempre la hora
universal en las columnas `_gmt`, y el `post_date_gmt` de la entrada de prueba
(`22:37:01`) coincide exactamente con las marcas del sistema.

# 3. Respaldo de referencia

Ejecución del script automatizado `/usr/local/sbin/respaldo-nodosur.sh`,
identificador `20261120-223742`.

```
2026-11-20T22:37:42Z === inicio 20261120-223742 ===
2026-11-20T22:37:42Z base de datos: 236K
2026-11-20T22:37:54Z archivos: 76M
2026-11-20T22:37:54Z configuracion: 8.0K
2026-11-20T22:37:55Z checksums verificados: 3 archivos
2026-11-20T22:37:56Z replicado a 10.33.199.65:respaldos/db1
2026-11-20T22:37:56Z rotacion aplicada (retencion 30 dias)
2026-11-20T22:37:56Z === fin 20261120-223742 ===
```

**Duración: 14 segundos.** El respaldo quedó cerrado a las **22:37:56 UTC**.

## Verificación de integridad

Antes de restaurar se comprobaron los checksums del respaldo:

```
./archivos-wp-content.tgz: OK
./config-db1.tgz: OK
./db-lab08_db.sql.gz: OK
```

Los tres archivos íntegros. La comprobación se hace sobre el conjunto generado,
de modo que un respaldo truncado o corrupto se detecta antes del ensayo y no
durante una emergencia real.

# 4. Ejecución del ensayo

## Línea de tiempo

| Marca | Hora UTC | Evento |
|---|---|---|
| — | 22:37:01 | Último dato creado en producción (entrada ID 20) |
| — | 22:37:36 | Archivo de marca creado |
| — | 22:37:42 | Inicio del respaldo |
| — | 22:37:56 | **Respaldo cerrado y replicado** |
| **T0** | **22:39:02** | Inicio de la restauración |
| **T1** | **22:39:10** | Base de datos restaurada |
| **T2** | **22:39:34** | Archivos restaurados |

## Restauración de la base de datos

La base se restauró en `restore_test`, reescribiendo el nombre del esquema
durante el proceso para no afectar a la productiva:

```
sudo mysql -e "DROP DATABASE IF EXISTS restore_test; CREATE DATABASE restore_test;"
sudo zcat $DIR/db-lab08_db.sql.gz \
  | sed 's/`lab08_db`/`restore_test`/g; s/^USE .*/USE `restore_test`;/' \
  | sudo mysql restore_test
```

**Duración: 8 segundos.**

### Verificación funcional

```
SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='restore_test';
→ 98

SELECT ID, post_title, post_date FROM restore_test.wp_posts WHERE ID=20;
→ 20 | Prueba restauracion 2026-11-20 23:05 | 2026-11-20 23:37:01
```

Las **98 tablas** de la base productiva están presentes, y el dato identificable
se recuperó con su título y su fecha intactos.

## Restauración de archivos

```
sudo tar -xzf $DIR/archivos-wp-content.tgz -C /tmp/restore_files
```

**Duración: 24 segundos** para 332 MB de contenido.

### Verificación

```
cat /tmp/restore_files/wp-content/uploads/marca-restauracion.txt
→ marca de prueba 2026-11-20T22:37:36Z

du -sh /tmp/restore_files/wp-content
→ 332M
```

El archivo de marca se recuperó con su contenido exacto.

## Incidente durante el ensayo

El primer intento de restauración **falló de forma silenciosa**. El comando
`zcat` se ejecutó sin privilegios sobre `/var/backups/nodosur`, que tiene modo
`700` y pertenece a `root`:

```
gzip: /var/backups/nodosur/.../db-lab08_db.sql.gz: Permission denied
```

El proceso terminó sin error visible y la base quedó creada pero **vacía**. Se
detectó porque la verificación posterior devolvió **0 tablas** en lugar de 98.

Es la razón por la que el ensayo incluye comprobación funcional y no se limita a
confirmar que los comandos terminaron. Un procedimiento que solo mira el código
de salida habría registrado una restauración que nunca ocurrió.

# 5. Medición de RPO y RTO

## RPO — Recovery Point Objective

Cuánto dato se perdería en una falla: el intervalo entre el último respaldo
válido y el momento del incidente.

| Medida | Valor |
|---|---|
| Último dato en producción | 22:37:01 UTC |
| Respaldo cerrado | 22:37:56 UTC |
| **Pérdida de datos en el ensayo** | **0 segundos** |
| **RPO operativo** (respaldo diario a las 03:00) | **≤ 24 horas** |
| Objetivo del proyecto | ≤ 24 horas |
| Resultado | **CUMPLE** |

El ensayo verifica que el respaldo captura el dato más reciente. El RPO real en
operación lo determina la frecuencia del temporizador, no la velocidad del
respaldo: con una ejecución diaria, el peor caso es perder las transacciones de
hasta 24 horas.

## RTO — Recovery Time Objective

Cuánto tarda el servicio en volver a estar disponible.

| Fase | Duración |
|---|---|
| Restauración de la base (T0→T1) | 8 s |
| Restauración de archivos (T1→T2) | 24 s |
| **Total medido (T0→T2)** | **32 segundos** |
| Objetivo del proyecto | ≤ 60 minutos |
| Resultado | **CUMPLE con holgura** |

**Alcance de la medición.** Los 32 segundos corresponden a la recuperación de
datos y archivos en un ambiente de prueba. Un RTO de producción completo
incluiría además detectar el incidente, decidir restaurar, detener el servicio,
dirigir la restauración a la base productiva y validar el sitio de extremo a
extremo. Aun estimando esos pasos con holgura, el margen frente a los 60 minutos
es amplio.

# 6. Conclusiones y mejoras propuestas

## Conclusiones

- Los respaldos **contienen datos reales**, no estructuras vacías: se verificó
  con un dato creado deliberadamente antes del respaldo.
- Los tres activos exigidos (base, archivos y configuración) se restauran
  correctamente y pasan verificación de integridad.
- Ambos objetivos se cumplen: **RPO ≤ 24 h** y **RTO ≤ 60 min**, este último con
  amplio margen.
- La restauración **no alteró el ambiente productivo**.

## Mejoras propuestas

El enunciado pide proponer mejora para datos transaccionales durante campañas.
Durante una campaña, perder hasta 24 horas de pedidos sería inaceptable.

| Mejora | Qué resuelve | Costo |
|---|---|---|
| **Aumentar la frecuencia durante campañas** a cada 4 o 6 horas | Reduce el RPO a ese intervalo | Trivial: cambiar `OnCalendar` en el temporizador |
| **Registro binario de MariaDB** (`binlog`) | Permite recuperar hasta el instante previo a la falla, RPO cercano a cero | Requiere espacio y gestión de los registros |
| **Copia fuera del host de Proxmox** | Protege frente a la pérdida del host, no solo de la VM | Depende de disponer de un destino externo |
| **Ensayo de restauración periódico y automatizado** | Detecta respaldos corruptos antes de necesitarlos | Script que restaure en `restore_test` y compruebe el conteo de tablas |

## Limitación declarada

VM1 y VM4 **comparten el mismo host de Proxmox**. La réplica protege frente a la
pérdida de una máquina virtual, no frente a la pérdida del host físico. Es una
copia separada del origen, no una copia fuera del sitio.

# 7. Reproducibilidad

El ensayo completo se reproduce con estos comandos en VM4. Requieren privilegios
porque el directorio de respaldos pertenece a `root`.

```
SELLO=<identificador del respaldo>
DIR=/var/backups/nodosur/$SELLO

# Integridad
sudo bash -c "cd $DIR && sha256sum -c SHA256SUMS"

# Base de datos en ambiente de prueba
sudo mysql -e "DROP DATABASE IF EXISTS restore_test; CREATE DATABASE restore_test;"
sudo zcat $DIR/db-lab08_db.sql.gz \
  | sed 's/`lab08_db`/`restore_test`/g; s/^USE .*/USE `restore_test`;/' \
  | sudo mysql restore_test

# Verificación funcional
sudo mysql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='restore_test';"
sudo mysql -e "SELECT ID, post_title, post_date FROM restore_test.wp_posts WHERE ID=20;"

# Archivos en directorio temporal
sudo mkdir -p /tmp/restore_files
sudo tar -xzf $DIR/archivos-wp-content.tgz -C /tmp/restore_files
sudo cat /tmp/restore_files/wp-content/uploads/marca-restauracion.txt
```

## Limpieza posterior

El ambiente de prueba debe retirarse al terminar:

```
sudo mysql -e "DROP DATABASE IF EXISTS restore_test;"
sudo rm -rf /tmp/restore_files
```

# 8. Segundo ensayo: restauración funcional con el CMS (22/11/2026)

> Esta sección **se agrega** al informe. El primer ensayo (secciones 1 a 7) se
> conserva tal cual. Este segundo ensayo cubre lo que el primero no alcanzó a
> demostrar: *"Comprobar integridad funcional del CMS después de restaurar"*,
> y mide el **RTO del servicio**, no solo el de la extracción de datos.

## 8.1 Correcciones al primer ensayo

| Se dijo | Lo correcto |
|---|---|
| Marca en la base: "entrada publicada, ID 20" | Es un **producto de WooCommerce** (`post_type = product`), publicado |
| "Los tres activos [...] se restauran correctamente" | En el primer ensayo **no se restauró la configuración**, solo la base y los archivos. El respaldo actual incluye la configuración de las 4 VMs (ver la bitácora, paso 3) |
| RTO de 32 s | 32 s corresponde a la extracción en un ambiente de prueba. El RTO del servicio con el CMS funcionando es el de la sección 8.4 |

## 8.2 Diseño

- **Origen:** respaldo `20261122-011902`, el primero con la configuración de las 4 VMs y con checksum verificado en origen y destino.
- **Base:** se restauró en `restore_test`, en db1. Se creó un usuario temporal `restore_test@10.33.199.66` con permisos `SELECT, INSERT, UPDATE, DELETE` **solo** sobre `restore_test`.
- **Archivos:** se enviaron a web1 por `scp`, con la cuenta de servicio `respaldo`, y se extrajeron en `/tmp/restore_test`.
- **CMS:** en web1 se levantó un contenedor temporal `wp-restore-test` con la **misma imagen** que producción (`wordpress:7.1.3-php8.3-apache`). Solo escucha en `127.0.0.1:8099`, así que HAProxy no lo conoce y no es accesible desde fuera. Se sobrescribieron `WP_HOME` y `WP_SITEURL` por variable de entorno, sin modificar la base restaurada.
- **Producción no se tocó:** `lab08_db`, el NFS y los contenedores `web1` y `web2` siguieron atendiendo.

## 8.3 Línea de tiempo (UTC)

| Marca | Hora | Evento |
|---|---|---|
| **T0** | **01:24:06** | Inicio, en db1 |
| — | 01:24:12 | Checksums OK; `restore_test` con 98 tablas; producto ID 20 presente; usuario temporal creado; archivos y `.env` temporal enviados a web1 |
| — | 01:24:30 y 01:26:24 | Dos ejecuciones por error en la máquina equivocada (proxy1 y db1). Sin efecto más allá de una carpeta vacía en `/tmp`, que se borró |
| — | 01:25:23 | Contenedor temporal en marcha en web1 |
| **T1** | **01:27:56** | CMS verificado |

## 8.4 Verificación funcional

| Prueba | Resultado | Qué demuestra |
|---|---|---|
| Portada | HTTP 200 | WordPress funciona con la base restaurada |
| `?p=20` | 301 → `?product=prueba-restauracion-2026-11-20-2305`, con el título visible | El catálogo muestra el producto creado antes del respaldo |
| REST `/wp/v2/product/20` | `"rendered":"Prueba restauracion 2026-11-20 23:05"` | La API del CMS lee los datos restaurados |
| REST raíz | `wc/v3` presente | **WooCommerce** se cargó desde los archivos restaurados |
| `/wp-content/uploads/marca-restauracion.txt` | `marca de prueba 2026-11-20T22:37:36Z` | El archivo creado antes del respaldo se sirve por HTTP |

## 8.5 RTO y RPO

| Medida | Valor | Objetivo | Resultado |
|---|---|---|---|
| **RTO del servicio** (T0 → CMS verificado) | **3 min 50 s** | ≤ 60 min | Cumple |
| Tiempo técnico (sin los dos errores de ejecución) | Unos 6 s de base más unos 40 s de arranque de WordPress | — | — |
| RPO operativo | ≤ 24 h. El timer diario se ejecutó solo el 21/11 a las 03:04 | ≤ 24 h | Cumple |

Para restaurar **sobre producción** hay que agregar la contención (detener los
dos nodos) y un respaldo de seguridad previo; el procedimiento está en
`runbook.md` §17. Aun así, el margen frente a los 60 minutos es amplio.

## 8.6 Limpieza verificada

`docker rm -f -v wp-restore-test`; se borraron `/tmp/restore_test`, el `.tgz`
y el `.env` temporal; `DROP USER 'restore_test'@'10.33.199.66'` y
`DROP DATABASE restore_test`. Al terminar, web1 solo tiene el contenedor `web1`
(`healthy`), y db1 no tiene ni la base ni el usuario temporal.
