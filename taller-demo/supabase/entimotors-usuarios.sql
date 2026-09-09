-- ═══════════════════════════════════════════════════════════════════════════
--  ENTIMOTORS OS · usuarios, roles y privacidad
--  Se ejecuta DESPUÉS de entimotors-completo.sql. Es idempotente: se puede
--  volver a correr sin romper nada.
--
--  Qué hace:
--    1. añade el rol 'desarrollador' (sin quitar 'cajero')
--    2. separa "equipo del taller" de "desarrollador"
--    3. deja el sistema con UN SOLO administrador, garantizado por la base
--    4. cierra al desarrollador el acceso a los datos de los clientes
--    5. le da a cambio una superficie técnica: solo conteos y estado
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────── 1. EL ROL DESARROLLADOR
-- 'cajero' se mantiene: ya está probado y forma parte de la arquitectura.
alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check
  check (rol in ('admin','mecanico','cajero','desarrollador'));

-- ─────────────────────────────────────────────── 2. QUIÉN ES QUIÉN
-- SECURITY DEFINER como las que ya existen: si leyeran perfiles con los
-- permisos de quien llama, la política de perfiles se llamaría a sí misma.

-- El personal del taller. El desarrollador NO está aquí, y esa es la clave
-- de toda la privacidad: donde antes decía "cualquiera con sesión", ahora
-- dice "el equipo".
create or replace function public.es_equipo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('admin','cajero','mecanico'), false)
$$;

create or replace function public.es_desarrollador() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() = 'desarrollador', false)
$$;

-- ─────────────────────────────────────────────── 3. UN SOLO ADMINISTRADOR
-- Un disparador, no una política: los disparadores se cumplen SIEMPRE, también
-- para la clave de servidor. Aunque alguien tuviera la service_role, no puede
-- fabricarse un segundo administrador.
create or replace function public.proteger_admin_unico() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- (a) nunca puede haber dos administradores
  if new.rol = 'admin'
     and exists (select 1 from public.perfiles where rol = 'admin' and id <> new.id) then
    raise exception 'Ya existe un administrador. ENTIMOTORS OS admite uno solo.';
  end if;

  -- (b) desde la aplicación no se puede dejar al taller sin administrador.
  --     Desde el panel de Supabase (sin sesión de usuario) sí, para poder
  --     traspasar el cargo: primero se degrada al actual, luego se asciende
  --     al nuevo.
  if tg_op = 'UPDATE' and old.rol = 'admin' and new.rol <> 'admin'
     and auth.uid() is not null
     and not exists (select 1 from public.perfiles where rol = 'admin' and id <> old.id) then
    raise exception 'No se puede quitar al único administrador desde la aplicación.';
  end if;

  return new;
end $$;

drop trigger if exists perfiles_admin_unico on public.perfiles;
create trigger perfiles_admin_unico
  before insert or update on public.perfiles
  for each row execute function public.proteger_admin_unico();

-- el mismo cuidado al borrar
create or replace function public.proteger_borrado_admin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.rol = 'admin' and auth.uid() is not null
     and not exists (select 1 from public.perfiles where rol = 'admin' and id <> old.id) then
    raise exception 'No se puede borrar al único administrador desde la aplicación.';
  end if;
  return old;
end $$;

drop trigger if exists perfiles_borrado_admin on public.perfiles;
create trigger perfiles_borrado_admin
  before delete on public.perfiles
  for each row execute function public.proteger_borrado_admin();

-- ─────────────────────────────────────────────── 4. PRIVACIDAD DEL CLIENTE
-- Se sustituye "auth.uid() is not null" por "es_equipo()" en TODAS las tablas
-- con datos de clientes. Para admin, cajero y mecánico no cambia absolutamente
-- nada: los tres son equipo. Para el desarrollador, se cierra la puerta.

do $$
declare t text;
begin
  foreach t in array array['clientes','motos','ordenes','orden_items',
                           'cotizaciones','cotizacion_items','citas'] loop
    execute format('drop policy if exists %1$s_equipo_lee   on public.%1$s', t);
    execute format('drop policy if exists %1$s_equipo_crea  on public.%1$s', t);
    execute format('drop policy if exists %1$s_equipo_edita on public.%1$s', t);
    execute format('create policy %1$s_equipo_lee   on public.%1$s for select using (public.es_equipo())', t);
    execute format('create policy %1$s_equipo_crea  on public.%1$s for insert with check (public.es_equipo())', t);
    execute format('create policy %1$s_equipo_edita on public.%1$s for update using (public.es_equipo()) with check (public.es_equipo())', t);
  end loop;
end $$;

drop policy if exists ventas_lee on public.ventas;
create policy ventas_lee on public.ventas for select using (public.es_equipo());

drop policy if exists venta_items_lee on public.venta_items;
create policy venta_items_lee on public.venta_items for select using (public.es_equipo());

drop policy if exists creditos_lee on public.creditos;
create policy creditos_lee on public.creditos for select using (public.es_equipo());

