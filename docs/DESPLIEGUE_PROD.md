# Service Assurance — Procedimiento PROD (solo con GO expreso)

## Precondiciones (lectura)
1. Acceso PROD operativo (Teleport `noc-sysbrazo` o Tailscale). **No tocar nada aún.**
2. Confirmar ruta de plugins y contenedor: `docker inspect redmine_app --format '{{.Mounts}}'`, `ls <plugins>/fibrazo_service_assurance` (debe NO existir).
3. Respaldo: snapshot RDS + `cp -a <plugins> /root/sa_backup_<fecha>` (solo lectura del dato, copia de seguridad permitida en ventana).

## Despliegue (exclusivo del plugin)
1. En estación: `git archive --remote` o tar desde tag `v1.0.0-rc2` (commit `d04242f`). Verificar sha256.
2. Copiar tar a PROD `/tmp/` (un archivo por envío en `tsh scp`).
3. Extraer a `<plugins>/fibrazo_service_assurance` (solo este directorio).
4. Migraciones propias únicamente: `bundle exec rake redmine:plugins:migrate NAME=fibrazo_service_assurance RAILS_ENV=production` (crea 5 tablas propias: cases, evaluations, circuits, intervals, audits + índices UNIQUE/FK).
5. Reiniciar contenedor Redmine PROD. Verificar `healthy`, `restarts` sin incremento.
6. Configurar (Administración → Settings → plugin): `activation_cf_id=295`, `activation_yes_value=SÍ`, trackers/proyectos/estados por NOMBRE en UI, `carrier_list` manual, `allowed_user_ids=[evaluadores]`, `api_read_enabled=0`.
7. **No importar registros QA. No generar evaluaciones masivas.** La bandeja se puebla sola al cerrar tickets con CF295=SÍ.
8. **No modificar otros plugins, tickets, usuarios ni workflows.**

## Validación post-despliegue
Login admin → `/service_assurance` 200 (bandeja vacía o solo SÍ reales) → `/settings/plugin/fibrazo_service_assurance` 200 con listas → export 200 (solo cabecera si no hay casos) → abrir un caso real SÍ y guardar avance → revisar `audits` creados.

## Rollback
`rm -rf <plugins>/fibrazo_service_assurance` + reiniciar (tablas propias quedan inertes, sin afectar Redmine). Si la migración falló a medias: restaurar snapshot RDS. Nunca borrar tickets ni CF295.
