import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import * as logger from "firebase-functions/logger";
import axios from "axios";
import PDFDocument from "pdfkit";
import sharp from "sharp";

// ─── INTERFACES ────────────────────────────────────────────────────────────

type CorrectivePdfType = "pending" | "corrected";

type AttentionLevel = "A" | "B" | "C";

type CorrectiveStatus =
  | "PENDING"
  | "IN_PROGRESS"
  | "CORRECTED_BY_ICISI"
  | "CORRECTED_BY_THIRD";

interface CorrectiveItemModel {
  id: string;
  policyId: string;
  reportId: string;
  reportDateStr: string;
  deviceInstanceId: string;
  deviceCustomId: string;
  deviceArea: string;
  deviceDefId: string;
  deviceDefName: string;
  activityId: string;
  activityName: string;
  detectionDate: Timestamp;
  problemDescription: string;
  problemPhotoUrls: string[];
  level: AttentionLevel;
  status: CorrectiveStatus;
  reportedTo?: string | null;
  estimatedCorrectionDate?: Timestamp | null;
  correctionAction: string;
  correctionPhotoUrls: string[];
  actualCorrectionDate?: Timestamp | null;
  correctedByUserId?: string | null;
  correctedByName?: string | null;
  observations: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  uniqueKey?: string;
}

interface ClientModel {
  id: string;
  name: string;
  razonSocial: string;
  nombreContacto: string;
  contact: string;
  address: string;
  logoUrl: string;
}

interface CompanySettings {
  name: string;
  legalName: string;
  address: string;
  phone: string;
  email: string;
  logoUrl: string;
}

interface PolicyModel {
  id: string;
  clientId: string;
}

// ─── PALETA DE COLORES (igual que Flutter) ────────────────────────────────

const C = {
  black:    "#000000",
  white:    "#FFFFFF",
  grey50:   "#FAFAFA",
  grey100:  "#F5F5F5",
  grey200:  "#EEEEEE",
  grey300:  "#E0E0E0",
  grey400:  "#BDBDBD",
  grey600:  "#757575",
  grey700:  "#616161",
  grey800:  "#424242",
  green:    "#4CAF50",
  amber:    "#F59E0B",
  purple:   "#8B5CF6",
  levelA:   "#EF4444",
  levelABg: "#FEE2E2",
  levelB:   "#F59E0B",
  levelBBg: "#FEF3C7",
  levelC:   "#64748B",
  levelCBg: "#F1F5F9",
};

// ─── LAYOUT ────────────────────────────────────────────────────────────────

const MARGIN       = 14.4;
const PAGE_W       = 792;   // Landscape Letter width
const PAGE_H       = 612;   // Landscape Letter height
const FOOTER_H     = 18;
const CONTENT_W    = PAGE_W - MARGIN * 2;

// ─── HELPERS ───────────────────────────────────────────────────────────────

async function downloadImage(url: string): Promise<Buffer | null> {
  if (!url || url.trim() === "") return null;
  try {
    let rawBuffer: Buffer;
    if (url.startsWith("http")) {
      const res = await axios.get(url, { responseType: "arraybuffer", timeout: 20000 });
      rawBuffer = Buffer.from(res.data);
    } else {
      const b64 = url.includes("base64,") ? url.split("base64,")[1] : url;
      rawBuffer = Buffer.from(b64, "base64");
    }
    return await sharp(rawBuffer)
      .resize({ width: 400, withoutEnlargement: true })
      .flatten({ background: { r: 255, g: 255, b: 255 } })
      .jpeg({ quality: 65, force: true })
      .toBuffer();
  } catch (e) {
    logger.warn(`[CorrectivePDF] Error descargando imagen (${url}): ${e}`);
    return null;
  }
}

async function downloadLogo(url: string): Promise<Buffer | null> {
  if (!url || url.trim() === "") return null;
  try {
    let rawBuffer: Buffer;
    if (url.startsWith("http")) {
      const res = await axios.get(url, { responseType: "arraybuffer", timeout: 20000 });
      rawBuffer = Buffer.from(res.data);
    } else {
      const b64 = url.includes("base64,") ? url.split("base64,")[1] : url;
      rawBuffer = Buffer.from(b64, "base64");
    }
    return await sharp(rawBuffer)
      .resize({ width: 200, withoutEnlargement: true })
      .png({ compressionLevel: 7 })
      .toBuffer();
  } catch (e) {
    logger.warn(`[CorrectivePDF] Error descargando logo (${url}): ${e}`);
    return null;
  }
}

function isCorrected(status: CorrectiveStatus): boolean {
  return status === "CORRECTED_BY_ICISI" || status === "CORRECTED_BY_THIRD";
}

function getLevelColor(level: AttentionLevel): string {
  if (level === "A") return C.levelA;
  if (level === "B") return C.levelB;
  return C.levelC;
}

function getLevelBgColor(level: AttentionLevel): string {
  if (level === "A") return C.levelABg;
  if (level === "B") return C.levelBBg;
  return C.levelCBg;
}

