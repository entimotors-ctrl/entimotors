-- ENTIMOTORS OS — Fase 4D: DESHACER.  ***NO EJECUTADO***
--
-- Devuelve el RLS al estado exacto anterior a entimotors-fase4d-rls.sql, es
-- decir, al que dejaron entimotors-completo.sql y entimotors-usuarios.sql.
--
-- QUÉ **NO** DESHACE, y por qué
--
--   La Fase 4C está aprobada y aplicada. Este archivo NO toca nada de ella:
--     · citas.mecanico_id / ordenes.mecanico_id      (las columnas se quedan)
--     · citas_mecanico_id_fkey / ordenes_..._fkey    (las FK se quedan)
--     · citas_mecanico_id_idx / ordenes_..._idx      (los índices se quedan)
--     · los comment on column de 4C                  (se quedan)
--   Sin políticas de 4D esas columnas simplemente no se usan para filtrar. No
--   estorban y volver a añadirlas costaría otra migración.
--
-- AVISO: al terminar, el taller vuelve a estar abierto de par en par para el
-- rol mecanico — clientes, precios, ventas y créditos incluidos. Eso es
-- exactamente el estado de hoy, pero conviene decirlo en voz alta.
--
-- Es una sola transacción, igual que la ida.

begin;

-- ═════════════════════════════════════════════ 1. QUITAR LOS TRIGGERS DE 4D
-- Primero los triggers, luego su función: al revés PostgreSQL se niega.
drop trigger if exists ordenes_mecanico_avance on public.ordenes;
drop trigger if exists citas_mecanico_avance   on public.citas;
drop function if exists public.mecanico_solo_avance_tecnico();


-- ═════════════════════════════════════════════ 2. QUITAR LAS POLÍTICAS DE 4D
-- También antes que los helpers, por la misma razón: una política que
-- referencia una función crea dependencia y bloquea su borrado.
drop policy if exists citas_lee   on public.citas;
drop policy if exists citas_crea  on public.citas;
drop policy if exists citas_edita on public.citas;

drop policy if exists ordenes_lee   on public.ordenes;
drop policy if exists ordenes_crea  on public.ordenes;
drop policy if exists ordenes_edita on public.ordenes;

drop policy if exists clientes_lee   on public.clientes;
drop policy if exists clientes_crea  on public.clientes;
drop policy if exists clientes_edita on public.clientes;

drop policy if exists motos_lee   on public.motos;
drop policy if exists motos_crea  on public.motos;
drop policy if exists motos_edita on public.motos;

drop policy if exists orden_items_lee   on public.orden_items;
drop policy if exists orden_items_crea  on public.orden_items;
drop policy if exists orden_items_edita on public.orden_items;

drop policy if exists cotizaciones_lee   on public.cotizaciones;
drop policy if exists cotizaciones_crea  on public.cotizaciones;
drop policy if exists cotizaciones_edita on public.cotizaciones;

drop policy if exists cotizacion_items_lee   on public.cotizacion_items;
drop policy if exists cotizacion_items_crea  on public.cotizacion_items;
drop policy if exists cotizacion_items_edita on public.cotizacion_items;

-- Estas cinco y las dos de inventario conservan su NOMBRE original: 4D las
-- recreó con la misma etiqueta y otra expresión. Se borran igual y se vuelven
-- a crear abajo con es_equipo().
-- storage va aquí y no más abajo: sus políticas referencian ve_todo_el_taller(),
-- y PostgreSQL no deja borrar una función de la que cuelga una política.
drop policy if exists taller_lee_media  on storage.objects;
drop policy if exists taller_sube_media on storage.objects;

drop policy if exists ventas_lee        on public.ventas;
drop policy if exists venta_items_lee   on public.venta_items;
drop policy if exists creditos_lee      on public.creditos;
drop policy if exists credito_items_lee on public.credito_items;
drop policy if exists abonos_lee        on public.abonos;
drop policy if exists inventario_lee    on public.inventario;
drop policy if exists categorias_lee    on public.categorias_inv;


-- ═════════════════════════════════════════════ 3. QUITAR LOS HELPERS DE 4D
drop function if exists public.mi_cliente(uuid);
drop function if exists public.mi_moto(uuid);
drop function if exists public.es_mecanico_activo();
drop function if exists public.ve_todo_el_taller();
-- rol_actual, es_admin, es_equipo, puede_cobrar y es_desarrollador son
-- anteriores a 4D y no se tocan.


