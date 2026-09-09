-- ENTIMOTORS OS — Fase 4C: identidad estable del mecánico.
-- Migración incremental sobre entimotors-completo.sql + entimotors-usuarios.sql
-- + entimotors-fase3a.sql. Idempotente: se puede ejecutar más de una vez.
--
-- NO SE HA EJECUTADO CONTRA SUPABASE REAL. Ejecutarlo requiere autorización
-- aparte (ver informe de Fase 4C-1, sección D).
--
-- ─────────────────────────────────────────────────────────────────────────────
-- QUÉ RESUELVE
--
-- Hoy una cita o una orden dicen quién la atiende con un texto:
--
--     citas.mecanico   = 'Wilkin'
--     ordenes.mecanico = 'Wilkin'
--
-- Eso tiene tres problemas: dos empleados que se llamen igual son la misma
-- persona para el sistema; renombrar a alguien huérfana todo su historial; y
-- no hay nada a lo que una política RLS pueda agarrarse para decir «esta orden
-- es tuya». Sin un identificador estable no se puede escribir la regla
-- «cada mecánico ve solo lo suyo», que es el objetivo de la Fase 4.
--
-- QUÉ **NO** HACE ESTE ARCHIVO
--
--   · No borra ni toca `citas.mecanico` ni `ordenes.mecanico`. Ese texto se
--     queda: es el historial, el nombre que se enseña en pantalla y lo único
--     que tienen los registros creados sin conexión o antes de esta fase.
--   · No rellena `mecanico_id` a partir del nombre. Un UPDATE ... WHERE
--     mecanico = 'X' podría atribuirle el trabajo a la persona equivocada en
--     cuanto haya dos nombres iguales, y eso ensucia el rendimiento y las
--     finanzas sin que nadie se dé cuenta. Los registros viejos se quedan con
--     mecanico_id = null, y eso es una respuesta válida: «no se sabe con
--     certeza quién fue».
--   · No crea políticas RLS, ni la tabla de notificaciones, ni disparadores de
--     asignación. Eso es 4D en adelante.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────── 1. LA COLUMNA
-- Nullable a propósito y para siempre: un trabajador puede no tener cuenta
-- (los de la lista TEAM local no la tienen), y una cita puede quedar sin
-- asignar. Que sea null no es un defecto de datos, es un estado real.
alter table public.citas
  add column if not exists mecanico_id uuid;

alter table public.ordenes
  add column if not exists mecanico_id uuid;

-- ─────────────────────────────────────────────── 2. LA REFERENCIA
-- ON DELETE SET NULL, y conviene explicar por qué no las otras dos:
--
--   CASCADE  borraría la cita o la orden al dar de baja al empleado. Es
--            destrucción de historial comercial por un cambio de personal:
--            inaceptable.
--   RESTRICT impediría borrar el perfil de cualquiera que haya trabajado
--            alguna vez, que es justamente todo el mundo.
--   SET NULL deja el registro intacto y solo suelta el vínculo. El nombre
--            sobrevive en la columna de texto, así que la orden sigue
--            diciendo quién la hizo aunque su cuenta ya no exista.
--
-- En la práctica el borrado de perfiles casi no ocurre — la baja se hace con
-- `activo = false`, que no dispara nada de esto —, pero la regla tiene que
-- ser segura también en el caso raro.
do $$ begin
  alter table public.citas
    add constraint citas_mecanico_id_fkey
    foreign key (mecanico_id) references public.perfiles(id) on delete set null;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.ordenes
    add constraint ordenes_mecanico_id_fkey
    foreign key (mecanico_id) references public.perfiles(id) on delete set null;
exception when duplicate_object then null;
end $$;

-- ─────────────────────────────────────────────── 3. ÍNDICES
-- La consulta que va a existir en cuanto haya varios mecánicos es «dame lo
-- mío», y la va a hacer la app en cada arranque y cada política RLS en cada
-- fila. Parciales sobre `not null` porque hoy la inmensa mayoría de las filas
-- tendrán null y no aportan nada al índice.
create index if not exists citas_mecanico_id_idx
  on public.citas (mecanico_id) where mecanico_id is not null;

create index if not exists ordenes_mecanico_id_idx
  on public.ordenes (mecanico_id) where mecanico_id is not null;

-- ─────────────────────────────────────────────── 4. DOCUMENTACIÓN EN LA BASE
-- Para que dentro de un año se entienda por qué hay dos columnas para lo mismo.
comment on column public.citas.mecanico_id is
  'Perfil asignado. Null = trabajador sin cuenta, registro anterior a 4C, o sin asignar. El nombre visible está en citas.mecanico.';
comment on column public.ordenes.mecanico_id is
  'Perfil asignado. Null = trabajador sin cuenta, registro anterior a 4C, o sin asignar. El nombre visible está en ordenes.mecanico.';
comment on column public.citas.mecanico is
  'Nombre visible del mecánico. Se conserva siempre, también cuando mecanico_id está puesto: es el historial y el fallback.';
comment on column public.ordenes.mecanico is
  'Nombre visible del mecánico. Se conserva siempre, también cuando mecanico_id está puesto: es el historial y el fallback.';