function needsNewPage(currentY: number, required: number): boolean {
  return currentY + required > PAGE_H - MARGIN - FOOTER_H - 10;
}


function formatDate(ts: Timestamp | null | undefined): string {
  if (!ts) return "-";
  const d = ts.toDate();
  return `${d.getDate().toString().padStart(2, "0")}/${(d.getMonth() + 1).toString().padStart(2, "0")}/${d.getFullYear()}`;
}

function formatMonthYear(ts: Timestamp): string {
  const d = ts.toDate();
  const months = [
    "ENERO","FEBRERO","MARZO","ABRIL","MAYO","JUNIO",
    "JULIO","AGOSTO","SEPTIEMBRE","OCTUBRE","NOVIEMBRE","DICIEMBRE",
  ];
  return `${months[d.getMonth()]} ${d.getFullYear()}`;
}

function drawClippedImage(
  doc: PDFKit.PDFDocument,
  buf: Buffer,
  x: number, y: number, w: number, h: number,
  radius = 2
): void {
  doc.save();
  doc.roundedRect(x, y, w, h, radius).clip();
  try {
    doc.image(buf, x, y, { fit: [w, h], align: "center", valign: "center" });
  } catch (_) { /* no rompe */ }
  doc.restore();
}

// ─── CONSTRUCCIÓN DEL PDF ─────────────────────────────────────────────────

