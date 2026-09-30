---
name: Reporte de bug
about: Algo no funciona como debería en Lynx
title: '[BUG] '
labels: ['bug', 'triage']
assignees: ''
---

<!--
Antes de abrir este issue:
1. Comprueba que no exista ya uno igual: https://github.com/matarturo/lynx/issues
2. Ejecuta `./lynx.sh --version` y ten a mano el resultado.
3. Anonimiza IPs, usuarios y rutas antes de pegar salidas.
-->

## Descripción del problema

<!-- Explica en 2-3 frases qué ocurre. -->

## Pasos para reproducirlo

1.
2.
3.

## Comportamiento esperado

<!-- Qué esperabas que hiciera Lynx. -->

## Comportamiento observado

<!-- Qué hizo realmente. Si puedes, pega el fragmento exacto del reporte. -->

## Entorno

| Campo | Valor |
|---|---|
| Distribución | <!-- p.ej. Debian 12.7 --> |
| Versión del kernel | <!-- `uname -r` --> |
| Versión de Lynx | <!-- `./lynx.sh --version` --> |
| Bash | <!-- `bash --version` --> |
| systemd | <!-- sí / no --> |
| Backend de firewall | <!-- iptables-legacy / iptables-nft / nftables / ninguno --> |

## Información adicional

<!-- Salidas que ayuden a diagnosticar:

- `iptables --version` (y `update-alternatives --display iptables`)
- `nft --version`
- `sshd -V`
- Variables de entorno con las que ejecutaste Lynx (REPORT_DIR, ES_ROUTER, etc.)

Pega solo las líneas relevantes, no el reporte completo.
-->

## Salida con `bash -x` (opcional)

<!-- Si el bug es difícil de reproducir, ejecuta:

sudo bash -x ./lynx.sh 2> lynx_debug.txt

y adjunta las últimas 50 líneas de lynx_debug.txt (revisa que no haya datos sensibles).
-->