drop policy if exists credito_items_lee on public.credito_items;
create policy credito_items_lee on public.credito_items for select using (public.es_equipo());

drop policy if exists abonos_lee on public.abonos;
create policy abonos_lee on public.abonos for select using (public.es_equipo());

drop policy if exists inventario_lee on public.inventario;
create policy inventario_lee on public.inventario for select using (public.es_equipo());

drop policy if exists categorias_lee on public.categorias_inv;
create policy categorias_lee on public.categorias_inv for select using (public.es_equipo());

drop policy if exists cms_lee on public.web_cms;
create policy cms_lee on public.web_cms for select using (public.es_equipo());

-- la bitácora la escribe quien trabaja, no quien supervisa
drop policy if exists auditoria_crea on public.auditoria;
create policy auditoria_crea on public.auditoria for insert with check (public.es_equipo());

-- Las fotos de las motos son datos del cliente: el desarrollador tampoco entra.
drop policy if exists taller_lee_media  on storage.objects;
drop policy if exists taller_sube_media on storage.objects;
create policy taller_lee_media on storage.objects for select
  using (bucket_id = 'entimotors-taller' and public.es_equipo());
create policy taller_sube_media on storage.objects for insert
  with check (bucket_id = 'entimotors-taller' and public.es_equipo());

-- ─────────────────────────────────────────────── 5. SUPERFICIE TÉCNICA
-- Lo único que el desarrollador puede consultar de la base: CONTEOS.
-- Ni un nombre, ni un teléfono, ni un importe. Si mañana alguien añade aquí
-- una columna con datos, se rompe la promesa de privacidad: solo count(*).
create or replace function public.estadisticas_tecnicas() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_rol text;
begin
  v_rol := public.rol_actual();
  -- rol conocido y activo. rol_actual() ya filtra por activo = true, así que a
  -- un usuario dado de baja le devuelve null y no pasa de aquí.
  if v_rol is null or v_rol not in ('admin','cajero','mecanico','desarrollador') then
    raise exception 'Se necesita una sesión iniciada con un rol válido';
  end if;
  -- SOLO count(*). Ni un nombre, ni un teléfono, ni un importe, ni un UUID.
  return jsonb_build_object(
    'clientes',          (select count(*) from public.clientes),
    'motos',             (select count(*) from public.motos),
    'ordenes',           (select count(*) from public.ordenes),
    'ordenes_abiertas',  (select count(*) from public.ordenes where not finalizada),
    'cotizaciones',      (select count(*) from public.cotizaciones),
    'citas',             (select count(*) from public.citas),
    'inventario',        (select count(*) from public.inventario),
    'ventas',            (select count(*) from public.ventas),
    'ventas_hoy',        (select count(*) from public.ventas where creado_en::date = current_date),
    'creditos',          (select count(*) from public.creditos),
    'creditos_abiertos', (select count(*) from public.creditos where estado <> 'pagado'),
    'abonos',            (select count(*) from public.abonos),
    'movimientos_caja',  (select count(*) from public.caja_movimientos),
    'auditoria',         (select count(*) from public.auditoria)
  );
end $$;

-- Estado técnico: versión del motor, hora del servidor, y si RLS sigue puesto
-- en cada tabla. Nada de esto identifica a nadie.
create or replace function public.estado_tecnico() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_rol text;
begin
  v_rol := public.rol_actual();
  -- comprobación explícita de rol: esta superficie es para quien mantiene el
  -- sistema. Un mecánico o un cajero no tienen nada que hacer aquí.
  if v_rol is null then
    raise exception 'Se necesita una sesión iniciada';
  end if;
  if not (public.es_admin() or public.es_desarrollador()) then
    raise exception 'Solo el administrador y el desarrollador pueden consultar el estado técnico';
  end if;
  return jsonb_build_object(
    'rol',            v_rol,
    'hora_servidor',  now(),
    'motor',          current_setting('server_version'),
    'tablas', (
      select jsonb_agg(jsonb_build_object(
               'tabla', c.relname, 'rls', c.relrowsecurity,
               'politicas', (select count(*) from pg_policy p where p.polrelid = c.oid))
             order by c.relname)
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r'
         and c.relname in ('perfiles','clientes','motos','inventario','categorias_inv',
              'ordenes','orden_items','cotizaciones','cotizacion_items','citas','ventas',
              'venta_items','creditos','credito_items','abonos','caja_movimientos',
              'web_cms','auditoria')),
    'usuarios_por_rol', (
      select coalesce(jsonb_object_agg(rol, n), '{}'::jsonb)
        from (select rol, count(*) n from public.perfiles where activo group by rol) x)
  );
end $$;

