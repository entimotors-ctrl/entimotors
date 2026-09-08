-- ENTIMOTORS OS — Fase 3A: citas+WhatsApp, taller/negocio, mecánicos, rendimiento.
-- Migración incremental sobre entimotors-completo.sql (+ entimotors-usuarios.sql).
-- Idempotente: se puede ejecutar más de una vez sin romper nada.
--
-- NO SE HA EJECUTADO CONTRA SUPABASE REAL. Este archivo documenta el cambio
-- de esquema que corresponde al código de esta fase; ejecutarlo requiere
-- autorización aparte (ver informe de Fase 3A, sección P).

alter table public.ordenes
  add column if not exists origen_trabajo text not null default 'taller';

do $$ begin
  alter table public.ordenes
    add constraint ordenes_origen_trabajo_check check (origen_trabajo in ('taller','negocio'));
exception when duplicate_object then null;
end $$;

alter table public.citas
  add column if not exists aviso_cliente_wa jsonb;
