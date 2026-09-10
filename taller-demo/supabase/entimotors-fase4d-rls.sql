-- ENTIMOTORS OS — Fase 4D: RLS por persona.  ***NO EJECUTADO***
--
-- Requiere entimotors-fase4c-identidad.sql, ya aplicado: citas.mecanico_id y
-- ordenes.mecanico_id existen en Supabase real desde 4C-2A.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- QUÉ CIERRA
--
-- Hoy 30 políticas dicen es_equipo(), que es cierto para admin, cajero Y
-- mecanico por igual. Un mecánico con su sesión lee el taller entero: la
-- cartera de clientes, las placas, los precios, las ventas, los créditos y las
-- cotizaciones. La barrera de showView de 4C-1 es de interfaz; esta es la de
-- datos, y es la única que cuenta.
--
-- DOS BARRERAS QUE NO SE SUSTITUYEN
--
--   RLS      decide QUÉ FILAS ve y toca cada quien.
--   TRIGGER  decide QUÉ COLUMNAS puede cambiar dentro de una fila ya suya.
--
-- Una política de UPDATE no distingue columnas: ve la fila vieja en el USING y
-- la nueva en el WITH CHECK, pero no "qué campo tocaste". De ahí el trigger. Y
-- los GRANT por columna no sirven aquí, porque todos los usuarios de la app
-- son el mismo rol de PostgreSQL: `authenticated`. El rol de negocio vive en
-- perfiles.rol, que PostgreSQL no mira al conceder privilegios.
--
-- DECISIONES DE PRODUCTO APLICADAS (Fase 4D-1)
--
--   · El mecánico LEE lo suyo y no escribe más que el avance técnico de sus
--     órdenes. Ni citas, ni clientes, ni motos, ni repuestos, ni dinero.
--   · mecanico_id IS NULL = sin asignar = INVISIBLE al mecánico. Asigna el admin.
--   · El mecánico no borra nada, nunca, en ninguna tabla.
--   · El cajero conserva exactamente lo que el código de hoy necesita.
--
-- ORDEN DE EJECUCIÓN
--   1. El bloque PRECHECK de abajo (solo lectura).
--   2. Este archivo entero, de una vez: es una sola transacción.
--   3. El bloque POSTCHECK.
--   Si algo va mal: entimotors-fase4d-rollback.sql
-- ─────────────────────────────────────────────────────────────────────────────


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  PRECHECK — SOLO LECTURA — descomentar y ejecutar ANTES. No es parte del  ║
-- ║  DDL: está comentado a propósito para que no pueda correr por accidente.  ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- select tablename, policyname, cmd, qual, with_check
--   from pg_policies where schemaname='public' order by tablename, policyname;
-- -- esperado antes de 4D: 30 políticas mencionando es_equipo(); 4D reemplaza 28
--
-- select c.relname, c.relrowsecurity
--   from pg_class c join pg_namespace n on n.oid=c.relnamespace
--  where n.nspname='public' and c.relkind='r' order by 1;
-- -- esperado: relrowsecurity = true en las 18 tablas del taller
--
-- select tgname, tgrelid::regclass, tgenabled from pg_trigger
--  where not tgisinternal and tgrelid::regclass::text in ('ordenes','citas');
-- -- esperado antes de 4D: 0 filas
--
-- select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--  where n.nspname='public' order by 1;
-- -- esperado antes de 4D: sin ve_todo_el_taller, es_mecanico_activo, mi_cliente, mi_moto
--
-- select 'perfiles' t, count(*) from public.perfiles
-- union all select 'clientes', count(*) from public.clientes
-- union all select 'motos',    count(*) from public.motos
-- union all select 'citas',    count(*) from public.citas
-- union all select 'ordenes',  count(*) from public.ordenes;
-- -- esperado: 2 / 0 / 0 / 0 / 0
--
-- select id, rol, activo from public.perfiles order by creado_en;
-- -- esperado: admin activo=true; 14722843-…-09a0ca379ab8 mecanico activo=false


begin;