async function buildCorrectivePdf(params: {
  items: CorrectiveItemModel[];
  allItems: CorrectiveItemModel[];
  client: ClientModel;
  company: CompanySettings;
  pdfType: CorrectivePdfType;
  policyId: string;
}): Promise<Buffer> {
  const { items, allItems, client, company, pdfType } = params;

  return new Promise(async (resolve, reject) => {
    try {
      // ── Pre-descarga de imágenes ──────────────────────────────────────
      const imgCache = new Map<string, Buffer | null>();

      // Logos
      if (company.logoUrl) imgCache.set(company.logoUrl, await downloadLogo(company.logoUrl));
      if (client.logoUrl)  imgCache.set(client.logoUrl,  await downloadLogo(client.logoUrl));

      // Fotos de los items — todas las fotos de cada item
      const photoUrls: string[] = [];
      for (const item of items) {
        photoUrls.push(...item.problemPhotoUrls);
        photoUrls.push(...item.correctionPhotoUrls);
      }
      const uniquePhotos = [...new Set(photoUrls)].filter(Boolean);

      // Descarga en lotes de 6 para no saturar
      for (let i = 0; i < uniquePhotos.length; i += 6) {
        const batch = uniquePhotos.slice(i, i + 6);
        const results = await Promise.allSettled(batch.map((u) => downloadImage(u)));
        batch.forEach((url, idx) => {
          imgCache.set(
            url,
            results[idx].status === "fulfilled"
              ? (results[idx] as PromiseFulfilledResult<Buffer | null>).value
              : null
          );
        });
      }
      logger.info(`[CorrectivePDF] ${imgCache.size} imágenes listas`);

      // ── Documento PDF ─────────────────────────────────────────────────
      const chunks: Buffer[] = [];
      const doc = new PDFDocument({
        margin: MARGIN,
        size: [PAGE_W, PAGE_H],  // Landscape Letter
        bufferPages: true,
        info: { Title: `Bitacora Correctivos ${client.name}`, Author: company.name },
      });

      doc.on("data", (c: Buffer) => chunks.push(c));
      doc.on("end", () => resolve(Buffer.concat(chunks)));
      doc.on("error", reject);

      // ── Estadísticas ─────────────────────────────────────────────────
      const totalCount     = allItems.length;
      const pendingCount   = allItems.filter((i) =>
        i.status === "PENDING" || i.status === "IN_PROGRESS").length;
      const correctedCount = allItems.filter((i) => isCorrected(i.status)).length;
      const levelACount    = items.filter((i) => i.level === "A").length;
      const levelBCount    = items.filter((i) => i.level === "B").length;
      const levelCCount    = items.filter((i) => i.level === "C").length;

      const now          = new Date();
      const monthYear    = allItems.length > 0
        ? formatMonthYear(allItems[0].detectionDate)
        : formatMonthYear(Timestamp.now());
      const generatedStr = `${now.getDate().toString().padStart(2,"0")}/${(now.getMonth()+1).toString().padStart(2,"0")}/${now.getFullYear()} ${now.getHours().toString().padStart(2,"0")}:${now.getMinutes().toString().padStart(2,"0")}`;

      const hasAnyPhotos = items.some(
        (i) => i.problemPhotoUrls.length > 0 || i.correctionPhotoUrls.length > 0
      );

      // ════════════════════════════════════════════════════════════════
      // HEADER (mismo diseño que el Flutter)
      // ════════════════════════════════════════════════════════════════
      const drawHeader = (d: PDFKit.PDFDocument): number => {
        const startY      = MARGIN;
        const HEADER_H    = 46;
        const LOGO_W      = 70;
        const LOGO_H      = 40;
        const LOGO_PAD    = 4;
        const SIDE_W      = 175;

        const accentColor = pdfType === "pending" ? C.amber : C.green;
        const subtitle    = pdfType === "pending"
          ? "HALLAZGOS PENDIENTES Y EN PROCESO"
          : "HALLAZGOS CORREGIDOS";

        // Borde exterior
        d.rect(MARGIN, startY, CONTENT_W, HEADER_H).stroke(C.black);

        // ── COL 1: Empresa ───────────────────────────────────────────
        const col1X = MARGIN;
        const col2X = MARGIN + SIDE_W;

        // Separador col1 | col2
        d.moveTo(col2X, startY).lineTo(col2X, startY + HEADER_H).stroke(C.grey400);

        // Logo empresa
        const companyBuf = imgCache.get(company.logoUrl);
        if (companyBuf) {
          try {
            d.image(companyBuf, col1X + LOGO_PAD, startY + (HEADER_H - LOGO_H) / 2, {
              fit: [LOGO_W, LOGO_H], align: "center", valign: "center",
            });
          } catch (_) { /* logo empresa no disponible */ }
        }

        const info1X = col1X + LOGO_PAD + LOGO_W + 5;
        const info1W = SIDE_W - LOGO_W - LOGO_PAD - 8;
        const info1Y = startY + 5;

        d.fontSize(6).font("Helvetica-Bold").fillColor(C.black)
          .text(company.name, info1X, info1Y, { width: info1W, ellipsis: true });
        if (company.legalName) {
          d.fontSize(4.5).font("Helvetica").fillColor(C.grey700)
            .text(company.legalName, info1X, info1Y + 8, { width: info1W, ellipsis: true });
        }
        if (company.address) {
          d.fontSize(4).font("Helvetica").fillColor(C.grey700)
            .text(company.address, info1X, info1Y + 14, { width: info1W, height: 8, ellipsis: true });
        }
        const contactLine = [company.phone, company.email].filter(Boolean).join("  ");
        if (contactLine) {
          d.fontSize(4).font("Helvetica").fillColor(C.grey600)
            .text(contactLine, info1X, info1Y + 22, { width: info1W, ellipsis: true });
        }

        // ── COL 2: Título central ────────────────────────────────────
        const centerW = CONTENT_W - SIDE_W * 2;
        const col3X   = col2X + centerW;

        d.moveTo(col3X, startY).lineTo(col3X, startY + HEADER_H).stroke(C.grey400);

        d.fontSize(9).font("Helvetica-Bold").fillColor(C.black)
          .text("BITACORA DE CORRECTIVOS", col2X, startY + 4, {
            width: centerW, align: "center",
          });
        d.fontSize(5.5).font("Helvetica").fillColor(C.grey600)
          .text("SISTEMA DE DETECCION DE INCENDIOS", col2X, startY + 15, {
            width: centerW, align: "center",
          });

        // Badge de tipo
        const badgeText = subtitle;
        d.fontSize(6).font("Helvetica-Bold");
        const badgeW = d.widthOfString(badgeText) + 16;
        const badgeX = col2X + (centerW - badgeW) / 2;
        d.rect(badgeX, startY + 22, badgeW, 10).fill(accentColor);
        d.fontSize(6).font("Helvetica-Bold").fillColor(C.white)
          .text(badgeText, badgeX, startY + 24.5, { width: badgeW, align: "center" });

        // Caja de periodo
        const periodText = `PERIODO: ${monthYear}  |  GENERADO: ${generatedStr}`;
        d.fontSize(5).font("Helvetica-Bold");
        const periodW = d.widthOfString(periodText) + 16;
        const periodX = col2X + (centerW - periodW) / 2;
        d.rect(periodX, startY + 35, periodW, 8).fillAndStroke(C.grey200, C.grey400);
        d.fontSize(5).font("Helvetica-Bold").fillColor(C.black)
          .text(periodText, periodX + 3, startY + 36.5, { width: periodW - 6, align: "center" });

        // ── COL 3: Cliente ───────────────────────────────────────────
        const info3W = SIDE_W - LOGO_W - LOGO_PAD - 8;
        const info3X = col3X + 4;
        const info3Y = startY + 5;

        d.fontSize(6).font("Helvetica-Bold").fillColor(C.black)
          .text(client.name, info3X, info3Y, { width: info3W, align: "right", ellipsis: true });
        if (client.razonSocial) {
          d.fontSize(4.5).font("Helvetica").fillColor(C.grey700)
            .text(client.razonSocial, info3X, info3Y + 8, { width: info3W, align: "right", ellipsis: true });
        }
        if (client.address) {
          d.fontSize(4).font("Helvetica").fillColor(C.grey700)
            .text(client.address, info3X, info3Y + 14, { width: info3W, height: 8, align: "right", ellipsis: true });
        }
        const clientContact = `Tel: ${client.contact}${client.nombreContacto ? "  " + client.nombreContacto : ""}`;
        if (client.contact) {
          d.fontSize(4).font("Helvetica").fillColor(C.grey600)
            .text(clientContact, info3X, info3Y + 22, { width: info3W, align: "right", ellipsis: true });
        }

        // Logo cliente
        const clientBuf = imgCache.get(client.logoUrl);
        if (clientBuf) {
          try {
            const logoX = col3X + SIDE_W - LOGO_W - LOGO_PAD;
            d.image(clientBuf, logoX, startY + (HEADER_H - LOGO_H) / 2, {
              fit: [LOGO_W, LOGO_H], align: "center", valign: "center",
            });
          } catch (_) { /* logo cliente no disponible */ }
        }
        const statsY = startY + HEADER_H;
        const STATS_H = 28;
        d.rect(MARGIN, statsY, CONTENT_W, STATS_H)
          .fillAndStroke(C.grey100, C.black);

        // Separador inferior
        d.rect(MARGIN, statsY + STATS_H, CONTENT_W, 0).stroke(C.black);

        // Totales
        const statStartX = MARGIN + 10;
        let sx = statStartX;

        const drawStatBox = (label: string, value: string, color: string, x: number) => {
          d.fontSize(13).font("Helvetica-Bold").fillColor(color)
            .text(value, x, statsY + 4, { width: 50, align: "center" });
          d.fontSize(4.5).font("Helvetica").fillColor(C.grey600)
            .text(label, x, statsY + 18, { width: 50, align: "center" });
        };

        drawStatBox("TOTAL",      String(totalCount),     C.grey800, sx);  sx += 60;
        drawStatBox("PENDIENTES", String(pendingCount),   C.amber,   sx);  sx += 60;
        drawStatBox("CORREGIDOS", String(correctedCount), C.green,   sx);

        // Separador
        d.moveTo(MARGIN + 200, statsY + 4).lineTo(MARGIN + 200, statsY + STATS_H - 4).stroke(C.grey300);

        // Niveles
        const drawLevelChip = (lvl: string, count: number, label: string, color: string, bgColor: string, x: number) => {
          d.rect(x, statsY + 7, 14, 14).fillAndStroke(bgColor, color);
          d.fontSize(7).font("Helvetica-Bold").fillColor(color)
            .text(lvl, x, statsY + 10, { width: 14, align: "center" });
          d.fontSize(9).font("Helvetica-Bold").fillColor(color)
            .text(String(count), x + 18, statsY + 4);
          d.fontSize(4).font("Helvetica").fillColor(C.grey600)
            .text(label, x + 18, statsY + 16);
        };

        d.fontSize(5.5).font("Helvetica-Bold").fillColor(C.grey700)
          .text("Nivel de atencion  |", MARGIN + 210, statsY + 10);

        let lx = MARGIN + 290;
        drawLevelChip("A", levelACount, "Daño potencial",    C.levelA, C.levelABg, lx); lx += 75;
        drawLevelChip("B", levelBCount, "Riesgo moderado",   C.levelB, C.levelBBg, lx); lx += 75;
        drawLevelChip("C", levelCCount, "Detalle prevencion", C.levelC, C.levelCBg, lx);

        // Norma (derecha)
        d.fontSize(5.5).font("Helvetica-Bold").fillColor(C.grey700)
          .text("Norma de Referencia: NFPA", MARGIN + CONTENT_W - 130, statsY + 10, { width: 125, align: "right" });

        return startY + HEADER_H + STATS_H + 8;
      };

      let Y = drawHeader(doc);

      // ════════════════════════════════════════════════════════════════
      // TABLA
      // ════════════════════════════════════════════════════════════════

      const PHOTO_H   = 52;
      const PHOTO_W   = 65;
      const showPhotoCols = hasAnyPhotos;

      // Anchos de columna (igual que Flutter)
      // #, NVL, Dispositivo, Problema, Accion, F.Deteccion, Cierre, Estatus, Obs, [Antes, Despues]
      const COL = {
        num:     22,
        level:   24,
        device:  75,
        problem: 0,   // flex
        action:  0,   // flex
        detDate: 52,
        closeDate: 52,
        status:  82,
        obs:     0,   // flex
        photo:   80,  // solo si hay fotos
      };

      // Calcular el ancho flex disponible
      const fixedW = COL.num + COL.level + COL.device + COL.detDate + COL.closeDate + COL.status
        + (showPhotoCols ? COL.photo * 2 : 0);
      const flexTotal = CONTENT_W - fixedW;
      // Distribución 2:2:1.4 igual que Flutter
      const flexUnit  = flexTotal / (2 + 2 + 1.4);
      const colProblem = flexUnit * 2;
      const colAction  = flexUnit * 2;
      const colObs     = flexUnit * 1.4;

      // Función para dibujar encabezado de tabla
      const TABLE_HEADER_H = 18;

      const drawTableHeader = (headerY: number) => {
        doc.rect(MARGIN, headerY, CONTENT_W, TABLE_HEADER_H).fill(C.grey800);

        const cols: Array<{ label: string; w: number }> = [
          { label: "#",                    w: COL.num },
          { label: "NVL",                  w: COL.level },
          { label: "Dispositivo / Area",   w: COL.device },
          { label: "Problema / Hallazgo",  w: colProblem },
          { label: "Accion Correctiva",    w: colAction },
          { label: "Fecha\nDeteccion",     w: COL.detDate },
          { label: "Cierre\n(Est / Real)", w: COL.closeDate },
          { label: "Estatus",              w: COL.status },
          { label: "Observaciones",        w: colObs },
          ...(showPhotoCols ? [
            { label: "Antes",   w: COL.photo },
            { label: "Despues", w: COL.photo },
          ] : []),
        ];

        let cx = MARGIN;
        for (const col of cols) {
          doc.fontSize(6.5).font("Helvetica-Bold").fillColor(C.white)
            .text(col.label, cx + 2, headerY + 4, {
              width: col.w - 4,
              align: "center",
              lineGap: 1,
            });
          if (cx + col.w < MARGIN + CONTENT_W) {
            doc.moveTo(cx + col.w, headerY).lineTo(cx + col.w, headerY + TABLE_HEADER_H).stroke(C.grey400);
          }
          cx += col.w;
        }
      };

      drawTableHeader(Y);
      Y += TABLE_HEADER_H;

      // ── Filas ─────────────────────────────────────────────────────
      for (let idx = 0; idx < items.length; idx++) {
        const item = items[idx];

        const beforeUrls = item.problemPhotoUrls;
        const afterUrls  = item.correctionPhotoUrls;

        // Filtrar solo las que se descargaron correctamente
        const beforeBufs = beforeUrls
          .map((u) => imgCache.get(u) ?? null)
          .filter((b): b is Buffer => b !== null && b.length > 100);
        const afterBufs  = afterUrls
          .map((u) => imgCache.get(u) ?? null)
          .filter((b): b is Buffer => b !== null && b.length > 100);

        const maxPhotos    = Math.max(beforeBufs.length, afterBufs.length);
        const rowHasPhotos = maxPhotos > 0;

        // ── Altura mínima por FOTOS ────────────────────────────────
        const photoRowH = (showPhotoCols && rowHasPhotos)
          ? maxPhotos * PHOTO_H + (maxPhotos - 1) * 4 + 10
          : 0;

        // ── Altura mínima por TEXTO — calculamos cada columna ──────
        // Col: Dispositivo / Area (3 líneas posibles: customId + defName + area)
        const COL_DEVICE_W = COL.device - 6;
        let deviceTextH = 8; // padding top + bottom
        if (item.deviceCustomId) {
          doc.fontSize(7).font("Helvetica-Bold");
          deviceTextH += doc.heightOfString(item.deviceCustomId, { width: COL_DEVICE_W });
        }
        if (item.deviceDefName) {
          doc.fontSize(6.5).font("Helvetica");
          deviceTextH += doc.heightOfString(item.deviceDefName, { width: COL_DEVICE_W });
        }
        if (item.deviceArea) {
          doc.fontSize(6).font("Helvetica");
          deviceTextH += doc.heightOfString(item.deviceArea, { width: COL_DEVICE_W });
        }

        // Col: Problema / Hallazgo (activityName + problemDescription)
        const COL_PROB_W = colProblem - 6;
        let problemTextH = 8;
        if (item.activityName) {
          doc.fontSize(6.5).font("Helvetica-Bold");
          problemTextH += doc.heightOfString(item.activityName.toUpperCase(), { width: COL_PROB_W });
        }
        if (item.problemDescription) {
          doc.fontSize(6.5).font("Helvetica");
          problemTextH += Math.min(
            doc.heightOfString(item.problemDescription, { width: COL_PROB_W }),
            60 // máximo ~8 líneas para no crecer indefinidamente
          );
        }

        // Col: Acción Correctiva
        const COL_ACT_W = colAction - 6;
        doc.fontSize(6.5).font(item.correctionAction ? "Helvetica" : "Helvetica-Oblique");
        const actionTextH = 8 + Math.min(
          doc.heightOfString(
            item.correctionAction || "Pendiente de definir",
            { width: COL_ACT_W }
          ),
          60
        );

        // Col: Observaciones
        const COL_OBS_W = colObs - 6;
        doc.fontSize(6).font("Helvetica");
        const obsTextH = 8 + Math.min(
          doc.heightOfString(item.observations || "-", { width: COL_OBS_W }),
          60
        );

        // ROW_H = máximo entre altura por fotos y altura por texto de cualquier columna
        const MIN_ROW_H = 28;
        const ROW_H = Math.max(
          MIN_ROW_H,
          photoRowH,
          deviceTextH,
          problemTextH,
          actionTextH,
          obsTextH
        );

        if (needsNewPage(Y, ROW_H + 4)) {
          doc.addPage();
          Y = drawHeader(doc);
          drawTableHeader(Y);
          Y += TABLE_HEADER_H;
        }

        // Fondo de fila alternado
        const rowBg = idx % 2 === 0 ? C.white : C.grey50;
        doc.rect(MARGIN, Y, CONTENT_W, ROW_H).fillAndStroke(rowBg, C.grey400);

        const lvlColor   = getLevelColor(item.level);
        const lvlBgColor = getLevelBgColor(item.level);

        // ── Columna # ──────────────────────────────────────────────
        let cx = MARGIN;
        doc.fontSize(7).font("Helvetica-Bold").fillColor(C.grey600)
          .text(String(idx + 1), cx + 2, Y + ROW_H / 2 - 4, { width: COL.num - 4, align: "center" });
        doc.moveTo(cx + COL.num, Y).lineTo(cx + COL.num, Y + ROW_H).stroke(C.grey400);
        cx += COL.num;

        // ── Columna NVL ────────────────────────────────────────────
        const badgePad = 3;
        const badgeH   = 14;
        const badgeY   = Y + (ROW_H - badgeH) / 2;
        doc.rect(cx + badgePad, badgeY, COL.level - badgePad * 2, badgeH)
          .fillAndStroke(lvlBgColor, lvlColor);
        doc.fontSize(8).font("Helvetica-Bold").fillColor(lvlColor)
          .text(item.level, cx + badgePad, badgeY + 3, {
            width: COL.level - badgePad * 2, align: "center",
          });
        doc.moveTo(cx + COL.level, Y).lineTo(cx + COL.level, Y + ROW_H).stroke(C.grey400);
        cx += COL.level;

        // ── Columna Dispositivo / Area ──────────────────────────────
        let ty = Y + 4;
        if (item.deviceCustomId) {
          doc.fontSize(7).font("Helvetica-Bold").fillColor(C.black)
            .text(item.deviceCustomId, cx + 3, ty, { width: COL.device - 6 });
          ty += doc.heightOfString(item.deviceCustomId, { width: COL.device - 6 }) + 1;
        }
        if (item.deviceDefName) {
          doc.fontSize(6.5).font("Helvetica").fillColor(C.grey700)
            .text(item.deviceDefName, cx + 3, ty, { width: COL.device - 6 });
          ty += doc.heightOfString(item.deviceDefName, { width: COL.device - 6 }) + 1;
        }
        if (item.deviceArea) {
          doc.fontSize(6).font("Helvetica").fillColor(C.grey600)
            .text(item.deviceArea, cx + 3, ty, { width: COL.device - 6 });
        }
        doc.moveTo(cx + COL.device, Y).lineTo(cx + COL.device, Y + ROW_H).stroke(C.grey400);
        cx += COL.device;

        // ── Columna Problema / Hallazgo ─────────────────────────────
        ty = Y + 4;
        if (item.activityName) {
          doc.fontSize(6.5).font("Helvetica-Bold").fillColor(C.black)
            .text(item.activityName.toUpperCase(), cx + 3, ty, { width: colProblem - 6 });
          ty += doc.heightOfString(item.activityName.toUpperCase(), { width: colProblem - 6 }) + 2;
        }
        if (item.problemDescription) {
          doc.fontSize(6.5).font("Helvetica").fillColor(C.grey700)
            .text(item.problemDescription, cx + 3, ty, {
              width: colProblem - 6,
              height: ROW_H - (ty - Y) - 4,
              ellipsis: true,
            });
        }
        doc.moveTo(cx + colProblem, Y).lineTo(cx + colProblem, Y + ROW_H).stroke(C.grey400);
        cx += colProblem;

        // ── Columna Acción Correctiva ───────────────────────────────
        const hasAction = !!item.correctionAction;
        doc.fontSize(6.5)
          .font(hasAction ? "Helvetica" : "Helvetica-Oblique")
          .fillColor(hasAction ? C.black : C.grey600)
          .text(
            hasAction ? item.correctionAction : "Pendiente de definir",
            cx + 3, Y + 4,
            { width: colAction - 6, height: ROW_H - 8, ellipsis: true }
          );
        doc.moveTo(cx + colAction, Y).lineTo(cx + colAction, Y + ROW_H).stroke(C.grey400);
        cx += colAction;

        // ── Columna Fecha Detección ─────────────────────────────────
        doc.fontSize(7).font("Helvetica-Bold").fillColor(C.black)
          .text(formatDate(item.detectionDate), cx + 2, Y + ROW_H / 2 - 4, {
            width: COL.detDate - 4, align: "center",
          });
        doc.moveTo(cx + COL.detDate, Y).lineTo(cx + COL.detDate, Y + ROW_H).stroke(C.grey400);
        cx += COL.detDate;

        // ── Columna Cierre (Est / Real) ─────────────────────────────
        const showReal = item.actualCorrectionDate != null && isCorrected(item.status);
        if (showReal) {
          doc.fontSize(4.5).font("Helvetica-Bold").fillColor(C.green)
            .text("REAL", cx + 2, Y + ROW_H / 2 - 8, { width: COL.closeDate - 4, align: "center" });
          doc.fontSize(7).font("Helvetica-Bold").fillColor(C.black)
            .text(formatDate(item.actualCorrectionDate), cx + 2, Y + ROW_H / 2 - 2, {
              width: COL.closeDate - 4, align: "center",
            });
        } else {
          doc.fontSize(4.5).font("Helvetica-Bold").fillColor(C.grey600)
            .text("ESTIMADA", cx + 2, Y + ROW_H / 2 - 8, { width: COL.closeDate - 4, align: "center" });
          doc.fontSize(7).font("Helvetica").fillColor(C.grey700)
            .text(formatDate(item.estimatedCorrectionDate), cx + 2, Y + ROW_H / 2 - 2, {
              width: COL.closeDate - 4, align: "center",
            });
        }
        doc.moveTo(cx + COL.closeDate, Y).lineTo(cx + COL.closeDate, Y + ROW_H).stroke(C.grey400);
        cx += COL.closeDate;

        // ── Columna Estatus (con dot + texto 2 líneas) ──────────────
        let dotColor: string;
        let line1: string;
        let line2: string | null = null;

        switch (item.status) {
          case "CORRECTED_BY_ICISI":
            dotColor = C.green;   line1 = "CORREGIDO"; line2 = "POR ICISI";    break;
          case "CORRECTED_BY_THIRD":
            dotColor = C.purple;  line1 = "CORREGIDO"; line2 = "POR TERCEROS"; break;
          case "IN_PROGRESS":
            dotColor = C.amber;   line1 = "EN PROCESO"; break;
          default:
            dotColor = C.grey400; line1 = "PENDIENTE";  break;
        }

        const dotR  = 3;
        const dotX  = cx + 8;
        const dotY  = Y + ROW_H / 2 - (line2 ? 5 : 3);
        const textX = dotX + dotR * 2 + 3;
        const textW = COL.status - (textX - cx) - 4;

        doc.circle(dotX, dotY + 3, dotR).fill(dotColor);
        doc.fontSize(5.5).font("Helvetica-Bold").fillColor(C.black)
          .text(line1, textX, dotY, { width: textW });
        if (line2) {
          doc.fontSize(5.5).font("Helvetica-Bold").fillColor(C.black)
            .text(line2, textX, dotY + 7, { width: textW });
        }

        doc.moveTo(cx + COL.status, Y).lineTo(cx + COL.status, Y + ROW_H).stroke(C.grey400);
        cx += COL.status;

        // ── Columna Observaciones ───────────────────────────────────
        doc.fontSize(6).font("Helvetica").fillColor(C.grey700)
          .text(
            item.observations || "-",
            cx + 3, Y + 4,
            { width: colObs - 6, height: ROW_H - 8, ellipsis: true }
          );
        doc.moveTo(cx + colObs, Y).lineTo(cx + colObs, Y + ROW_H).stroke(C.grey400);
        cx += colObs;

        // ── Columnas de fotos ───────────────────────────────────────
        if (showPhotoCols) {
          // ── Antes (todas las fotos del problema apiladas) ──────────
          if (beforeBufs.length > 0) {
            let photoY = Y + 4;
            for (const buf of beforeBufs) {
              drawClippedImage(doc, buf, cx + 4, photoY, PHOTO_W, PHOTO_H);
              photoY += PHOTO_H + 4;
            }
          } else {
            doc.fontSize(6).font("Helvetica").fillColor(C.grey400)
              .text("-", cx + 2, Y + ROW_H / 2 - 3, { width: COL.photo - 4, align: "center" });
          }
          doc.moveTo(cx + COL.photo, Y).lineTo(cx + COL.photo, Y + ROW_H).stroke(C.grey400);
          cx += COL.photo;

          // ── Después (todas las fotos de corrección apiladas) ───────
          if (afterBufs.length > 0) {
            let photoY = Y + 4;
            for (const buf of afterBufs) {
              drawClippedImage(doc, buf, cx + 4, photoY, PHOTO_W, PHOTO_H);
              photoY += PHOTO_H + 4;
            }
          } else {
            const afterLabel = isCorrected(item.status) ? "-" : "Pendiente";
            doc.fontSize(6).font("Helvetica-Oblique").fillColor(C.grey400)
              .text(afterLabel, cx + 2, Y + ROW_H / 2 - 3, { width: COL.photo - 4, align: "center" });
          }
        }

        Y += ROW_H;
      }

      // ════════════════════════════════════════════════════════════════
      // FOOTER en todas las páginas
      // ════════════════════════════════════════════════════════════════
      const totalPages = (doc as any)._pageBuffer.length;
      const FOOTER_Y   = PAGE_H - FOOTER_H - 4;

      for (let p = 0; p < totalPages; p++) {
        doc.switchToPage(p);
        doc.page.margins.bottom = 0;

        doc.rect(MARGIN, FOOTER_Y, CONTENT_W, FOOTER_H)
          .fillAndStroke(C.grey100, C.grey300);
        doc.rect(MARGIN, FOOTER_Y, CONTENT_W, 1.5).fill(C.grey800);

        doc.fontSize(6).font("Helvetica").fillColor(C.grey600)
          .text("Norma de Referencia: NFPA", MARGIN + 4, FOOTER_Y + 4);

        doc.fontSize(6.5).font("Helvetica-Bold").fillColor(C.grey600)
          .text(`Pagina ${p + 1} de ${totalPages}`, MARGIN + CONTENT_W - 80, FOOTER_Y + 4, {
            width: 75, align: "right",
          });
      }

      doc.end();
    } catch (err) {
      reject(err);
    }
  });
}

