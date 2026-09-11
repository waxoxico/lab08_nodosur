# Registro de decisiones de arquitectura — Entrega 1

**Grupo Tas_08 · Proyecto Nodo Sur 2026**

---

## AD-01 · Selección del CMS

**Decisión:** WordPress + WooCommerce

**Alternativas evaluadas:** PrestaShop, Drupal + Drupal Commerce, OpenCart

**Fundamento:** Nodo Sur necesita tanto venta en línea como publicación de contenido informativo (novedades, reservas de talleres). Las plataformas dedicadas de ecommerce (PrestaShop, OpenCart) resuelven bien el catálogo pero dejan el contenido en segundo plano. Drupal ofrece mayor robustez pero consume entre 512 MB y 1 GB de RAM solo para PHP, inviable con el límite de 2 GB por nodo.

**Consecuencia:** se asume dependencia del ecosistema de plugins de WordPress y la necesidad de mantenerlos actualizados.

---

## AD-02 · PHP-FPM sobre mod_php

**Decisión:** ejecutar PHP como servicio independiente (PHP-FPM) en lugar de integrado en Apache

**Fundamento:** permite limitar explícitamente la cantidad de procesos PHP concurrentes y su consumo de memoria, factor relevante con 2 GB de RAM por nodo. Con mod_php cada proceso de Apache carga el intérprete completo, incluso al servir contenido estático.

**Consecuencia:** un servicio adicional que administrar y monitorear.

---

## AD-03 · Separación de roles entre las 4 VMs

**Decisión:** VM1 (DNS + HAProxy), VM2 y VM3 (nodos web equivalentes), VM4 (MariaDB + NFS)

**Alternativa descartada:** replicar el stack completo en las cuatro VMs

**Fundamento:** para que la plataforma se comporte como un solo sitio, el estado (base de datos y archivos) debe vivir fuera de los nodos web. De lo contrario, cada VM sería un sitio independiente y la caída de una implicaría perder su contenido.

**Consecuencia:** VM1 y VM4 se convierten en puntos únicos de falla, aceptados por la restricción de 4 VMs.

---

## AD-04 · Dominio `lab08.nodosur.cl`

**Decisión:** usar el sufijo `.cl` en lugar de `.local`

**Fundamento:** el sufijo `.local` está reservado por el RFC 6762 para Multicast DNS y genera conflictos con el servicio Avahi presente en clientes Linux y macOS. La herramienta `dig` emite una advertencia explícita al usarlo.

**Consecuencia:** el dominio no está registrado públicamente; los clientes deben usar el DNS del proyecto para resolverlo.

---

## AD-05 · Segmentación en dos redes

**Decisión:** red de administración (10.33.195.0/25) separada de la red interna del proyecto (10.33.199.64/29)

**Fundamento:** MariaDB y NFS no deben ser alcanzables desde fuera del proyecto. Al no tener interfaz en la red de administración, quedan inaccesibles por topología, no solo por reglas de firewall.

**Consecuencia:** solo VM1 expone servicios en ambas interfaces; el resto depende de ella como punto de entrada.

---

## AD-06 · Terminación TLS en el balanceador

**Decisión:** el certificado se instala en HAProxy; el tráfico hacia los backends viaja sin cifrar por la red interna

**Fundamento:** un solo certificado que gestionar en lugar de tres. La red interna es un segmento controlado sin acceso externo.

**Consecuencia:** si la red interna se viera comprometida, el tráfico entre balanceador y backends sería legible.

---

## AD-07 · Puntos únicos de falla aceptados

**Decisión:** se aceptan tres SPOF (HAProxy en VM1, MariaDB en VM4, NFS en VM4)

**Fundamento:** su mitigación completa requeriría instancias adicionales en modo activo-pasivo, réplica de base de datos o almacenamiento distribuido. El equipo dispone de exactamente 4 máquinas virtuales sin posibilidad de ampliación.

**Consecuencia:** la plataforma logra balanceo de carga y tolerancia a falla de nodos web, pero no alta disponibilidad completa. Esta distinción se documenta explícitamente en el informe.

---

## AD-08 · Almacenamiento compartido mediante NFS

**Decisión:** centralizar `wp-content` en VM4 y montarlo desde VM2 y VM3

**Alternativa descartada:** sincronización periódica entre nodos

**Fundamento:** sin almacenamiento compartido, un archivo subido desde un nodo no existe en el otro, y el sitio se comporta distinto según cuál atienda la solicitud. La sincronización periódica deja ventanas de inconsistencia.

**Consecuencia:** NFS se suma a los puntos únicos de falla del nodo de datos.
