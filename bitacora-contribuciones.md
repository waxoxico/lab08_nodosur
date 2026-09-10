# Bitácora de contribuciones — Entrega 2

**Grupo Tas_08 · Nodo Sur 2026**

| Actividad | Matías González | Javier Saavedra | Yovani Contreras | Aníbal Villablanca |
|---|---|---|---|---|
| Instalación y actualización de Ubuntu Server | ✓ | ✓ | ✓ | ✓ |
| Configuración de hostname, red estática y NTP | ✓ | ✓ | ✓ | ✓ |
| Endurecimiento de SSH (llaves, sin root, sin contraseña) | ✓ | ✓ | ✓ | ✓ |
| Configuración de firewall UFW por origen | ✓ | ✓ | ✓ | ✓ |
| Instalación de Apache, PHP-FPM y WordPress | ✓ | ✓ | ✓ | ✓ |
| Instalación y restricción de MariaDB | ✓ | ✓ | ✓ | ✓ |
| Configuración de BIND9 y zona `lab08.nodosur.cl` | ✓ | ✓ | ✓ | ✓ |
| Generación de certificado y publicación HTTPS | ✓ | ✓ | ✓ | ✓ |
| Instalación de WooCommerce y prueba de flujo de compra | ✓ | ✓ | ✓ | ✓ |
| Configuración de respaldos y ensayo de restauración | ✓ | ✓ | ✓ | ✓ |
| Recopilación de evidencias y redacción de bitácora | ✓ | ✓ | ✓ | ✓ |

## Nota metodológica

Cada integrante implementó la pila completa de forma independiente en su VM asignada, con el objetivo de asegurar dominio individual de todos los componentes antes de especializar roles en la arquitectura objetivo definida en la Entrega 1. Esta decisión responde al requisito del enunciado: *"cada integrante debe operar y explicar cualquier componente de la solución"*.

La VM documentada en este repositorio (`web1`, 10.33.195.234) corresponde a la instancia de Matías González, seleccionada como referencia para la entrega.

## Registro de uso de inteligencia artificial

| Campo | Detalle |
|---|---|
| **Herramienta** | Claude (Anthropic) |
| **Propósito** | Diagnóstico de errores de configuración, revisión de coherencia entre documentación e implementación, y apoyo en la redacción técnica |
| **Validación** | Todos los comandos fueron ejecutados y verificados en la VM antes de documentarse. Las salidas reales de cada comando constan en `evidencias/`. Varias sugerencias iniciales fueron corregidas al contrastarlas con el estado real del sistema (rangos de red, nombres de servicios, rutas de archivos) |
| **Límite declarado** | Ningún comando o configuración fue incorporado sin haber sido comprendido por al menos un integrante, conforme a la regla: *"el código o comando que ningún integrante pueda explicar se considera no defendido"* |
