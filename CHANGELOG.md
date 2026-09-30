# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).

## [No publicado]

### Por añadir
- Validación en servidores Debian 13 reales.
- Códigos de salida diferenciados para integración en CI.
- Salida opcional en JSON (`--format=json`).

## [3.0.0] - 2026-09-30

### Añadido
- Soporte completo para los tres backends de firewall: `iptables-legacy`,
  `iptables-nft` y `nftables` nativo. Se leen en paralelo porque las reglas
  de un backend no son visibles desde el otro.
- Detección heurística de **fwbuilder**: paquete instalado, scripts `*.fw`
  generados y su carga al arranque.
- Detección de **persistencia del firewall**: avisa si hay reglas cargadas
  sin mecanismo que las restaure tras un reinicio.
- Detección de reglas **stateful** en los tres formatos: `-m state --state`
  (fwbuilder), `-m conntrack --ctstate` y `ct state` de nftables.
- Seguimiento de **saltos a cadenas de usuario** (`-A INPUT -j RULE_N ...`)
  para detectar una denegación final aunque la política de la cadena sea ACCEPT.
- Generación de **evidencias crudas** con manifiesto SHA-256 verificable.
- Variables de entorno: `REPORT_DIR`, `ES_ROUTER`, `SIN_EVIDENCIAS`,
  `SKIP_SLOW`, `TIMEOUT_FIND`.
- 29 controles puntuables agrupados en 6 secciones con peso sobre 100 puntos.
- Sección 7 de información complementaria (puertos, servicios, sudoers,
  parches, montajes, inventarios SUID/SGID, world-writable y huérfanos).

### Cambiado
- Reescritura completa del motor de auditoría respecto a versiones previas.
- Lectura de sysctl directamente desde `/proc/sys` (no requiere el binario `sysctl`).
- Los controles N/A ahora **suman puntos** en lugar de restarlos.

### Seguridad
- El reporte se escribe con permisos `600` y el directorio de evidencias con `700`.
- Lynx no copia hashes de contraseñas de `/etc/shadow` en ningún caso.

[No publicado]: https://github.com/matarturo/lynx/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/matarturo/lynx/releases/tag/v3.0.0
