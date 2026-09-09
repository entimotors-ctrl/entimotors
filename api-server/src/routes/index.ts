import { Router, type IRouter } from "express";
import healthRouter from "./health.js";
import productsRouter from "./products.js";
import projectsRouter from "./projects.js";
import videosRouter from "./videos.js";
import adminAuthRouter from "./admin-auth.js";
import rifaRouter from "./rifa.js"; // <-- Importamos la rifa
import adminUsuariosRouter from "./admin-usuarios.js";

const router: IRouter = Router();

// 🚨 Montamos la rifa PRIMERO. 
// Como este archivo ya maneja todo lo que empieza con "/api", al agregarle "/rifa", 
// la URL final perfecta será: /api/rifa/registrar
router.use("/rifa", rifaRouter);

// El resto de tus rutas originales
// Gestión del equipo del taller. Autoriza por token de Supabase, no por
// contraseña compartida: ver admin-usuarios.ts.
router.use(adminUsuariosRouter);

router.use(healthRouter);
router.use(adminAuthRouter);
router.use(productsRouter);
router.use(projectsRouter);
router.use(videosRouter);

export default router;
