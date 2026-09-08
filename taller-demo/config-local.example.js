// Plantilla de configuración local para desarrollo.
//
// Copia este archivo como config-local.js (ya está en .gitignore) y pon ahí
// los valores reales SOLO en tu máquina. config-local.js NUNCA debe llegar a
// la PWA publicada: index.html lo carga de forma opcional (si no existe, la
// app sigue funcionando igual) y sw.js no lo incluye en el SHELL, así que
// tampoco queda cacheado para uso offline.
//
// Sin este archivo:
//   - el login local de TEAM (sin correo, sin red) queda deshabilitado.
//   - las acciones protegidas por código de administrador (borrar orden,
//     cotización, movimiento de caja, crédito; restaurar respaldo; "Borrar
//     todo") no se pueden confirmar.
//
// Los valores de abajo son ficticios — no son las contraseñas reales del taller.
window.ENTIMOTORS_LOCAL = {
  teamPasswords: {
    wilkin: "cambia-esta-clave",
    mecanico1: "cambia-esta-clave",
    mecanico2: "cambia-esta-clave",
    prueba: "cambia-esta-clave",
  },
  adminCode: "0000",
};
