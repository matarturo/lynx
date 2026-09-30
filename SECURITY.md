# Política de seguridad

## Versiones soportadas

Reciben parches de seguridad:

| Versión | Soportada |
|---------|-----------|
| 3.x     | ✅        |
| < 3.0   | ❌        |

## Reportar una vulnerabilidad

**No abras un issue público para reportar una vulnerabilidad.**

Usa una de estas vías privadas:

1. **GitHub Security Advisories** (preferido):
   https://github.com/matarturo/lynx/security/advisories/new
2. **Correo:** arturo.mata@gmail.com con asunto `[Lynx] Security report`.

Incluye, si puedes:

- Descripción del problema y su impacto.
- Pasos para reproducirlo (distribución, versión de Lynx, comandos).
- Fragmento del reporte o del código afectado.
- Si lo deseas, una propuesta de parche.

## Qué esperar

- **Acuse de recibo:** en 72 horas.
- **Evaluación inicial:** en 7 días.
- **Parche o mitigación:** en 30 días para problemas confirmados.
- **Crédito público:** si lo deseas, en el CHANGELOG y en el aviso de seguridad.

## Alcance

Lynx es una herramienta **pasiva**: solo lee el sistema. Aun así, se
consideran vulnerabilidades:

- Ejecución arbitraria de comandos a través de datos del sistema
  (por ejemplo, un nombre de usuario o una regla de firewall que se
  interprete como comando).
- Escritura fuera de `REPORT_DIR` o del directorio de evidencias.
- Fuga de hashes de contraseñas desde `/etc/shadow` al reporte o las evidencias.
- Elevación de privilegios a partir de la ejecución de Lynx.
- Manipulación del manifiesto SHA-256 sin detección.

## Fuera de alcance

- Resultados incorrectos que no impliquen un riesgo de seguridad
  (repórtalos como bug normal).
- Falsos positivos en los controles (bug, no vulnerabilidad).
- Problemas derivados de ejecutar Lynx en un sistema ya comprometido.

## Reconocimiento

Agradezco públicamente a quienes reportan vulnerabilidades de forma
responsable, salvo que prefieran permanecer en el anonimato.
