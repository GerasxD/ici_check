import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

// ✅ CRITICAL: Inicializar Firebase Admin
initializeApp();

// ✅ Configuración global para Functions v2
setGlobalOptions({
  region: "us-central1",
  maxInstances: 10,
});

// ✅ Exportar la función
export { generateServiceReportPdf } from "./generateServiceReportPdf";