-- ─────────────────────────────────────────────── 6. PERMISOS
grant execute on function public.es_equipo()             to authenticated;
grant execute on function public.es_desarrollador()      to authenticated;
grant execute on function public.estadisticas_tecnicas() to authenticated;
grant execute on function public.estado_tecnico()        to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
--  CÓMO ASIGNAR LOS ROLES (ejecutar a mano, cambiando los correos)
-- ═══════════════════════════════════════════════════════════════════════════
-- update public.perfiles set rol='admin', nombre='Wilkin'
--  where id=(select id from auth.users where email='wilkin@entimotors.hn');
--
-- update public.perfiles set rol='desarrollador', nombre='Desarrollador'
--  where id=(select id from auth.users where email='dev@entimotors.hn');
--
-- los mecánicos no necesitan nada: 'mecanico' es el valor por defecto.
--
-- dar de baja a alguien SIN borrarlo (su historial sigue teniendo sentido):
-- update public.perfiles set activo=false where id='...';

-- ═══════════════════════════════════════════════════════════════════════════
--  7. AUTOCOMPROBACIÓN
--  El script se revisa a sí mismo antes de dar por bueno el resultado. Si algo
--  quedó a medias —o si alguien vuelve a ejecutar entimotors-completo.sql
--  DESPUÉS de este y revierte las políticas— esto lo dice en voz alta en vez de
--  dejar la base abierta en silencio.
-- ═══════════════════════════════════════════════════════════════════════════
do $$
declare
  -- tablas con datos de personas: aquí NO puede valer con "tener sesión"
  privadas text[] := array['clientes','motos','ordenes','orden_items','cotizaciones',
                           'cotizacion_items','citas','ventas','venta_items','creditos',
                           'credito_items','abonos','inventario','categorias_inv',
                           'caja_movimientos','web_cms','auditoria'];
  abiertas text;
  faltan   text;
  n_pol    int;
begin
  -- (a) ninguna política de lectura/escritura puede seguir diciendo
  --     "auth.uid() is not null" sobre una tabla privada
  select string_agg(tablename||'.'||policyname, ', ' order by tablename, policyname)
    into abiertas
    from pg_policies
   where schemaname = 'public'
     and tablename = any(privadas)
     and (coalesce(qual,'') ~ 'auth\.uid\(\) IS NOT NULL'
       or coalesce(with_check,'') ~ 'auth\.uid\(\) IS NOT NULL');
  if abiertas is not null then
    raise exception E'PRIVACIDAD ROTA: estas políticas siguen abiertas a cualquiera con sesión, así que el rol desarrollador vería datos de clientes:\n  %\nVuelve a ejecutar este archivo DESPUÉS de entimotors-completo.sql.', abiertas;
  end if;

  -- (b) lo mismo en el bucket privado de fotos
  select string_agg(policyname, ', ' order by policyname) into abiertas
    from pg_policies
   where schemaname = 'storage' and policyname in ('taller_lee_media','taller_sube_media')
     and (coalesce(qual,'') ~ 'auth\.uid\(\) IS NOT NULL'
       or coalesce(with_check,'') ~ 'auth\.uid\(\) IS NOT NULL');
  if abiertas is not null then
    raise exception 'PRIVACIDAD ROTA: el desarrollador podría descargar las fotos de las motos (%)', abiertas;
  end if;

  -- (c) las cuatro funciones tienen que existir
  select string_agg(f, ', ') into faltan from unnest(array[
      'es_equipo','es_desarrollador','estadisticas_tecnicas','estado_tecnico']) f
   where not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                      where n.nspname='public' and p.proname=f);
  if faltan is not null then
    raise exception 'Faltan funciones: %', faltan;
  end if;

  -- (d) los dos disparadores del admin único
  select string_agg(t, ', ') into faltan from unnest(array[
      'perfiles_admin_unico','perfiles_borrado_admin']) t
   where not exists (select 1 from pg_trigger where tgname=t and not tgisinternal);
  if faltan is not null then
    raise exception 'Faltan disparadores: %', faltan;
  end if;

  -- (e) el rol desarrollador tiene que estar admitido
  if not exists (select 1 from pg_constraint
                  where conname='perfiles_rol_check'
                    and pg_get_constraintdef(oid) like '%desarrollador%') then
    raise exception 'El CHECK de perfiles.rol no admite el rol desarrollador';
  end if;

  -- (f) nunca más de un administrador
  if (select count(*) from public.perfiles where rol='admin') > 1 then
    raise exception 'Hay más de un administrador. Corrígelo antes de continuar.';
  end if;

  select count(*) into n_pol from pg_policies
   where schemaname in ('public','storage')
     and (coalesce(qual,'') like '%es_equipo%' or coalesce(with_check,'') like '%es_equipo%');

  raise notice '───────────────────────────────────────────────';
  raise notice 'ENTIMOTORS · usuarios y privacidad: TODO CORRECTO';
  raise notice '  politicas con es_equipo(): %', n_pol;
  raise notice '  administradores: %', (select count(*) from public.perfiles where rol='admin');
  raise notice '  el rol desarrollador NO ve datos de clientes';
  raise notice '───────────────────────────────────────────────';
end $$;