// ─── CLOUD FUNCTION ────────────────────────────────────────────────────────

export const generateCorrectiveLogPdf = onCall(
  {
    timeoutSeconds: 540,
    memory: "2GiB",
    region: "us-central1",
    cors: true,
  },
  async (request) => {
    const { data, auth } = request;
    logger.info("=== INICIO generateCorrectiveLogPdf ===", { data });

    if (!auth) {
      logger.warn("[CorrectivePDF] Llamada sin autenticación");
    }

    const { policyId, pdfType } = data as {
      policyId: string;
      pdfType: CorrectivePdfType;
    };

    if (!policyId || !pdfType) {
      throw new HttpsError("invalid-argument", "Se requiere policyId y pdfType.");
    }
    if (pdfType !== "pending" && pdfType !== "corrected") {
      throw new HttpsError("invalid-argument", "pdfType debe ser 'pending' o 'corrected'.");
    }

    const db      = getFirestore();
    const storage = getStorage();

    // ── Obtener póliza ────────────────────────────────────────────────
    const policySnap = await db.collection("policies").doc(policyId).get();
    if (!policySnap.exists) {
      throw new HttpsError("not-found", "Póliza no encontrada.");
    }
    const policy = { id: policySnap.id, ...policySnap.data() } as PolicyModel;

    // ── Obtener cliente ───────────────────────────────────────────────
    const clientSnap = await db.collection("clients").doc(policy.clientId).get();
    if (!clientSnap.exists) {
      throw new HttpsError("not-found", "Cliente no encontrado.");
    }
    const client = { id: clientSnap.id, ...clientSnap.data() } as ClientModel;

    // ── Obtener configuración de empresa ──────────────────────────────
    const settingsSnap = await db.collection("settings").doc("company_profile").get();
    const company = (settingsSnap.exists
      ? settingsSnap.data()
      : { name: "Mi Empresa", legalName: "", address: "", phone: "", email: "", logoUrl: "" }
    ) as CompanySettings;

    // ── Obtener TODOS los correctivos de la póliza ────────────────────
    const allItemsSnap = await db
      .collection("corrective_logs")
      .doc(policyId)
      .collection("items")
      .orderBy("detectionDate", "desc")
      .get();

    const allItems: CorrectiveItemModel[] = allItemsSnap.docs.map((d) => {
      const data = d.data();
      return { id: d.id, ...data } as CorrectiveItemModel;
    });

    if (allItems.length === 0) {
      throw new HttpsError("not-found", "No hay correctivos registrados para esta póliza.");
    }

    // ── Filtrar según tipo de PDF ─────────────────────────────────────
    const filteredItems = pdfType === "pending"
      ? allItems.filter((i) => i.status === "PENDING" || i.status === "IN_PROGRESS")
      : allItems.filter((i) => isCorrected(i.status));

    if (filteredItems.length === 0) {
      throw new HttpsError(
        "not-found",
        pdfType === "pending"
          ? "No hay correctivos pendientes o en proceso."
          : "No hay correctivos corregidos."
      );
    }

    logger.info(`[CorrectivePDF] ${filteredItems.length} items a renderizar (tipo: ${pdfType})`);

    // ── Generar PDF ───────────────────────────────────────────────────
    const pdfBuffer = await buildCorrectivePdf({
      items: filteredItems,
      allItems,
      client,
      company,
      pdfType,
      policyId,
    });

    logger.info(`[CorrectivePDF] PDF generado: ${pdfBuffer.length} bytes`);

    // ── Guardar en Storage con URL pública ────────────────────────────
    const bucket    = storage.bucket();
    const suffix    = pdfType === "pending" ? "Pendientes" : "Corregidos";
    const timestamp = Date.now();
    const fileName  = `Bitacora_${suffix}_${client.name.replace(/\s+/g, "_")}.pdf`;
    const filePath  = `generated_pdfs/corrective/${policyId}/${timestamp}_${fileName}`;
    const file      = bucket.file(filePath);

    await file.save(pdfBuffer, {
      metadata: { contentType: "application/pdf" },
      public: true,
    });

    const publicUrl = `https://storage.googleapis.com/${bucket.name}/${filePath}`;
    logger.info(`[CorrectivePDF] PDF guardado: ${publicUrl}`);

    return {
      success: true,
      downloadUrl: publicUrl,
      sizeBytes: pdfBuffer.length,
      itemCount: filteredItems.length,
    };
  }
);