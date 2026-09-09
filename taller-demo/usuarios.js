/* ============================================================================
 * ENTIMOTORS OS · usuarios.js — pantalla «Usuarios y equipo»
 *
 * Habla ÚNICAMENTE con el api-server, nunca directamente con Supabase para
 * administrar cuentas: crear un usuario exige la clave de servidor, y esa clave
 * no puede pisar el navegador. Lo que viaja es el token de la sesión del admin;
 * el servidor comprueba por su cuenta que quien llama es administrador.
 *
 * Esconder botones no es seguridad: el backend rechaza igual a quien no sea
 * admin. Esto solo evita enseñar lo que no toca.
 * ==========================================================================*/
(function (global) {
  "use strict";

  var ROLES = [
    { valor: "mecanico", texto: "Mecánico" },
    { valor: "cajero", texto: "Cajero" },
    { valor: "desarrollador", texto: "Desarrollador" },
  ];
  var NOMBRE_ROL = { admin: "Administrador", mecanico: "Mecánico", cajero: "Cajero", desarrollador: "Desarrollador" };

  function baseApi() {
    var cfg = global.ENTIMOTORS_SUPABASE || {};
    return (cfg.apiUrl || "").replace(/\/+$/, "");
  }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function aviso(msg) { if (typeof toast === "function") toast(msg, "off"); }
  function bien(msg) { if (typeof toast === "function") toast(msg); }

  /* Todas las llamadas pasan por aquí: una sola puerta para el token y para
     traducir los fallos a algo que se pueda leer. */
  async function pedir(metodo, ruta, cuerpo) {
    var base = baseApi();
    if (!base) return { ok: false, motivo: "sin-servidor" };
    if (!global.Auth || !Auth.estado().conSesion) return { ok: false, motivo: "sin-sesion" };
    if (navigator.onLine === false) return { ok: false, motivo: "sin-conexion" };

    var ses = global.SupabaseCliente && SupabaseCliente.sesion();
    if (!ses || !ses.access_token) return { ok: false, motivo: "sin-sesion" };

    var corta = new AbortController();
    var reloj = setTimeout(function () { corta.abort(); }, 20000);
    try {
      var res = await fetch(base + "/api/admin/usuarios" + (ruta || ""), {
        method: metodo,
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer " + ses.access_token,
        },
        body: cuerpo ? JSON.stringify(cuerpo) : undefined,
        signal: corta.signal,
      });
      clearTimeout(reloj);
      var datos = null;
      try { datos = await res.json(); } catch (e) { datos = null; }
      if (!res.ok) {
        return { ok: false, motivo: res.status === 401 ? "sin-sesion"
                            : res.status === 403 ? "sin-permiso" : "rechazado",
                 mensaje: (datos && datos.error) || "No se pudo completar la operación.", http: res.status };
      }
      return { ok: true, datos: datos };
    } catch (e) {
      clearTimeout(reloj);
      return { ok: false, motivo: e && e.name === "AbortError" ? "tiempo-agotado" : "sin-conexion" };
    }
  }

  function pintarMensaje(html) {
    var c = document.getElementById("usuariosCuerpo");
    if (c) c.innerHTML = '<div class="card"><p class="hint" style="margin:0;">' + html + "</p></div>";
  }

  var enCurso = false;

  async function render() {
    var c = document.getElementById("usuariosCuerpo");
    if (!c) return;

    // ── condiciones para que esta pantalla tenga sentido ──
    if (!global.Auth || !Auth.esAdmin()) {
      pintarMensaje("Esta sección es solo para el administrador.");
      return;
    }
    if (!baseApi()) {
      pintarMensaje("Falta indicar la dirección del servidor. Se configura en " +
        "<code>supabase-config.js</code>, campo <code>apiUrl</code>.");
      return;
    }
    if (navigator.onLine === false) {
      pintarMensaje("<b>Usuarios y equipo no está disponible sin conexión.</b><br>" +
        "Esta pantalla lee y escribe en el servidor: no se puede trabajar con una copia local. " +
        "El resto del sistema sigue funcionando con normalidad.");
      return;
    }

    c.innerHTML = '<div class="card"><p class="hint" style="margin:0;">Cargando el equipo…</p></div>';
    var r = await pedir("GET", "");
    if (!r.ok) { pintarMensaje(textoDeFallo(r)); return; }

    var us = (r.datos && r.datos.usuarios) || [];
    var filas = us.map(function (u) {
      var acciones = u.esUsted || u.rol === "admin"
        ? '<span class="hint">—</span>'
        : '<div style="display:flex; gap:0.35rem; flex-wrap:wrap;">' +
            '<select class="u-rol" data-id="' + esc(u.id) + '" style="padding:0.3rem 0.4rem;">' +
              ROLES.map(function (x) {
                return '<option value="' + x.valor + '"' + (u.rol === x.valor ? " selected" : "") + ">" + x.texto + "</option>";
              }).join("") +
            "</select>" +
            '<button class="btn small ghost u-estado" data-id="' + esc(u.id) + '" data-activo="' + (u.activo ? "1" : "0") + '">' +
              (u.activo ? "Dar de baja" : "Reactivar") + "</button>" +
            '<button class="btn small ghost u-editar" data-id="' + esc(u.id) + '" data-nombre="' + esc(u.nombre) +
              '" data-telefono="' + esc(u.telefono) + '">Editar</button>' +
          "</div>";
      return "<tr>" +
        "<td>" + esc(u.nombre) + (u.esUsted ? ' <span class="hint">(tú)</span>' : "") + "</td>" +
        "<td>" + esc(u.correo) + "</td>" +
        "<td>" + (esc(u.telefono) || '<span class="hint">—</span>') + "</td>" +
        "<td>" + esc(NOMBRE_ROL[u.rol] || u.rol) + "</td>" +
        '<td>' + (u.activo ? "Activo" : '<span style="opacity:.65;">Inactivo</span>') + "</td>" +
        "<td>" + acciones + "</td></tr>";
    }).join("");

    c.innerHTML =
      '<div class="card">' +
        '<div style="display:flex; justify-content:space-between; align-items:center; gap:0.6rem; flex-wrap:wrap; margin-bottom:0.6rem;">' +
          '<h3 class="font-display" style="font-size:0.95rem; margin:0;">Equipo · ' + us.length + "</h3>" +
          '<button class="btn primary small" id="btnNuevoUsuario">+ Nuevo usuario</button>' +
        "</div>" +
        '<div class="table-scroll"><table><thead><tr>' +
          "<th>Nombre</th><th>Correo</th><th>Teléfono</th><th>Rol</th><th>Estado</th><th>Acciones</th>" +
        "</tr></thead><tbody>" + filas + "</tbody></table></div>" +
        '<p class="hint" style="margin:0.6rem 0 0;">Dar de baja no borra nada: la persona deja de poder entrar, ' +
        "pero su historial en órdenes, ventas y bitácora se queda como está.</p>" +
      "</div>" +
      '<div class="card" id="cardNuevoUsuario" style="margin-top:1rem; display:none;">' +
        '<h3 class="font-display" style="font-size:0.95rem; margin:0 0 0.5rem;">Nuevo usuario</h3>' +
        '<div class="grid-2">' +
          "<div><label>Nombre</label><input type=\"text\" id=\"nuNombre\" maxlength=\"60\" placeholder=\"Juan Pérez\"></div>" +
          "<div><label>Correo</label><input type=\"email\" id=\"nuCorreo\" placeholder=\"juan@entimotors.hn\"></div>" +
          "<div><label>Teléfono</label><input type=\"text\" id=\"nuTelefono\" placeholder=\"9704-9635\"></div>" +
          '<div><label>Rol</label><select id="nuRol">' +
            ROLES.map(function (x) { return '<option value="' + x.valor + '">' + x.texto + "</option>"; }).join("") +
          "</select></div>" +
        "</div>" +
        '<p class="hint" style="margin:0.5rem 0;">La contraseña no se pone aquí. Al crear la cuenta se genera un ' +
        "enlace de un solo uso para que la persona elija la suya. El administrador nunca llega a conocerla.</p>" +
        '<div style="display:flex; gap:0.5rem;">' +
          '<button class="btn primary small" id="btnCrearUsuario">Crear</button>' +
          '<button class="btn small ghost" id="btnCancelarUsuario">Cancelar</button>' +
        "</div>" +
        '<div id="nuResultado" style="margin-top:0.6rem;"></div>' +
      "</div>";

    enganchar();
  }

  function textoDeFallo(r) {
    if (r.motivo === "sin-servidor") return "Falta configurar <code>apiUrl</code> en <code>supabase-config.js</code>.";
    if (r.motivo === "sin-conexion") return "Sin conexión con el servidor. Esta pantalla necesita internet.";
    if (r.motivo === "tiempo-agotado") return "El servidor tardó demasiado en responder.";
    if (r.motivo === "sin-sesion") return "Tu sesión ha caducado. Vuelve a entrar.";
    if (r.motivo === "sin-permiso") return "Solo el administrador puede gestionar usuarios.";
    return esc(r.mensaje || "No se pudo completar la operación.");
  }

  function enganchar() {
    var nuevo = document.getElementById("btnNuevoUsuario");
    var card = document.getElementById("cardNuevoUsuario");
    if (nuevo) nuevo.addEventListener("click", function () { card.style.display = card.style.display === "none" ? "" : "none"; });
    var cancelar = document.getElementById("btnCancelarUsuario");
    if (cancelar) cancelar.addEventListener("click", function () { card.style.display = "none"; });

    document.querySelectorAll(".u-rol").forEach(function (sel) {
      sel.addEventListener("change", async function () {
        if (enCurso) return; enCurso = true;
        var r = await pedir("PATCH", "/" + sel.dataset.id, { rol: sel.value });
        enCurso = false;
        if (!r.ok) { aviso(quitarHtml(textoDeFallo(r))); render(); return; }
        bien("Rol actualizado");
        render();
      });
    });

    document.querySelectorAll(".u-estado").forEach(function (b) {
      b.addEventListener("click", async function () {
        if (enCurso) return; enCurso = true;
        b.disabled = true;
        var r = await pedir("PATCH", "/" + b.dataset.id, { activo: b.dataset.activo !== "1" });
        enCurso = false; b.disabled = false;
        if (!r.ok) { aviso(quitarHtml(textoDeFallo(r))); return; }
        bien(b.dataset.activo === "1" ? "Usuario dado de baja" : "Usuario reactivado");
        render();
      });
    });

    document.querySelectorAll(".u-editar").forEach(function (b) {
      b.addEventListener("click", async function () {
        if (typeof showPrompt !== "function") return;
        var nombre = await showPrompt("Nombre", { titulo: "Editar usuario", valorInicial: b.dataset.nombre });
        if (nombre == null) return;
        var tel = await showPrompt("Teléfono (puede quedar vacío)", { titulo: "Editar usuario", valorInicial: b.dataset.telefono });
        if (tel == null) return;
        var r = await pedir("PATCH", "/" + b.dataset.id, { nombre: nombre.trim(), telefono: tel.trim() });
        if (!r.ok) { aviso(quitarHtml(textoDeFallo(r))); return; }
        bien("Datos actualizados");
        render();
      });
    });

    var crear = document.getElementById("btnCrearUsuario");
    if (crear) crear.addEventListener("click", async function () {
      if (enCurso) return; enCurso = true;
      crear.disabled = true; crear.textContent = "Creando…";
      var r = await pedir("POST", "", {
        nombre: document.getElementById("nuNombre").value.trim(),
        correo: document.getElementById("nuCorreo").value.trim(),
        telefono: document.getElementById("nuTelefono").value.trim(),
        rol: document.getElementById("nuRol").value,
      });
      enCurso = false; crear.disabled = false; crear.textContent = "Crear";
      var caja = document.getElementById("nuResultado");
      if (!r.ok) { caja.innerHTML = '<p class="gate-error" style="margin:0;">' + textoDeFallo(r) + "</p>"; return; }
      var enlace = r.datos && r.datos.enlaceParaEstablecerClave;
      /* La lista NO se refresca sola: hacerlo redibujaría la pantalla y se
         llevaría por delante el enlace antes de que dé tiempo a copiarlo.
         Se actualiza cuando la persona diga que ya lo tiene. */
      caja.innerHTML =
        '<p class="hint" style="margin:0 0 0.4rem;"><b>Cuenta creada.</b> ' + esc(r.datos.nota || "") + "</p>" +
        (enlace ? '<input type="text" readonly value="' + esc(enlace) + '" style="width:100%; margin-bottom:0.5rem;" id="nuEnlace">' : "") +
        '<div style="display:flex; gap:0.5rem; flex-wrap:wrap;">' +
          (enlace ? '<button class="btn small" id="btnCopiarEnlace">Copiar enlace</button>' : "") +
          '<button class="btn primary small" id="btnListoUsuario">Listo · actualizar lista</button>' +
        "</div>";
      var campo = document.getElementById("nuEnlace");
      if (campo) campo.addEventListener("click", function () { campo.select(); });
      var copiar = document.getElementById("btnCopiarEnlace");
      if (copiar) copiar.addEventListener("click", function () {
        if (campo) campo.select();
        var listo = function () { copiar.textContent = "Copiado"; };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(campo.value).then(listo, function () { document.execCommand("copy"); listo(); });
        } else { try { document.execCommand("copy"); listo(); } catch (e) {} }
      });
      var listoBtn = document.getElementById("btnListoUsuario");
      if (listoBtn) listoBtn.addEventListener("click", function () { render(); });
      bien("Usuario creado");
    });
  }

  function quitarHtml(s) { var d = document.createElement("div"); d.innerHTML = s; return d.textContent; }

  global.PantallaUsuarios = { render: render };
})(typeof window !== "undefined" ? window : this);
