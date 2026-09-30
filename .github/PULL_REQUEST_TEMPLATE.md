<!--
Gracias por enviar un PR a Lynx.
Antes de continuar, asegúrate de haber leído CONTRIBUTING.md.
-->

## Qué cambia este PR

<!-- Resumen en 1-3 frases. Si cierra un issue, enlázalo: "Cierra #12". -->

## Tipo de cambio

- [ ] Bugfix (cambio que corrige un comportamiento incorrecto)
- [ ] Nueva funcionalidad (control nuevo, mejora)
- [ ] Cambio de comportamiento (los usuarios notarán la diferencia)
- [ ] Documentación
- [ ] Refactor / limpieza interna
- [ ] CI / tooling

## ¿Rompe compatibilidad?

- [ ] No
- [ ] Sí, y lo explico abajo

<!-- Si rompe, indica qué deja de funcionar y cómo migrar. -->

## Checklist del contribuidor

- [ ] He leído `CONTRIBUTING.md` y respeto el carácter **pasivo** de Lynx.
- [ ] `bash -n lynx.sh` termina sin errores.
- [ ] `shellcheck --severity=warning lynx.sh` termina sin advertencias.
- [ ] He ejecutado el script en una máquina de prueba.
- [ ] He actualizado el `README.md` si el cambio lo requiere.
- [ ] He actualizado el `CHANGELOG.md` en la sección `[No publicado]`.
- [ ] Si añado un control, sigue el contrato `chk_*` y su peso está justificado.
- [ ] No incluyo datos sensibles (IPs reales, usuarios reales, hashes).

## Cómo se ha probado

<!-- Distribución, versión, comandos. Ejemplo:
Ubuntu 24.04 en VM, sin systemd ni iptables.
Probado con volcados simulados de fwbuilder y nftables nativo.
-->

## Capturas o salida (opcional)

<!-- Si aplica, pega un fragmento del reporte antes/después. -->

## Notas para el revisor

<!-- Cualquier cosa que ayude a entender el PR: decisiones, dudas, alternativas. -->
