# Registro de cambios · ENTIMOTORS OS

## 3.12.0 — 4 de septiembre de 2026

> **Esta versión NO constituye todavía el piloto multiusuario con Supabase.**
> El sistema sigue funcionando entero en el dispositivo, con IndexedDB. La base de
> datos en Supabase quedó creada y verificada, pero la aplicación todavía no se
> conecta con ella.

Actualización centrada en **integridad del dinero y seguridad de los datos**. Corrige
errores que estaban en producción y podían costar plata de verdad.

### Seguridad

- La aplicación **ya no se actualiza sola**. Antes, al haber versión nueva, el
  Service Worker tomaba el control y recargaba sin avisar — con datos que solo
  existen en ese teléfono. Ahora aparece un aviso con tres opciones (crear copia y
  actualizar · solo crear copia · ahora no), y **si la copia no se verifica, no se
  actualiza**.
- La cuenta `prueba` ya no siembra datos de ejemplo encima de información real.
  Como su contraseña está en el código, bastaba con entrar con ella en el celular
  del cliente para mezclarle clientes y repuestos inventados con los suyos.
- Los modales de confirmación pasan por encima de cualquier otro. Antes quedaban
  tapados y el botón no se podía tocar: el aviso de choque de horario al mover una
  cita era imposible de responder.

### Base de datos

- Esquema de IndexedDB de la **v5 a la v6**.
- Nuevas tablas locales: `auditoria` (bitácora) y `sync_cola` (cola de cambios
  pendientes de subir).
- La migración v5 → v6 se probó **contra la versión 3.11 real descargada de
  producción**, con datos de taller: cliente, moto, inventario, venta, crédito con
  abono, orden, cotización y cita. **Ningún registro perdido**; saldos y caja
  idénticos antes y después.

### Finanzas

- **Costos históricos.** Ni las ventas ni los créditos ni las órdenes guardaban a
  cuánto había costado el repuesto, así que la ganancia se recalculaba con el costo
  de hoy: subirle el precio a un repuesto **cambiaba hacia atrás la ganancia de
  ventas ya cerradas**, y borrarlo del inventario la inflaba a costo cero. Ahora el
  costo se congela en el momento exacto de la operación. Los registros anteriores a
  esta versión se rellenaron con el costo actual y quedan **marcados como
  estimados**, nunca presentados como exactos.
- **El abono ya es atómico.** Bajaba el saldo del crédito y metía el dinero en caja
  en dos guardados separados: si el segundo fallaba, el crédito quedaba cobrado y
  la plata no aparecía en el libro. Ahora las dos escrituras van en la misma
  transacción.
- **El abono ya no se puede cobrar dos veces.** Lleva identificador único;
  repetirlo —doble toque o reintento por mala señal— se ignora.
- **Se acabó el cobro triplicado al finalizar una orden.** Tres toques seguidos en
  «Finalizar trabajo» registraban tres ingresos: medido, **L.3 600 por una orden de
  L.1 200**. Ahora hay guarda de doble toque y comprobación del estado guardado.
- **Una orden ya no se cierra sin su registro financiero.** Antes se marcaba
  finalizada *antes* de crear el crédito o el ingreso; si eso fallaba, la orden
  quedaba cerrada, el cliente debiendo y sin rastro de la deuda. Ahora primero el
  cobro y solo si sale bien se cierra.
- **No se puede borrar la contraparte contable** de una venta, un abono o una
  orden. Esas líneas muestran un candado en vez del botón de borrar. Los
  movimientos escritos a mano se siguen borrando normalmente.
- Nueva **bitácora de auditoría**: quién, qué, cuándo y sobre qué registro. Cubre
  ventas, abonos, finalización de órdenes, movimientos de caja, respaldos y
  restauraciones. Sobrevive a una restauración y no se puede editar ni borrar.

### Inventario

- Cuando no alcanza la existencia, **se informa cuánto faltó** con nombre y
  cantidad. Antes el faltante se convertía en cero en silencio.
- Corregido: los repuestos **importados por CSV se ofrecían a L. 0.00** al
  agregarlos a una orden, porque la importación guardaba el precio en un solo
  campo. Ahora guarda los dos, más el stock mínimo y la categoría.

### Backup

- El respaldo **se verifica solo**: se relee la base y se compara tabla por tabla.
  Si no cuadra, no se entrega la copia y se dice por qué.
- Cabecera completa: identificador, versión de app, versión de esquema, fecha,
  quién la hizo, dispositivo y conteo por tabla.
- **Compartir la copia** con el menú del teléfono — WhatsApp, Archivos o a otra
  persona.
- El sistema **recuerda cuándo fue la última copia** y avisa en rojo si pasó una
  semana.
- **Restaurar guarda antes una copia de lo actual**, automáticamente. Se puede
  elegir entre reemplazar o combinar, explicado en palabras. Probado con seis tipos
  de archivo inválido: ninguno alteró la base.

### PWA

- El Service Worker ya no llama a `skipWaiting()` por su cuenta: espera a que la
  persona acepte y solo entonces se activa.
- IndexedDB sobrevive a la actualización — comprobado con datos reales.

### Correcciones

- El buscador global no encontraba las cotizaciones y mostraba **L. 0.00** en los
  repuestos importados.
- Una cotización hecha de noche decía «16 días» en vez de 15, por mezclar días con
  horas sueltas.
- Una cotización ya aceptada seguía mostrando su fecha de vencimiento, como si
  siguiera contando.
- Un cliente sin teléfono dejaba un guion colgando en la factura y en el estado de
  cuenta.
- El sistema decía haber **enviado** mensajes de WhatsApp que en realidad solo
  abría. Ahora dice «WhatsApp abierto… falta pulsar enviar».
- El indicador de conexión decía **«sincronizado»** sin que existiera ningún
  servidor. Ahora dice «Solo en este dispositivo · respalda seguido».

### Preparación Supabase

- Nuevo `supabase/entimotors-completo.sql`: 18 tablas, 56 políticas RLS, 5
  funciones, 12 índices y 2 disparadores. Idempotente. **Ya ejecutado y verificado
  contra el proyecto real.**
- Nuevo bucket privado `entimotors-taller` para las fotos de las motos. El bucket
  público del catálogo web no se tocó.
- `supabase/README-MAPA.md` con la correspondencia IndexedDB → Supabase y la
  estrategia de identificadores para no romper relaciones al migrar.
- Nuevos `SUPABASE-CONFIG.md` y `SUPABASE-STATUS.md`.
- La cola `sync_cola` ya anota cada cambio, en orden y con identificador único,
  esperando a que exista a dónde subirlo.

### Pruebas

101 pruebas de aplicación, 41 de regresión, 16 de permisos en PostgreSQL local y 9
de restricciones contra el proyecto real de Supabase. **0 fallos. 0 errores de
consola. 0 promesas rechazadas.**

---

## 3.11.0 — versión en producción

Cotizaciones con vigencia, envío de facturas por WhatsApp como imagen o PDF.
Es la versión que el cliente usa hoy.
