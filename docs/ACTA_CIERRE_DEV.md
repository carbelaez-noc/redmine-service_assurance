# Service Assurance — Acta de cierre DEV

- **Commit:** `d04242f` · **Rama:** `stable` · **Tag:** `v1.0.0-rc2` (rc1 `v1.0.0-rc1` en `1393e12`, superado)
- **Versión plugin:** 0.7.0 · **Repo:** `carbelaez-noc/redmine-service_assurance`
- **DEV verificado:** archivos en servidor byte-idénticos a `stable` (sha256 controller/vista/xlsx), `healthy restarts=0`
- **Alcance respetado:** solo DEV. PROD no intervenido. Sin cambios de usuarios/roles. N0 Lite, FCS, ANS I&M, MOPS, Krill, OneView intactos.

## Qué incluye
Bandeja de cerrados con CF activación=SÍ (normalizado SÍ/SI/YES/1), detalle A/B/C con snapshot solo-lectura, precarga configurable sin IDs en código, evaluación rápida, conciliación con diferencia automática, XLSX 26 columnas al carrier, idempotencia por UNIQUE, auditoría append-only, lock optimista, nómina de acceso + permisos por proyecto, API OneView OFF.

## Evidencia funcional (todas PASS)
1. E2E autenticado real (carlos0424, HTTP): login 302 → bandeja 200 (12 filas) → caso 200 → save→conciliar→stale-guard→cerrar `conciliado` (downtime 120, difference 30).
2. Batería controlador: aceptación, rechazo, reapertura (302→en_revision), conciliación con créditos, descarte con motivo y limpieza de ANS.
3. `to_conciliate` sin B completa → 422 con lista de faltantes, flotante sin recarga. Cierre reconocida exige fecha+tiempo+motivo (créditos opcionales).
4. DoubleRender corregido: sin permiso → **403** (usuario `sistema_odoo`), anónimo → 302 login, con permiso → 200.
5. Export: 200, ZIP válido, **26 columnas** verificadas, sin "Caso SA"/"Circuito(s)", "# caso carrier", evaluador nombre+apellido; filtro carrier (Liberty→5) y rango vacío (→0) correctos.
6. Render: topbar tabs+flujo, tarjetas 2 líneas, rojo pastel en vacíos, cero `alert/confirm` nativos, auditoría bajo demanda.

## Limitación expresa
Playwright automatizado con navegador **no ejecutado**: el SSO de Google bloquea login bot y las credenciales no se delegan a un runner desatendido. La cobertura E2E es **HTTP autenticado real** (misma pila: rutas, CSRF, permisos, persistencia), no clics en DOM. Aceptación visual = manual del responsable con los 10 casos QA.

## Sintéticos (NO migrar a PROD, NO generar masivo)
Issues `713054–713063` (SA QA 1–10, SA 32–41, pendientes) + `713066` (SA E2E curl, SA44 conciliado). Evaluaciones de prueba sobre tickets DEV: SA 5,6,15,16,19.

## Riesgos residuales
CF295 no existe aún en el código (solo setting → configurar 295 en PROD). `carrier_list` manual en PROD (sin inventario OLT). Reaperturas/reclasificaciones preservan evaluaciones por diseño. Concurrencia: segundo guardado recibe aviso de recarga.

## Dictamen
**GO condicionado a aceptación manual** en DEV (10 QA + recorrido visual) y GO expreso de despliegue. Sin nuevas funcionalidades tras este acta.
