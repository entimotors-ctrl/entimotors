# ENTIMOTORS OS

Sistema de gestión para un taller de motocicletas. Recibe la moto, la sigue por las
seis etapas de reparación, cobra, controla el inventario, lleva la caja y los
créditos, y le manda al cliente su factura por WhatsApp.

**Versión actual:** 3.12.0 · **Esquema de datos:** IndexedDB v6

---

## Cómo funciona hoy

Es una **aplicación web instalable (PWA)** que corre **entera dentro del teléfono o
la computadora**. No hay servidor, no hay mensualidad de hosting y **funciona sin
internet** — el taller no se detiene cuando se cae la señal.

Toda la información se guarda en **IndexedDB**, en el dispositivo. Esa misma
decisión es también su límite principal: si se borra la aplicación o se pierde el
teléfono, los datos se van con él. Por eso el sistema insiste tanto con las copias
de seguridad, y por qué existe la fase siguiente.

### Lo que hace

| Sección | Para qué |
|---|---|
| Página principal | Lo pendiente del día de un vistazo |
| Cotizaciones | El precio antes de tocar la moto, con vigencia de 7, 15 o 30 días |
| Órdenes de servicio | Las seis etapas, del recibo a la entrega |
| Citas | Agenda con horarios y mecánicos |
| Clientes y motos | Ficha, historial y semáforo de mantenimiento |
| Inventario | Costo, precio, stock mínimo, categorías y código de barras |
| Venta rápida (TPV) | El mostrador, con contado o crédito |
| Finanzas y caja | Libro de caja, utilidad y cuentas por cobrar |
| Créditos | Lo fiado, con abonos y estado de cuenta |
| Gestor de la web | Lo que ve el público en la página del taller |
| Ajustes | Respaldos, restauración y estado del sistema |

Además: buscador global (Ctrl+K), centro de avisos, modo claro y oscuro, dos roles
(administrador y mecánico), bitácora de auditoría, y seis documentos imprimibles
que se pueden enviar como imagen o PDF.

---

## Supabase: preparado, todavía no conectado

La base de datos en la nube **ya existe y está verificada**: 18 tablas, 56 políticas
de seguridad, las funciones de venta y abono, los candados que impiden stock
negativo y cobros duplicados, y un bucket privado para las fotos.

**Pero la aplicación todavía no habla con ella.** No hay ni una línea de código de
Supabase en el frontend. El sistema sigue guardando todo en el dispositivo.

Lo que falta para la fase siguiente:

1. La **clave pública** (anon key) del proyecto
2. Los **usuarios** en Supabase Auth con su rol
3. El **código de sincronización**: cliente, login, subida, bajada y migración

Detalles en [`SUPABASE-CONFIG.md`](SUPABASE-CONFIG.md) y el estado exacto en
[`SUPABASE-STATUS.md`](SUPABASE-STATUS.md).

---

## Ejecutarlo localmente

No hace falta compilar nada: son tres archivos y una carpeta de iconos.

```bash
cd taller-demo
python3 -m http.server 5500
```

Y abrir <http://localhost:5500>.

> **Tiene que servirse por HTTP, no abriendo el archivo directamente.** El Service
> Worker y IndexedDB no funcionan con `file://`.

La aplicación pide instalarse como PWA antes de dejar entrar. Para saltarse ese
paso durante el desarrollo hay un enlace al pie de esa pantalla.

### Estructura

```
taller-demo/
  index.html        interfaz completa y estilos
  app.js            toda la lógica
  sw.js             Service Worker (caché y actualización controlada)
  manifest.json     datos de instalación de la PWA
  icons/            iconos y marca de agua de los documentos
  supabase/
    entimotors-completo.sql   todo el esquema, RLS y funciones
    README-MAPA.md            correspondencia IndexedDB → Supabase
api-server/         backend del sitio web público (independiente del taller)
```

### Publicar una versión nueva

Al cambiar algo hay que subir el número de versión en **tres sitios**, o el
dispositivo se queda con la copia vieja:

1. `index.html` → `<script src="app.js?v=X.Y.Z">`
2. `sw.js` → `CACHE_NAME`
3. `sw.js` → la entrada de `app.js` dentro de `SHELL`

---

## Seguridad

- **Nunca** poner la clave `service_role` de Supabase en el frontend: se salta
  todas las políticas de seguridad. Va solo en el servidor, por variable de
  entorno.
- Las contraseñas del equipo están hoy dentro de `app.js` y llegan al navegador.
  Sirven para separar lo que ve el mecánico de lo que ve el dueño en el día a día,
  **no son seguridad real**. Se resuelven cuando entre Supabase Auth.
- El archivo `api-server/.env` está en `.gitignore` y nunca ha entrado al
  historial de Git.

---

## Estado

Sirve para un **piloto local**: un taller, un dispositivo, con respaldo semanal
guardado fuera del teléfono. **Todavía no** para varios talleres, varios
dispositivos ni acceso desde fuera — eso llega con la sincronización.

Ver [`CHANGELOG.md`](CHANGELOG.md) para el detalle de cada versión.