-- ═════════════════════════════════════════════ 4. RESTAURAR LAS POLÍTICAS
-- Reproducción literal del bucle de entimotors-completo.sql sobre las mismas 7
-- tablas y en el mismo orden. Se escribe igual que el original —con format() y
-- las cuatro políticas— para que un diff contra aquel archivo sea limpio.
-- Incluye _admin_borra aunque 4D no la tocara: así el bloque deja las 7 tablas
-- en un estado conocido completo, en vez de en uno que depende de qué se
-- borró antes.
do $$
declare t text;
begin
  foreach t in array array['clientes','motos','ordenes','orden_items',
                           'cotizaciones','cotizacion_items','citas'] loop
    execute format('drop policy if exists %1$s_equipo_lee on public.%1$s', t);
    execute format('drop policy if exists %1$s_equipo_crea on public.%1$s', t);
    execute format('drop policy if exists %1$s_equipo_edita on public.%1$s', t);
    execute format('drop policy if exists %1$s_admin_borra on public.%1$s', t);
    execute format('create policy %1$s_equipo_lee on public.%1$s for select using (public.es_equipo())', t);
    execute format('create policy %1$s_equipo_crea on public.%1$s for insert with check (public.es_equipo())', t);
    execute format('create policy %1$s_equipo_edita on public.%1$s for update using (public.es_equipo()) with check (public.es_equipo())', t);
    execute format('create policy %1$s_admin_borra on public.%1$s for delete using (public.es_admin())', t);
  end loop;
end $$;

-- Las siete sueltas, copiadas de entimotors-completo.sql tal cual estaban.
create policy ventas_lee        on public.ventas        for select using (public.es_equipo());
create policy venta_items_lee   on public.venta_items   for select using (public.es_equipo());
create policy creditos_lee      on public.creditos      for select using (public.es_equipo());
create policy credito_items_lee on public.credito_items for select using (public.es_equipo());
create policy abonos_lee        on public.abonos        for select using (public.es_equipo());
create policy inventario_lee    on public.inventario    for select using (public.es_equipo());
create policy categorias_lee    on public.categorias_inv for select using (public.es_equipo());

-- ═════════════════════════════════════════════ 5. RESTAURAR estadisticas_tecnicas
-- 4D la cerró a admin y desarrollador. Aquí vuelve al control de rol original
-- de entimotors-usuarios.sql, que admite los cuatro roles. Cuerpo idéntico.
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

-- ═════════════════════════════════════════════ 6. RESTAURAR STORAGE
-- Vuelven a es_equipo(), tal como estaban en entimotors-completo.sql.
create policy taller_lee_media on storage.objects for select
  using (bucket_id = 'entimotors-taller' and public.es_equipo());

create policy taller_sube_media on storage.objects for insert
  with check (bucket_id = 'entimotors-taller' and public.es_equipo());

-- ═════════════════════════════════════════════ 7. LOS ÍNDICES DE 4D SE VAN
-- idx_citas_cliente e idx_ordenes_moto los introdujo 4D y solo existen para
-- las políticas de 4D. Deshacer significa deshacer: el estado posterior debe
-- ser idéntico al anterior, sin sobras que nadie sepa de dónde salieron.
--
-- Los índices de 4C (citas_mecanico_id_idx, ordenes_mecanico_id_idx) NO se
-- tocan: 4C está aprobada y es independiente de esto.
drop index if exists public.idx_citas_cliente;
drop index if exists public.idx_ordenes_moto;

commit;





-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  COMPROBACIÓN — SOLO LECTURA — ejecutar después del rollback.             ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- select count(*) from pg_policies
--  where schemaname='public' and (qual like '%es_equipo%' or with_check like '%es_equipo%');
-- -- esperado tras el rollback: 30  (el número previo a 4D)
--
-- select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--  where n.nspname='public'
--    and proname in ('ve_todo_el_taller','es_mecanico_activo','mi_cliente','mi_moto',
--                    'mecanico_solo_avance_tecnico');
-- -- esperado: 0
--
-- select count(*) from pg_trigger
--  where not tgisinternal and tgrelid::regclass::text in ('ordenes','citas');
-- -- esperado: 0
--
-- select column_name from information_schema.columns
--  where table_schema='public' and table_name in ('citas','ordenes')
--    and column_name='mecanico_id';
-- -- esperado: 2 filas — 4C sigue intacta