-- ═════════════════════════════════════════════ 1. ÍNDICES
-- Solo los que una política nueva recorre de verdad. Nada "por si acaso".
--
--   mi_cliente() busca en citas por cliente_id   → citas.cliente_id  NO indexado
--   mi_moto()    busca en ordenes por moto_id    → ordenes.moto_id   NO indexado
--
-- Ya existen y sirven tal cual: idx_ordenes_cliente (mi_cliente sobre ordenes),
-- citas_mecanico_id_idx y ordenes_mecanico_id_idx (4C, el filtro de cada
-- SELECT), y la PK de ordenes.
create index if not exists idx_citas_cliente on public.citas(cliente_id);
create index if not exists idx_ordenes_moto  on public.ordenes(moto_id);


-- ═════════════════════════════════════════════ 2. HELPERS
-- rol_actual() ya filtra por `activo`, así que todo lo que se apoye en él deja
-- fuera automáticamente a un usuario dado de baja aunque su JWT siga vivo.

-- ¿Ve el taller entero? admin y cajero sí; mecánico no.
-- Existe puede_cobrar() con los mismos dos roles, pero significa otra cosa
-- (autoriza dinero). Mezclarlas haría que cambiar una moviera la otra sin que
-- nadie lo note, así que aquí va una función con su propio nombre.
-- SECURITY DEFINER porque lee perfiles, que tiene su propio RLS.
create or replace function public.ve_todo_el_taller() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('admin','cajero'), false)
$$;

-- ¿Es un mecánico y sigue de alta? Esta comprobación es obligatoria en cada
-- política y cada helper: sin ella, un mecánico desactivado con el JWT todavía
-- vigente seguiría leyendo sus órdenes y, a través de ellas, a sus clientes.
create or replace function public.es_mecanico_activo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() = 'mecanico', false)
$$;

