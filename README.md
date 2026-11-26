# Service Assurance (`fibrazo_service_assurance`) — v0.1.0 (DEV)

Bandeja ligera de evaluación y conciliación de ANS de proveedores externos.
Solo lectura sobre tickets; toda la escritura va a tablas propias.

## Rutas

- `/service_assurance` — bandeja (cerrados con activación Sí, paginado 100).
- `/service_assurance/cases/:id` — detalle (A solo lectura, B/C/D editables, guardar avance).
- `/service_assurance/admin` — resumen de configuración efectiva.
- Ajustes: Administración → Plugins → Service Assurance → Configurar.

## Sin IDs en código

`activation_cf_id`, valor afirmativo, trackers, proyectos y estados son ajustes.
Autodetección por nombre `¿Requiere evaluación de ANS?` si el ajuste está vacío.

## Tablas propias

- `service_assurance_cases` (UNIQUE issue_id, índice status).
- `service_assurance_evaluations` (UNIQUE case_id).
- `service_assurance_audits` (append-only: usuario, acción, campo, antes/después).

FK a issues con RESTRICT (nunca CASCADE).

## Idempotencia

`ServiceAssuranceCase.for_issue!` — `find_or_create` por `issue_id` vía
`Eligibility.check!`. Reaperturas y cambios del CF nunca duplican ni borran.

## Permisos

view / evaluate / manage_conciliations / reopen / admin. Rol propuesto:
Evaluador Service Assurance (crear en UI, no en esta misión).

## Rendimiento

Sin barridos: índice por `custom_field_id` + estado cerrado + `closed_on DESC`,
límite 100. Sin Krill, sin colectores. API de lectura deshabilitada por defecto
(`api_read_enabled`), futura OneView.

## v0.2.0 (P2)

- Precarga: snapshot de originales (CF ciudad/inicio/fin/clientes/carrier/caso-ISP/categoría/subcategoría/motivo/ID externo) + prefill editable; mapa por ajuste o autodetección por nombre.
- Multialcance: `service_assurance_circuits` (N circuitos) + `service_assurance_intervals` (kinds tecnica/degradacion/exclusion/contractual/reconocida); degradación nunca suma; sugerido = técnica − exclusiones.
- Concurrencia: `lock_version` en casos y evaluaciones (StaleObjectError → aviso).
- Bandeja: filtros periodo/estado/carrier/evaluador + columnas antigüedad/carrier/evaluador; responsable autoasignado al primer guardado.
- Detalle: journals con notas y adjuntos del ticket en solo lectura.
