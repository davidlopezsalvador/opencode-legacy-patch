# opencode-legacy-patch

Restaura la **interfaz legacy de OpenCode Desktop (Windows)** parcheando la "sunset date"
de 1 línea que OpenCode forzó el 14-sep-2026 para obligar a la UI nueva.

- **Método**: parche binario *same-length* sobre `app.asar` de la app instalada (sin recompilar nada, sin toolchain, sin binarios de terceros).
- **Probado en**: OpenCode Desktop **1.18.35** (Electron 42), Windows, 2026-10-07.
- **Funciona con**: 1.18.34 y 1.18.35 (mismo literal). El script busca el patrón dinámicamente, así que vale para futuras versiones **mientras upstream mantenga la constante**.

---

## Uso rápido

Script: [`patch-legacy.ps1`](./patch-legacy.ps1)

```powershell
# 1) Parchear (idempotente; funciona con la app abierta o cerrada)
& ".\patch-legacy.ps1"

# 2) Ver estado (no toca nada)
& ".\patch-legacy.ps1" -Mode status

# 3) Volver al estado 100% oficial (cerrar la app antes)
& ".\patch-legacy.ps1" -Mode restore
```

Tras el parche: **reiniciar OpenCode**. Si tu preferencia `newLayoutDesigns` ya estaba
forzada a `true` (caso normal tras la sunset), en Settings aparece el toggle de
interfaz antigua → actívalo. Con perfil elegible y preferencia undefined, la UI legacy
sale directa sin tocar nada.

---

## Qué hace exactamente

### 1. Parche del sunset en `app.asar`

En `packages/app/src/context/settings.tsx` (compilado dentro del asar):

```js
const oldInterfaceSunset = new Date(2026, 8, 14);   // oficial
const oldInterfaceSunset = new Date(2099, 8, 14);   // parcheado
```

- Búsqueda **dinámica** del literal; exige **exactamente 1 ocurrencia** (si upstream lo cambia, el script aborta sin tocar nada).
- Reemplazo **misma longitud** (2026 → 2099, 4→4 chars): el header del asar solo guarda tamaños de ficheros, no hashes → el asar sigue siendo válido tras escribirlo.
- Verificación post-escritura releyendo el fichero (2026×0, 2099×1).

Por qué funciona: la UI se decide con
`resolveNewLayoutDesigns(retired, preference, fallback) = retired ? true : (preference ?? fallback)`.
Con `retired=false` (fecha en el futuro) manda la preferencia del usuario y, si está
undefined, el fallback `legacyNewLayoutDesignsDefault = false` para perfiles elegibles
→ interfaz legacy por defecto.

### 2. Neutralización del updater

El updater de electron enlaza `void updater.start()` + `check()` cada 10 minutos en
`packages/desktop/src/main/index.ts` (`autoDownload=false`, pero descarga automática si
hay versión mayor). Si se quedara vivo, descargaría una versión nueva y, al aceptar
"restart to update", **restauraría el asar oficial y borraría el parche en silencio**.

Solución: reescribir `resources\app-update.yml` (fuera del asar, no protegido por
Authenticode) apuntando a un repo inexistente → cada chequeo acaba en `HttpError: 404`
→ estado `error` silencioso (los diálogos de error solo se abren desde menú/IPC).
Evidencia tras el reinicio:

```
updater state changed { from: 'checking', to: 'error' }
Error: HttpError: 404
```

Resultado: **OpenCode congelado en 1.18.35** hasta que tú decidas actualizar.

### 3. Backup + rollback

El primer run crea:

```
%LOCALAPPDATA%\Temp\opencode\legacy-backup-<timestamp>\
    app.asar.bak
    app-update.yml.bak
```

`-Mode restore` revierte ambos ficheros (nunca sobrescribe un backup con un asar ya
parcheado: el primer backup se conserva como original de verdad).

---

## Verificación realizada (2026-10-07)

| Check | Resultado |
|---|---|
| Versión | `app starting { version: '1.18.35' }` tras relanzar ✅ |
| Literal en asar (1.18.35) | `new Date(2026, 8, 14)` ×1 (confirmado antes de parchear) ✅ |
| Tras parchear | 2026×0, 2099×1 ✅ |
| Parche en caliente | escritura del asar con la app abierta → permitida por Windows ✅ |
| Updater | 404 silencioso, sin descargas ni diálogos ✅ |
| `opencode.settings` | `oldLayoutEligible: true` (toggle disponible) ✅ |
| Store renderer (`default.dat`) | `showCustomAgents: true`, `layoutTransitionEligible: true`; `newLayoutDesigns` false tras el toggle ✅ |
| UI legacy | activa y persistente ✅ |

Análisis de seguridad de la aproximación:

- **Fuses de Electron**: `embedded_asar_integrity_validation` es `0` por defecto en Electron 42 y el `electron-builder.config.ts` no configura fuses → no hay validación de integridad del asar.
- **Authenticode**: firma solo `OpenCode.exe` (intacto) → no afecta a SmartScreen ni a la ejecución.
- **Code cache**: V8 valida el contenido de origen → recompila solo; no hace falta limpiar `Code Cache`.

---

## Actualizar a futuro (flujo)

```powershell
# 1. Cerrar OpenCode y volver a oficial
& ".\patch-legacy.ps1" -Mode restore

# 2. Abrir OpenCode → Settings → Check for updates → reiniciar

# 3. Parchear de nuevo
& ".\patch-legacy.ps1"
# Si el literal ya no existe (cambio upstream) el script lo detecta y no toca nada.

# 4. Reiniciar → Settings → toggle interfaz legacy si hace falta
```

---

## Limitaciones y riesgos conocidos

1. **Updates congeladas**: mientras el updater esté neutralizado no llegan bugfixes
   oficiales. Se actualiza manualmente con el flujo de arriba.
2. **Literal de upstream**: si `new Date(2026, 8, 14)` desaparece o cambia de formato,
   el script falla con seguridad (fail-closed) y hay que revisarlo.
3. **Futuro fuse de integridad**: si una versión activara
   `embedded_asar_integrity_validation`, la app no arrancaría con el asar parcheado →
   ejecutar `-Mode restore`.
4. **Un patch de 1 línea, no un fork**: no reemplaza el código de la UI; solo evita que
   OpenCode *fuerce* la nueva. La UI legacy es el código legacy que upstream aún incluye.

---

## Contexto e historia

- La sunset del 14-sep-2026 (`oldInterfaceSunset`) forzaba `newLayoutDesigns=true` en
  todos los perfiles → el workaround previo (`default.dat → false`) dejó de funcionar.
- Issue: [anomalyco/opencode#38230](https://github.com/anomalyco/opencode/issues/38230)
  (voto 👍 y comentario públicos de la comunidad).
- Fork comunitario `kuznecov-anatoliy/opencode-old-interface`: analizado y descartado
  (base real upstream v1.18.30, 3 parches menores, binarios sin firma).
- Build desde source (plan C): descartado por coste (bun + toolchain + mantenimiento).
- Plan D (este repo): parche encima de la app instalada → 5 minutos, reversibles.

---

## Archivos

| Archivo | Descripción |
|---|---|
| `patch-legacy.ps1` | Script con modos `patch` (default) / `restore` / `status` |
| `README.md` | Este documento |

## Licencia

MIT — usa/comparte bajo tu criterio.
