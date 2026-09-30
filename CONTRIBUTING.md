# Contribuir a Lynx

Gracias por considerar contribuir. Lynx es una herramienta pequeña y
mantenida por voluntad propia; agradezco especialmente los reportes bien
detallados y los PRs pequeños y enfocados.

## Principio irrenunciable: pasivo por diseño

Lynx **solo lee**. Cualquier contribución debe respetar estas reglas:

- No modificar configuración del sistema.
- No instalar, eliminar ni actualizar paquetes.
- No reiniciar servicios ni ejecutar comandos que alteren el estado del host.
- No escribir fuera de `REPORT_DIR` y del directorio de evidencias.

Un PR que rompa estos principios será rechazado aunque técnicamente funcione.

## Entorno de desarrollo

Necesitas:

- Bash 4.4 o superior (`bash --version`).
- `shellcheck` (`sudo apt-get install shellcheck`).
- Opcional: `bats-core` si añades tests.

## Antes de enviar un PR

Ejecuta en local exactamente lo que corre el CI:

```bash
bash -n lynx.sh
shellcheck --severity=warning lynx.sh