-- ¿Este cliente aparece en algún trabajo mío?
-- SECURITY DEFINER a propósito: si el EXISTS fuera inline en la política de
-- clientes, la subconsulta volvería a pasar por el RLS de ordenes/citas y la
-- visibilidad de clientes quedaría encadenada en silencio a cualquier cambio
-- futuro allí. Aquí el alcance está escrito una sola vez y se lee entero.
create or replace function public.mi_cliente(p_cliente uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.es_mecanico_activo()
     and (exists (select 1 from public.ordenes o
                   where o.cliente_id = p_cliente and o.mecanico_id = auth.uid())
       or exists (select 1 from public.citas c
                   where c.cliente_id = p_cliente and c.mecanico_id = auth.uid()))
$$;

-- ¿Esta moto aparece en alguna orden mía?
-- citas NO tiene moto_id (verificado en el esquema vivo), así que una cita por
-- sí sola nunca da acceso a una moto. Solo la orden.
create or replace function public.mi_moto(p_moto uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.es_mecanico_activo()
     and exists (select 1 from public.ordenes o
                  where o.moto_id = p_moto and o.mecanico_id = auth.uid())
$$;

-- Ninguna recibe texto ni construye SQL dinámico: son SQL puro, estables, con
-- search_path fijado. anon no aparece en ningún GRANT, así que no puede
-- llamarlas ni evaluarlas dentro de una política.
--
-- service_role SÍ las necesita, y no por comodidad: el trigger de la sección 7
-- llama a es_mecanico_activo() en CADA update de ordenes o citas, y se ejecuta
-- como el invocante. Sin este permiso, toda escritura hecha con la clave de
-- servicio —el api-server, el panel de Supabase, cualquier mantenimiento—
-- moriría con «permission denied for function es_mecanico_activo». No amplía
-- nada: service_role ya se salta el RLS por definición; esto solo evita que el
-- trigger le cierre la puerta en las narices.
revoke all on function public.ve_todo_el_taller()   from public;
revoke all on function public.es_mecanico_activo()  from public;
revoke all on function public.mi_cliente(uuid)      from public;
revoke all on function public.mi_moto(uuid)         from public;
grant execute on function public.ve_todo_el_taller()  to authenticated, service_role;
grant execute on function public.es_mecanico_activo() to authenticated, service_role;
grant execute on function public.mi_cliente(uuid)     to authenticated, service_role;
grant execute on function public.mi_moto(uuid)        to authenticated, service_role;


-- ═════════════════════════════════════════════ 3. CITAS
-- El mecánico LEE las suyas y nada más. No crea, no mueve, no cancela, no
-- marca ausente, no cambia motivo ni fecha. Marcar una cita como "vista" será
-- una notificación en su momento, no un UPDATE sobre la cita.
drop policy if exists citas_equipo_lee   on public.citas;
drop policy if exists citas_equipo_crea  on public.citas;
drop policy if exists citas_equipo_edita on public.citas;
-- citas_admin_borra se queda intacta: solo el admin borra.

-- mecanico_id = auth.uid() excluye NULL por sí solo (null = uuid da null, que
-- no es true): el trabajo sin asignar no existe para el mecánico, sin más.
drop policy if exists citas_lee on public.citas;
create policy citas_lee on public.citas for select
  to authenticated
  using (
    public.ve_todo_el_taller()
    or (public.es_mecanico_activo() and mecanico_id = auth.uid())
  );

drop policy if exists citas_crea on public.citas;
create policy citas_crea on public.citas for insert
  to authenticated
  with check (public.ve_todo_el_taller());

drop policy if exists citas_edita on public.citas;
create policy citas_edita on public.citas for update
  to authenticated
  using      (public.ve_todo_el_taller())
  with check (public.ve_todo_el_taller());


-- ═════════════════════════════════════════════ 4. ORDENES
drop policy if exists ordenes_equipo_lee   on public.ordenes;
drop policy if exists ordenes_equipo_crea  on public.ordenes;
drop policy if exists ordenes_equipo_edita on public.ordenes;
-- ordenes_admin_borra se queda intacta.

drop policy if exists ordenes_lee on public.ordenes;
create policy ordenes_lee on public.ordenes for select
  to authenticated
  using (
    public.ve_todo_el_taller()
    or (public.es_mecanico_activo() and mecanico_id = auth.uid())
  );

drop policy if exists ordenes_crea on public.ordenes;
create policy ordenes_crea on public.ordenes for insert
  to authenticated
  with check (public.ve_todo_el_taller());

-- El mecánico solo alcanza sus propias filas, y solo puede dejarlas suyas: el
-- USING mira la fila vieja y el WITH CHECK la nueva, así que el par cierra las
-- dos direcciones del robo de asignación. Qué columnas puede tocar dentro de
-- esa fila lo decide el trigger de la sección 7.
drop policy if exists ordenes_edita on public.ordenes;
create policy ordenes_edita on public.ordenes for update
  to authenticated
  using (
    public.ve_todo_el_taller()
    or (public.es_mecanico_activo() and mecanico_id = auth.uid())
  )
  with check (
    public.ve_todo_el_taller()
    or (public.es_mecanico_activo() and mecanico_id = auth.uid())
  );


-- ═════════════════════════════════════════════ 5. CLIENTES Y MOTOS
-- El mecánico no navega estas tablas: llega a ellas porque abrió un trabajo
-- suyo. Por eso la regla es de relación, no de propiedad. Y solo lectura: el
-- alta y la corrección de datos del cliente son administrativas.

drop policy if exists clientes_equipo_lee   on public.clientes;
drop policy if exists clientes_equipo_crea  on public.clientes;
drop policy if exists clientes_equipo_edita on public.clientes;

drop policy if exists clientes_lee on public.clientes;
create policy clientes_lee on public.clientes for select
  to authenticated
  using (public.ve_todo_el_taller() or public.mi_cliente(id));

-- El cajero SÍ crea clientes: el POS da de alta al cliente al fiar
-- (resolverClienteCredito en app.js). Quitarle esto rompe la venta a crédito.
drop policy if exists clientes_crea on public.clientes;
create policy clientes_crea on public.clientes for insert
  to authenticated
  with check (public.ve_todo_el_taller());
drop policy if exists clientes_edita on public.clientes;
create policy clientes_edita on public.clientes for update
  to authenticated
  using (public.ve_todo_el_taller()) with check (public.ve_todo_el_taller());

drop policy if exists motos_equipo_lee   on public.motos;
drop policy if exists motos_equipo_crea  on public.motos;
drop policy if exists motos_equipo_edita on public.motos;

drop policy if exists motos_lee on public.motos;
create policy motos_lee on public.motos for select
  to authenticated
  using (public.ve_todo_el_taller() or public.mi_moto(id));

drop policy if exists motos_crea on public.motos;
create policy motos_crea on public.motos for insert
  to authenticated
  with check (public.ve_todo_el_taller());
-- Decisión 4D-1: el mecánico NO escribe motos.km. El kilometraje que tome
-- durante el trabajo va en ordenes.km_salida, que sí es suyo.
drop policy if exists motos_edita on public.motos;
create policy motos_edita on public.motos for update
  to authenticated
  using (public.ve_todo_el_taller()) with check (public.ve_todo_el_taller());


-- ═════════════════════════════════════════════ 6. EL RESTO DEL TALLER: FUERA
-- Cerrar citas y ordenes sin cerrar esto no serviría de nada: cotizaciones,
-- ventas y creditos apuntan a clientes.id, y cotizaciones además a motos.id.
-- Un mecánico reconstruiría la cartera entera por ahí.

-- ── ORDEN_ITEMS: aquí están los precios de cada trabajo ─────────────────────
-- Sin acceso por ahora. La primera versión de "Mi trabajo" no los necesita; si
-- luego hacen falta los repuestos, se hará con una superficie limitada que no
-- exponga importes.
drop policy if exists orden_items_equipo_lee   on public.orden_items;
drop policy if exists orden_items_equipo_crea  on public.orden_items;
drop policy if exists orden_items_equipo_edita on public.orden_items;
drop policy if exists orden_items_lee on public.orden_items;
create policy orden_items_lee on public.orden_items for select
  to authenticated
  using (public.ve_todo_el_taller());
drop policy if exists orden_items_crea on public.orden_items;
create policy orden_items_crea on public.orden_items for insert
  to authenticated
  with check (public.ve_todo_el_taller());
drop policy if exists orden_items_edita on public.orden_items;
create policy orden_items_edita on public.orden_items for update
  to authenticated
  using (public.ve_todo_el_taller()) with check (public.ve_todo_el_taller());

-- ── COTIZACIONES: cliente_id y moto_id, es decir, la cartera por otra puerta ─
drop policy if exists cotizaciones_equipo_lee   on public.cotizaciones;
drop policy if exists cotizaciones_equipo_crea  on public.cotizaciones;
drop policy if exists cotizaciones_equipo_edita on public.cotizaciones;
drop policy if exists cotizaciones_lee on public.cotizaciones;
create policy cotizaciones_lee on public.cotizaciones for select
  to authenticated
  using (public.ve_todo_el_taller());
drop policy if exists cotizaciones_crea on public.cotizaciones;
create policy cotizaciones_crea on public.cotizaciones for insert
  to authenticated
  with check (public.ve_todo_el_taller());
drop policy if exists cotizaciones_edita on public.cotizaciones;
create policy cotizaciones_edita on public.cotizaciones for update
  to authenticated
  using (public.ve_todo_el_taller()) with check (public.ve_todo_el_taller());

drop policy if exists cotizacion_items_equipo_lee   on public.cotizacion_items;
drop policy if exists cotizacion_items_equipo_crea  on public.cotizacion_items;
drop policy if exists cotizacion_items_equipo_edita on public.cotizacion_items;
drop policy if exists cotizacion_items_lee on public.cotizacion_items;
create policy cotizacion_items_lee on public.cotizacion_items for select
  to authenticated
  using (public.ve_todo_el_taller());
drop policy if exists cotizacion_items_crea on public.cotizacion_items;
create policy cotizacion_items_crea on public.cotizacion_items for insert
  to authenticated
  with check (public.ve_todo_el_taller());
drop policy if exists cotizacion_items_edita on public.cotizacion_items;
create policy cotizacion_items_edita on public.cotizacion_items for update
  to authenticated
  using (public.ve_todo_el_taller()) with check (public.ve_todo_el_taller());

-- ── DINERO: el mecánico nunca tuvo por qué ver la facturación del taller ────
-- Las políticas de INSERT/UPDATE de estas tablas ya son puede_cobrar() o
-- es_admin(); lo único abierto al mecánico era el SELECT. Eso es lo que cambia.
drop policy if exists ventas_lee on public.ventas;
create policy ventas_lee on public.ventas for select
  to authenticated
  using (public.ve_todo_el_taller());

drop policy if exists venta_items_lee on public.venta_items;
create policy venta_items_lee on public.venta_items for select
  to authenticated
  using (public.ve_todo_el_taller());

drop policy if exists creditos_lee on public.creditos;
create policy creditos_lee on public.creditos for select
  to authenticated
  using (public.ve_todo_el_taller());

drop policy if exists credito_items_lee on public.credito_items;
create policy credito_items_lee on public.credito_items for select
  to authenticated
  using (public.ve_todo_el_taller());

drop policy if exists abonos_lee on public.abonos;
create policy abonos_lee on public.abonos for select
  to authenticated
  using (public.ve_todo_el_taller());

-- caja_movimientos ya era puede_cobrar() en las cuatro operaciones. Sin cambio.

-- ── INVENTARIO: no se sincroniza todavía, así que el mecánico no lo necesita ─
drop policy if exists inventario_lee on public.inventario;
create policy inventario_lee on public.inventario for select
  to authenticated
  using (public.ve_todo_el_taller());

drop policy if exists categorias_lee on public.categorias_inv;
create policy categorias_lee on public.categorias_inv for select
  to authenticated
  using (public.ve_todo_el_taller());

-- web_cms se queda en es_equipo() a propósito: es el contenido de la web
-- pública, ya visible en internet para cualquiera. No hay nada que filtrar.
-- auditoria tampoco cambia: el mecánico INSERTA sus acciones (así debe ser) y
-- no puede leer el registro, que ya era es_admin().


-- ═════════════════════════════════════════════ 7. TRIGGER FAIL-CLOSED
-- La barrera que RLS no puede dar: qué columnas.
--
-- No enumera lo prohibido, enumera lo PERMITIDO y bloquea todo lo demás
-- comparando el resto de la fila. Una columna que se añada mañana nace
-- bloqueada para el mecánico, sin que nadie tenga que acordarse de ella.
--
-- SECURITY INVOKER (el defecto): esta función no necesita privilegios
-- elevados, solo comparar OLD contra NEW. rol_actual(), a la que llama, ya es
-- SECURITY DEFINER y está concedida a authenticated.
--
-- Verificado antes de escribirlo: hoy NO hay ningún trigger sobre ordenes ni
-- citas (los 4 del esquema están en perfiles, auth.users y caja_movimientos),
-- y ninguna de las dos tablas tiene columna de sello automático tipo
-- actualizado_en — eso solo existe en clientes y web_cms. Así que no hay
-- escritura automática que pueda producir un bloqueo falso.

create or replace function public.mecanico_solo_avance_tecnico()
returns trigger language plpgsql set search_path = public as $$
declare
  -- Lo único que un mecánico puede mover en SU orden. Todo lo que no esté
  -- aquí queda bloqueado, incluidas las columnas que aún no existen.
  k_permitidos text[] := array[
    'estado', 'diagnostico', 'reparacion_notas', 'calidad_checklist',
    'fotos', 'km_salida', 'falla'
  ];
  -- Las 6 etapas reales de app.js (const STAGES), en su orden. No se inventa
  -- ninguna: es literalmente ese array.
  k_etapas text[] := array[
    'recibido', 'diagnostico', 'presupuesto', 'reparacion', 'calidad', 'entregado'
  ];
  v_i_old int;
  v_i_new int;
begin
  -- Solo se restringe a un mecánico REAL y de alta. Se pregunta por
  -- es_mecanico_activo() y no por `rol_actual() <> 'mecanico'` a propósito: si
  -- el actor no tiene sesión de perfil —service_role, el propietario de la
  -- tabla, una tarea de mantenimiento— rol_actual() devuelve null, y comparar
  -- null con texto da null, no false. La función coalesce a false, así que un
  -- actor sin perfil nunca se confunde con un mecánico ni queda a medio
  -- camino entre las dos ramas.
  --
  -- Esto NO amplía el acceso de nadie: quien no es mecánico sigue sujeto a
  -- RLS, que es donde están sus límites.
  if not public.es_mecanico_activo() then
    return new;
  end if;

  -- ── 0. Un trabajo entregado está cerrado.
  -- Los 7 campos técnicos son libres mientras el trabajo está en curso, y las
  -- comprobaciones de etapa solo saltan cuando `estado` cambia — así que sin
  -- esto un mecánico podría seguir reescribiendo el diagnóstico, las notas o
  -- las fotos de una orden ya entregada y cobrada, sin tocar la etapa. Una vez
  -- entregada, para él es historia.
  if old.estado = 'entregado' then
    raise exception 'Este trabajo ya fue entregado: un mecánico no puede modificarlo';
  end if;

  -- En citas el mecánico no tiene UPDATE en absoluto. La política ya lo
  -- impide; esto es el cinturón por si alguien añade una política mañana.
  if TG_TABLE_NAME = 'citas' then
    raise exception 'Un mecánico no modifica citas';
  end if;

  -- ── 1. La asignación es intocable en las dos columnas y las dos direcciones.
  -- Explícito además del fail-closed, para que el mensaje diga qué pasó y para
  -- que siga cerrado aunque alguien añada estos campos a k_permitidos.
  -- `is distinct from` y no `<>`: con `<>`, un cambio desde o hacia NULL da
  -- NULL, el if no entra y el cambio pasaría. Justo el caso de lo sin asignar.
  if new.mecanico_id is distinct from old.mecanico_id then
    raise exception 'Un mecánico no puede cambiar la asignación de un trabajo';
  end if;
  if new.mecanico is distinct from old.mecanico then
    raise exception 'Un mecánico no puede cambiar el nombre asignado al trabajo';
  end if;

  -- ── 2. Solo avance técnico, y de una etapa en una.
  -- app.js permite hoy tres movimientos: avanzar uno (btnAvanzar), retroceder
  -- uno (btnRetroceder) y saltar a cualquier etapa tocándola en el tracker
  -- (renderStageTracker). Para el mecánico solo sobrevive el primero.
  if new.estado is distinct from old.estado then
    v_i_old := array_position(k_etapas, old.estado);
    v_i_new := array_position(k_etapas, new.estado);

    -- Una etapa que no está en STAGES no la pone un mecánico, sea lo que sea.
    if v_i_old is null or v_i_new is null then
      raise exception 'Etapa desconocida: "%"', coalesce(new.estado, '(nula)');
    end if;

    -- Ni saltos ni marcha atrás: exactamente el siguiente peldaño.
    if v_i_new <> v_i_old + 1 then
      raise exception 'Un mecánico solo avanza una etapa a la vez: de "%" solo puede pasar a "%"',
        old.estado, coalesce(k_etapas[v_i_old + 1], '(ninguna)');
    end if;

    -- Y el último peldaño no es suyo: entregar y cobrar es administrativo.
    if new.estado = 'entregado' then
      raise exception 'Un mecánico no entrega ni cobra: el trabajo técnico termina en "calidad"';
    end if;
  end if;

  -- ── 3. Fail-closed: si algo fuera de la lista permitida cambió, se acabó.
  if (to_jsonb(new) - k_permitidos) is distinct from (to_jsonb(old) - k_permitidos) then
    raise exception 'Un mecánico solo puede actualizar el avance técnico (etapa, diagnóstico, notas, checklist, fotos, kilometraje y falla)';
  end if;

  return new;
end $$;

drop trigger if exists ordenes_mecanico_avance on public.ordenes;
create trigger ordenes_mecanico_avance
  before update on public.ordenes
  for each row execute function public.mecanico_solo_avance_tecnico();

drop trigger if exists citas_mecanico_avance on public.citas;
create trigger citas_mecanico_avance
  before update on public.citas
  for each row execute function public.mecanico_solo_avance_tecnico();

-- ═════════════════════════════════════════════ 8. FUNCIONES TÉCNICAS
-- estado_tecnico() ya exige es_admin() or es_desarrollador(): correcta, no se
-- toca. estadisticas_tecnicas() en cambio admite hoy los cuatro roles, así que
-- un mecánico obtiene los conteos globales del negocio — cuántos clientes,
-- cuántas ventas hoy. No identifica a nadie, pero es información del taller y
-- él no la necesita.
--
-- Cambio mínimo: solo la línea del control de rol. El cuerpo, los conteos y la
-- firma quedan idénticos a entimotors-usuarios.sql. Verificado antes de
-- cerrarla: la única llamada en todo el proyecto está en panel-tecnico.html,
-- que es la superficie de admin/desarrollador. El cajero no depende de ella.
create or replace function public.estadisticas_tecnicas() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_rol text;
begin
  v_rol := public.rol_actual();
  -- rol_actual() ya filtra por activo = true, así que un usuario dado de baja
  -- recibe null y no pasa de aquí.
  if not (public.es_admin() or public.es_desarrollador()) then
    raise exception 'Solo el administrador y el desarrollador pueden consultar las estadísticas técnicas';
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

-- ═════════════════════════════════════════════ 9. STORAGE
-- El bucket entimotors-taller (privado) tiene hoy dos políticas con es_equipo(),
-- así que un mecánico podría leer y subir media de todo el taller.
--
-- POR QUÉ AQUÍ NO SE ESCRIBE UNA REGLA "SOLO MI ORDEN":
-- porque no hay con qué. La PWA no usa Supabase Storage en absoluto: las fotos
-- se guardan como data URL base64 dentro de ordenes.fotos (fileToDataUrl en
-- app.js). No existe convención de rutas, ni objetos, ni forma de relacionar
-- storage.objects.name con una orden. Inventar aquí un formato de path sería
-- adivinar, y una política que dependa de un formato que nadie escribe todavía
-- es una política que no protege nada.
--
-- Lo que sí se puede hacer sin inventar nada: cerrar el bucket al mecánico,
-- igual que el resto de tablas. Hoy no rompe absolutamente nada — el bucket
-- está vacío y ningún código lo toca —, y deja la puerta cerrada por defecto
-- para cuando llegue la sincronización de fotos. En ese momento (4E) la ruta
-- debe nacer con el UUID de la orden dentro, y esta política se afina.
--
-- Nota: la confidencialidad de las fotos HOY ya la da la política de ordenes,
-- porque las fotos viven en la fila, no en Storage.
--
-- taller_borra_media no se toca: ya es es_admin().
drop policy if exists taller_lee_media  on storage.objects;
create policy taller_lee_media on storage.objects for select
  to authenticated
  using (bucket_id = 'entimotors-taller' and public.ve_todo_el_taller());

drop policy if exists taller_sube_media on storage.objects;
create policy taller_sube_media on storage.objects for insert
  to authenticated
  with check (bucket_id = 'entimotors-taller' and public.ve_todo_el_taller());

commit;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  POSTCHECK — SOLO LECTURA — descomentar y ejecutar DESPUÉS.               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- select tablename, policyname, cmd, qual, with_check
--   from pg_policies where schemaname='public' order by tablename, policyname;
-- -- esperado: 0 políticas con es_equipo() salvo cms_lee y auditoria_crea
--
-- select count(*) from pg_policies
--  where schemaname='public' and (qual like '%es_equipo%' or with_check like '%es_equipo%');
-- -- esperado: 2  (cms_lee, auditoria_crea)
--
-- select tgname, tgrelid::regclass from pg_trigger
--  where not tgisinternal and tgrelid::regclass::text in ('ordenes','citas');
-- -- esperado: ordenes_mecanico_avance, citas_mecanico_avance
--
-- select proname, prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--  where n.nspname='public'
--    and proname in ('ve_todo_el_taller','es_mecanico_activo','mi_cliente','mi_moto',
--                    'mecanico_solo_avance_tecnico') order by 1;
-- -- esperado: 5 filas; prosecdef = true en las 4 primeras, false en el trigger
--
-- select indexname from pg_indexes
--  where schemaname='public' and indexname in ('idx_citas_cliente','idx_ordenes_moto');
-- -- esperado: las 2
--
-- select 'perfiles' t, count(*) from public.perfiles
-- union all select 'clientes', count(*) from public.clientes
-- union all select 'motos',    count(*) from public.motos
-- union all select 'citas',    count(*) from public.citas
-- union all select 'ordenes',  count(*) from public.ordenes;
-- -- esperado: 2 / 0 / 0 / 0 / 0 — igual que en el precheck
--
-- select id, rol, activo from public.perfiles order by creado_en;
-- -- esperado: idéntico al precheck; el mecánico temporal sigue activo=false
