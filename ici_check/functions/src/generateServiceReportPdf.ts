import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldPath } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import * as logger from "firebase-functions/logger";
import axios from "axios";
import PDFDocument from "pdfkit";
import type { Timestamp } from "firebase-admin/firestore";

// ─── INTERFACES ────────────────────────────────────────────────────────────

interface ActivityData {
  photoUrls: string[];
  observations: string;
}

interface ReportEntry {
  instanceId: string;
  deviceIndex: number;
  customId: string;
  area: string;
  results: Record<string, string | null>;
  observations: string;
  photoUrls: string[];
  activityData: Record<string, ActivityData>;
}

interface ServiceSession {
  id: string;
  date: Timestamp;
  startTime: string;
  endTime?: string;
  technicianId?: string;
}

interface ServiceReport {
  id: string;
  policyId: string;
  dateStr: string;
  serviceDate: Timestamp;
  startTime?: string;
  endTime?: string;
  sessions?: ServiceSession[];
  assignedTechnicianIds: string[];
  entries: ReportEntry[];
  generalObservations: string;
  providerSignature?: string;
  clientSignature?: string;
  providerSignerName?: string;
  clientSignerName?: string;
  sectionAssignments: Record<string, string[]>;
}

interface Policy {
  id: string;
  clientId: string;
  devices: PolicyDevice[];
}

interface PolicyDevice {
  instanceId: string;
  definitionId: string;
  quantity: number;
  scheduleOffsets: Record<string, number>;
  excludedActivities?: string[];
  cumulativeActivities?: string[];
}

interface DeviceDefinition {
  id: string;
  name: string;
  activities: ActivityConfig[];
  viewMode?: string;
}

interface ActivityConfig {
  id: string;
  name: string;
  frequency: string;
  type: string;
}

interface Client {
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

interface UserModel {
  id: string;
  name: string;
  email: string;
}

// ─── COLORES ────────────────────────────────────────────────────────────

const PDF_COLORS = {
  black: "#000000",
  white: "#FFFFFF",
  grey50: "#FAFAFA",
  grey100: "#F5F5F5",
  grey200: "#EEEEEE",
  grey300: "#E0E0E0",
  grey400: "#BDBDBD",
  grey600: "#757575",
  grey700: "#616161",
  grey800: "#424242",
  red: "#F44336",
  orange: "#FF9800",
  green: "#4CAF50",
};

const MARGIN = 14.4;
const PAGE_HEIGHT = 792;
const PAGE_WIDTH = 612;

// ─── HELPERS ───────────────────────────────────────────────────────────────

async function downloadImage(url: string): Promise<Buffer | null> {
  if (!url) return null;
  try {
    if (url.startsWith("http")) {
      const res = await axios.get(url, {
        responseType: "arraybuffer",
        timeout: 20000,
      });
      return Buffer.from(res.data);
    }
    const b64 = url.includes("base64,") ? url.split("base64,")[1] : url;
    return Buffer.from(b64, "base64");
  } catch {
    return null;
  }
}

function instanceIdMatchesBase(entryInstanceId: string, baseInstanceId: string): boolean {
  if (entryInstanceId === baseInstanceId) return true;
  if (entryInstanceId.startsWith(`${baseInstanceId}_`)) {
    const suffix = entryInstanceId.substring(baseInstanceId.length + 1);
    return /^\d+$/.test(suffix);
  }
  return false;
}

function groupByDef(
  entries: ReportEntry[],
  policyDevices: PolicyDevice[]
): Map<string, ReportEntry[]> {
  const map = new Map<string, ReportEntry[]>();
  for (const entry of entries) {
    const pd = policyDevices.find((p) => instanceIdMatchesBase(entry.instanceId, p.instanceId));
    if (!pd) {
      logger.warn(`Entry sin PolicyDevice: ${entry.instanceId}`);
      continue;
    }
    if (!map.has(pd.definitionId)) map.set(pd.definitionId, []);
    map.get(pd.definitionId)!.push(entry);
  }

  // ★ Reordenar según el orden de devices en la póliza
  const defOrder = new Map<string, number>();
  policyDevices.forEach((d, i) => {
    if (!defOrder.has(d.definitionId)) defOrder.set(d.definitionId, i);
  });

  const sorted = new Map<string, ReportEntry[]>(
    [...map.entries()].sort((a, b) =>
      (defOrder.get(a[0]) ?? 999) - (defOrder.get(b[0]) ?? 999)
    )
  );

  return sorted;
}

function periodLabel(dateStr: string): string {
  if (dateStr === "CUMULATIVE") return "Acumulativo";
  if (dateStr.includes("W")) return `Semana ${dateStr}`;
  try {
    const [y, m] = dateStr.split("-").map(Number);
    const months = [
      "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
      "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre",
    ];
    return `${months[m - 1]} ${y}`;
  } catch {
    return dateStr;
  }
}

function getInvolvedFrequencies(
  report: ServiceReport,
  devices: DeviceDefinition[]
): string {
  const frequencies = new Set<string>();
  for (const entry of report.entries) {
    const activityIds = Object.keys(entry.results);
    for (const def of devices) {
      const acts = def.activities.filter((a) => activityIds.includes(a.id));
      for (const act of acts) {
        frequencies.add(act.frequency.split(".").pop() || act.frequency);
      }
    }
  }
  return Array.from(frequencies).join(", ");
}

function calcStats(entries: ReportEntry[]) {
  let ok = 0, nok = 0, na = 0, nr = 0;
  for (const e of entries) {
    for (const s of Object.values(e.results)) {
      if (s === "OK") ok++;
      else if (s === "NOK") nok++;
      else if (s === "NA") na++;
      else if (s === "NR") nr++;
      else if (s && s.trim() !== "") ok++; // ★ valor medido = completado
    }
  }
  return { ok, nok, na, nr };
}

// ─── HELPERS DE CLASIFICACIÓN (CORREGIDOS) ─────────────────────────────────

/**
 * Determina si un entry tiene hallazgo (al menos un resultado NOK).
 * ★ CORREGIDO: Solo evalúa actividades relevantes (filtra excluidas y acumulativas).
 *   Si no se pasan relevantActivityIds, revisa todas (backward-compatible).
 */
function hasFinding(entry: ReportEntry, relevantActivityIds?: Set<string>): boolean {
  for (const [actId, status] of Object.entries(entry.results)) {
    if (status !== "NOK") continue;
    // Si no hay filtro, cualquier NOK cuenta
    if (!relevantActivityIds) return true;
    // Si hay filtro, solo cuenta si la actividad es relevante
    if (relevantActivityIds.has(actId)) return true;
  }
  return false;
}

/**
 * ★ Verifica si un entry tiene contenido visible SOLO en actividades
 * que coinciden con el filtro (NOK o no-NOK).
 *   - onlyNok = true  → solo datos de actividades con NOK
 *   - onlyNok = false → solo datos de actividades SIN NOK
 * Revisa entry-level (observations/photoUrls) + activityData-level.
 */
function hasVisibleContentFiltered(
  entry: ReportEntry,
  onlyNok: boolean,
  relevantActivityIds?: Set<string>
): boolean {
  // Nivel activityData — filtrado por NOK o no-NOK
  if (entry.activityData) {
    for (const [actId, ad] of Object.entries(entry.activityData)) {
      if (relevantActivityIds && !relevantActivityIds.has(actId)) continue;

      const isNok = entry.results[actId] === "NOK";
      if (onlyNok && !isNok) continue;
      if (!onlyNok && isNok) continue;

      // Para comentarios: solo cuenta si hay observación (foto sola no basta)
      // Para hallazgos: cuenta con observación O foto
      if (onlyNok) {
        if (ad.observations?.trim()) return true;
        if (ad.photoUrls?.length > 0) return true;
      } else {
        if (ad.observations?.trim()) return true;
        // Fotos solas sin comentario NO cuentan para la sección de comentarios
      }
    }
  }

  // Entry-level
  if (onlyNok) {
    if (hasFinding(entry, relevantActivityIds)) {
      if (entry.observations?.trim()) return true;
      if (entry.photoUrls?.length > 0) return true;
    }
  } else {
    if (!hasFinding(entry, relevantActivityIds)) {
      // Para comentarios: observación requerida (foto sola no basta)
      if (entry.observations?.trim()) return true;
    }
  }

  return false;
}

/**
 * ★ Recolecta observaciones filtradas por actividades NOK o no-NOK.
 *   - onlyNok = true  → solo observaciones de actividades con NOK
 *   - onlyNok = false → solo observaciones de actividades SIN NOK
 */
function collectFilteredObservations(
  entry: ReportEntry,
  onlyNok: boolean,
  relevantActivityIds?: Set<string>
): string {
  const parts: string[] = [];

  // Entry-level observations: asignar según si el entry tiene NOK o no
  const entryHasNok = hasFinding(entry, relevantActivityIds);
  if (onlyNok && entryHasNok && entry.observations?.trim()) {
    parts.push(entry.observations.trim());
  }
  if (!onlyNok && !entryHasNok && entry.observations?.trim()) {
    parts.push(entry.observations.trim());
  }

  // ActivityData-level: filtrar por actividad
  if (entry.activityData) {
    for (const [actId, ad] of Object.entries(entry.activityData)) {
      if (relevantActivityIds && !relevantActivityIds.has(actId)) continue;

      const isNok = entry.results[actId] === "NOK";
      if (onlyNok && !isNok) continue;
      if (!onlyNok && isNok) continue;

      if (ad.observations?.trim()) {
        parts.push(ad.observations.trim());
      }
    }
  }

  return parts.join(" | ");
}

/**
 * ★ Recolecta fotos filtradas por actividades NOK o no-NOK.
 *   - onlyNok = true  → solo fotos de actividades con NOK (siempre incluir)
 *   - onlyNok = false → solo fotos de actividades SIN NOK,
 *     PERO solo si la actividad también tiene un comentario/observación
 */
function collectFilteredPhotoUrls(
  entry: ReportEntry,
  onlyNok: boolean,
  relevantActivityIds?: Set<string>
): string[] {
  const urls = new Set<string>();

  // Entry-level photos
  const entryHasNok = hasFinding(entry, relevantActivityIds);
  if (onlyNok && entryHasNok && entry.photoUrls) {
    // Hallazgos: siempre incluir fotos entry-level
    for (const url of entry.photoUrls) { if (url) urls.add(url); }
  }
  if (!onlyNok && !entryHasNok && entry.photoUrls) {
    // Comentarios: solo incluir fotos entry-level si hay observación entry-level
    if (entry.observations?.trim()) {
      for (const url of entry.photoUrls) { if (url) urls.add(url); }
    }
  }

  // ActivityData-level: filtrar por actividad
  if (entry.activityData) {
    for (const [actId, ad] of Object.entries(entry.activityData)) {
      if (relevantActivityIds && !relevantActivityIds.has(actId)) continue;

      const isNok = entry.results[actId] === "NOK";
      if (onlyNok && !isNok) continue;
      if (!onlyNok && isNok) continue;

      if (ad.photoUrls) {
        if (onlyNok) {
          // Hallazgos: siempre incluir fotos
          for (const url of ad.photoUrls) { if (url) urls.add(url); }
        } else {
          // Comentarios: solo incluir fotos si la actividad tiene observación
          if (ad.observations?.trim()) {
            for (const url of ad.photoUrls) { if (url) urls.add(url); }
          }
        }
      }
    }
  }

  return Array.from(urls);
}

// ─── OTROS HELPERS ─────────────────────────────────────────────────────────

function drawClippedImage(
  doc: PDFKit.PDFDocument,
  buffer: Buffer,
  x: number, y: number, w: number, h: number
) {
  doc.save();
  doc.roundedRect(x, y, w, h, 2).clip();
  try {
    doc.image(buffer, x, y, { fit: [w, h], align: "center", valign: "center" });
  } catch (e) { /* no rompe el PDF */ }
  doc.restore();
}

function addPageIfNeeded(
  doc: PDFKit.PDFDocument,
  currentY: number,
  requiredSpace: number,
  drawHeaderFn?: (d: PDFKit.PDFDocument) => number
): number {
  if (currentY + requiredSpace > PAGE_HEIGHT - MARGIN - 25) {
    doc.addPage();
    return drawHeaderFn ? drawHeaderFn(doc) : MARGIN;
  }
  return currentY;
}

function renderImage(
  doc: PDFKit.PDFDocument,
  imgCache: Map<string, Buffer | null>,
  url: string | undefined,
  x: number, y: number, w: number, h: number
): void {
  if (!url) return;
  const buf = imgCache.get(url);
  if (!buf) return;
  try {
    doc.image(buf, x, y, { fit: [w, h], align: "center", valign: "center" });
  } catch (error) {
    logger.warn(`Error renderizando imagen: ${error}`);
  }
}

function needsNewPage(
  doc: PDFKit.PDFDocument,
  currentY: number,
  requiredSpace: number
): boolean {
  return currentY + requiredSpace > PAGE_HEIGHT - MARGIN - 25;
}

function calcSessionDuration(startTime: string, endTime?: string): string {
  if (!endTime) return "En curso";
  try {
    const [sh, sm] = startTime.split(":").map(Number);
    const [eh, em] = endTime.split(":").map(Number);
    const diffMin = (eh * 60 + em) - (sh * 60 + sm);
    if (diffMin <= 0) return "";
    const h = Math.floor(diffMin / 60);
    const m = diffMin % 60;
    return h > 0 ? `${h}h ${m.toString().padStart(2, "0")}m` : `${m}m`;
  } catch {
    return "";
  }
}

function formatSessionDate(ts: Timestamp): string {
  const d = ts.toDate();
  return `${d.getDate().toString().padStart(2, "0")}/${(d.getMonth() + 1).toString().padStart(2, "0")}`;
}

// ─── HELPER: Calcular altura de una celda de actividad en vista lista ──────

interface ListActivityCell {
  entry: ReportEntry;
  entryIndex: number;
  activity: ActivityConfig;
  actData: ActivityData | undefined;
  isFirstActivityOfEntry: boolean;
  activityNumber: number;
}

function calcListCellHeight(
  doc: PDFKit.PDFDocument,
  cell: ListActivityCell,
  colWidth: number,
  photoSize: number
): number {
  const ACTIVITY_BASE_HEIGHT = 14;
  let h = ACTIVITY_BASE_HEIGHT;

  const hasPhotos = cell.actData?.photoUrls && cell.actData.photoUrls.length > 0;
  if (hasPhotos) {
    const innerW = colWidth - 6;
    const maxPhotosPerRow = Math.max(1, Math.floor(innerW / (photoSize + 3)));
    const photoRows = Math.ceil(cell.actData!.photoUrls.length / maxPhotosPerRow);
    h += photoRows * (photoSize + 3) + 2;
  }

  if (cell.actData?.observations?.trim()) {
    const obsW = colWidth - 8;
    doc.fontSize(4);
    const obsH = doc.heightOfString(cell.actData.observations, { width: obsW });
    h += Math.min(obsH + 2, 14);
  }

  return h;
}

// ─── CONSTRUCTOR DEL PDF ───────────────────────────────────────────────────

async function buildPdf(p: {
  report: ServiceReport;
  policy: Policy;
  client: Client;
  company: CompanySettings;
  devices: DeviceDefinition[];
  technicians: UserModel[];
}): Promise<Buffer> {
  const { report, policy, client, company, devices, technicians } = p;

  return new Promise(async (resolve, reject) => {
    try {
      const chunks: Buffer[] = [];
      const doc = new PDFDocument({
        margin: MARGIN,
        size: "LETTER",
        bufferPages: true,
        info: { Title: `Reporte ${client.name}`, Author: company.name },
      });

      doc.on("data", (c: Buffer) => chunks.push(c));
      doc.on("end", () => resolve(Buffer.concat(chunks)));
      doc.on("error", reject);

      // ── Pre-descarga de imágenes ──────────────────────────────────────
      const allUrls: string[] = [];
      if (company.logoUrl) allUrls.push(company.logoUrl);
      if (client.logoUrl) allUrls.push(client.logoUrl);
      if (report.providerSignature) allUrls.push(report.providerSignature);
      if (report.clientSignature) allUrls.push(report.clientSignature);

      for (const e of report.entries) {
        allUrls.push(...e.photoUrls);
        for (const ad of Object.values(e.activityData)) {
          allUrls.push(...(ad.photoUrls ?? []));
        }
      }

      const unique = [...new Set(allUrls)].filter(Boolean);
      const imgCache = new Map<string, Buffer | null>();

      for (let i = 0; i < unique.length; i += 6) {
        const batch = unique.slice(i, i + 6);
        const results = await Promise.allSettled(batch.map(downloadImage));
        batch.forEach((url, idx) => {
          imgCache.set(
            url,
            results[idx].status === "fulfilled"
              ? (results[idx] as PromiseFulfilledResult<Buffer | null>).value
              : null
          );
        });
      }

      logger.info(`✅ ${imgCache.size} imágenes listas`);

      const W = PAGE_WIDTH - MARGIN * 2;

      // ═══════════════════════════════════════════════════════════════════
      // HEADER
      // ═══════════════════════════════════════════════════════════════════
      const drawHeader = (doc: PDFKit.PDFDocument): number => {
        const startY = MARGIN;
        const HEADER_HEIGHT = 46;

        const LOGO_W = 70;
        const LOGO_H = 40;
        const LOGO_PAD = 4;

        const isCumulative = report.dateStr === "CUMULATIVE";
        const reportTitle = isCumulative ? "REPORTE ACUMULATIVO" : "REPORTE DE SERVICIO";
        const executionDate = new Intl.DateTimeFormat("es", {
          day: "2-digit", month: "short", year: "numeric",
        }).format(report.serviceDate.toDate()).toUpperCase();
        const periodLabelText = periodLabel(report.dateStr);
        const frequencies = getInvolvedFrequencies(report, devices);

        doc.fontSize(8).font("Helvetica-Bold");
        const titleW = doc.widthOfString(reportTitle);
        doc.fontSize(5).font("Helvetica-Bold");
        const subtitleW = doc.widthOfString("SISTEMA DE DETECCIÓN DE INCENDIOS");
        const boxContentW = doc.widthOfString(
          `EJECUCIÓN: ${executionDate}  |  PERIODO: ${periodLabelText.toUpperCase()}`
        ) + 16;

        const CENTER_COL_W = Math.max(titleW, subtitleW, boxContentW) + 16;
        const SIDE_COL_W = (W - CENTER_COL_W) / 2;

        doc.rect(MARGIN, startY, W, HEADER_HEIGHT).stroke(PDF_COLORS.black);

        const col2X = MARGIN + SIDE_COL_W;
        doc.moveTo(col2X, startY).lineTo(col2X, startY + HEADER_HEIGHT).stroke(PDF_COLORS.grey400);
        doc.moveTo(col2X + CENTER_COL_W, startY).lineTo(col2X + CENTER_COL_W, startY + HEADER_HEIGHT).stroke(PDF_COLORS.grey400);

        const logo1X = MARGIN + LOGO_PAD;
        const logo1Y = startY + (HEADER_HEIGHT - LOGO_H) / 2;
        renderImage(doc, imgCache, company.logoUrl, logo1X, logo1Y, LOGO_W, LOGO_H);

        const info1X = logo1X + LOGO_W + 5;
        const info1W = SIDE_COL_W - LOGO_W - LOGO_PAD - 8;
        const info1Y = startY + 5;

        doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
          .text(company.name, info1X, info1Y, { width: info1W, ellipsis: true });
        doc.fontSize(4.5).font("Helvetica").fillColor(PDF_COLORS.grey700)
          .text(company.legalName, info1X, info1Y + 8, { width: info1W, ellipsis: true });
        doc.fontSize(4).fillColor(PDF_COLORS.grey700)
          .text(company.address, info1X, info1Y + 14, { width: info1W, height: 8, ellipsis: true });
        doc.fontSize(4).font("Helvetica").fillColor(PDF_COLORS.grey600)
          .text(`${company.phone}  ${company.email || ""}`, info1X, info1Y + 22, { width: info1W, ellipsis: true });

        doc.fontSize(8).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
          .text(reportTitle, col2X, startY + 4, { width: CENTER_COL_W, align: "center" });

        doc.fontSize(5).font("Helvetica-Bold").fillColor(PDF_COLORS.grey700)
          .text("SISTEMA DE DETECCIÓN DE INCENDIOS", col2X, startY + 14, { width: CENTER_COL_W, align: "center" });

        const boxW = Math.max(boxContentW, 140);
        const boxX = col2X + (CENTER_COL_W - boxW) / 2;
        doc.rect(boxX, startY + 22, boxW, 10).fillAndStroke(PDF_COLORS.grey200, PDF_COLORS.grey400);
        doc.fontSize(5).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
          .text(
            `EJECUCIÓN: ${executionDate}  |  PERIODO: ${periodLabelText.toUpperCase()}`,
            boxX + 3, startY + 24.5,
            { width: boxW - 6, align: "center" }
          );

        doc.fontSize(4.5).font("Helvetica").fillColor(PDF_COLORS.grey600)
          .text(`Frecuencias: ${frequencies}`, col2X, startY + 36, { width: CENTER_COL_W, align: "center", ellipsis: true });

        const col3X = col2X + CENTER_COL_W;
        const logo3X = col3X + SIDE_COL_W - LOGO_W - LOGO_PAD;
        const logo3Y = startY + (HEADER_HEIGHT - LOGO_H) / 2;
        renderImage(doc, imgCache, client.logoUrl, logo3X, logo3Y, LOGO_W, LOGO_H);

        const info3W = SIDE_COL_W - LOGO_W - LOGO_PAD - 8;
        const info3X = col3X + 4;
        const info3Y = startY + 5;

        doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
          .text(client.name, info3X, info3Y, { width: info3W, align: "right", ellipsis: true });
        if (client.razonSocial) {
          doc.fontSize(4.5).font("Helvetica").fillColor(PDF_COLORS.grey700)
            .text(client.razonSocial, info3X, info3Y + 8, { width: info3W, align: "right", ellipsis: true });
        }
        doc.fontSize(4).fillColor(PDF_COLORS.grey700)
          .text(client.address, info3X, info3Y + 14, { width: info3W, height: 8, align: "right", ellipsis: true });
        doc.fontSize(4).font("Helvetica").fillColor(PDF_COLORS.grey600)
          .text(
            `Tel: ${client.contact}${client.nombreContacto ? "  " + client.nombreContacto : ""}`,
            info3X, info3Y + 22,
            { width: info3W, align: "right", ellipsis: true }
          );

        return MARGIN + HEADER_HEIGHT + 8;
      };
      let Y = drawHeader(doc);

      // ═══════════════════════════════════════════════════════════════════
      // INFO BAR — SESIONES DE TRABAJO
      // ═══════════════════════════════════════════════════════════════════

      const staffNames = report.assignedTechnicianIds
        .map((id) => technicians.find((u) => u.id === id)?.name ?? "Desconocido")
        .join(", ");

      const sd = report.serviceDate.toDate();
      const dateStrFormatted = `${sd.getDate().toString().padStart(2, "0")}/${(sd.getMonth() + 1).toString().padStart(2, "0")}/${sd.getFullYear()}`;

      const sessions = (report.sessions ?? []).filter((s) => s.startTime);
      const hasMultipleSessions = sessions.length >= 2;

      const INFO_BAR_HEIGHT = 12;

      if (!hasMultipleSessions) {
        doc.rect(MARGIN, Y, W, INFO_BAR_HEIGHT).fillAndStroke(PDF_COLORS.grey100, PDF_COLORS.grey400);

        doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.grey600)
          .text("FECHA: ", MARGIN + 4, Y + 4);
        doc.font("Helvetica").fillColor(PDF_COLORS.black)
          .text(dateStrFormatted, MARGIN + 30, Y + 4);

        doc.font("Helvetica-Bold").fillColor(PDF_COLORS.grey600)
          .text("HORARIO: ", MARGIN + 90, Y + 4);
        doc.font("Helvetica").fillColor(PDF_COLORS.black)
          .text(`${report.startTime ?? "--:--"} - ${report.endTime ?? "--:--"}`, MARGIN + 125, Y + 4);

        doc.font("Helvetica-Bold").fillColor(PDF_COLORS.black)
          .text("PERSONAL DESIGNADO: ", MARGIN + 200, Y + 4);
        doc.font("Helvetica").fillColor(PDF_COLORS.black)
          .text(staffNames || "N/A", MARGIN + 285, Y + 4, { width: W - 289, ellipsis: true });

        Y += INFO_BAR_HEIGHT;

        const NFPA_BAR_HEIGHT = 10;
        doc.rect(MARGIN, Y, W, NFPA_BAR_HEIGHT).fillAndStroke(PDF_COLORS.grey200, PDF_COLORS.grey400);
        doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
          .text("Norma de Referencia: NFPA", MARGIN + 4, Y + 3);
        Y += NFPA_BAR_HEIGHT + 8;

      } else {
        const SESSION_TITLE_H = 11;
        const SESSION_ROW_H   = 10;

        doc.rect(MARGIN, Y, W, SESSION_TITLE_H)
          .fillAndStroke(PDF_COLORS.grey800, PDF_COLORS.black);
        doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.white)
          .text("PERIODOS DE ACTIVIDAD DEL MANTENIMIENTO", MARGIN + 4, Y + 3, { width: W * 0.5 });

        const closedSessions = sessions.filter((s) => s.endTime);
        let totalMinutes = 0;
        for (const s of closedSessions) {
          if (s.endTime) {
            try {
              const [sh, sm] = s.startTime.split(":").map(Number);
              const [eh, em] = s.endTime.split(":").map(Number);
              const diff = (eh * 60 + em) - (sh * 60 + sm);
              if (diff > 0) totalMinutes += diff;
            } catch { /* ignore */ }
          }
        }
        const totalH = Math.floor(totalMinutes / 60);
        const totalM = totalMinutes % 60;
        const totalStr = totalMinutes > 0
          ? (totalH > 0 ? `${totalH}h ${totalM.toString().padStart(2, "0")}m` : `${totalM}m`)
          : "--";

        doc.fontSize(5.5).font("Helvetica").fillColor(PDF_COLORS.grey400)
          .text(
            `${sessions.length} sesión${sessions.length !== 1 ? "es" : ""}  ·  Tiempo total: ${totalStr}`,
            MARGIN + W * 0.5, Y + 3.5,
            { width: W * 0.49, align: "right" }
          );
        Y += SESSION_TITLE_H;

        const colN    = 20;
        const colDate = 44;
        const colFrom = 44;
        const colTo   = 44;
        const colDur  = W - colN - colDate - colFrom - colTo;

        doc.rect(MARGIN, Y, W, SESSION_ROW_H)
          .fillAndStroke(PDF_COLORS.grey200, PDF_COLORS.grey400);

        const drawColumnLabels = (rowY: number) => {
          let cx = MARGIN;
          doc.fontSize(5).font("Helvetica-Bold").fillColor(PDF_COLORS.grey700)
            .text("N°", cx, rowY + 3, { width: colN, align: "center" });
          cx += colN;
          doc.moveTo(cx, rowY).lineTo(cx, rowY + SESSION_ROW_H).stroke(PDF_COLORS.grey400);
          doc.text("FECHA", cx + 2, rowY + 3, { width: colDate - 4 });
          cx += colDate;
          doc.moveTo(cx, rowY).lineTo(cx, rowY + SESSION_ROW_H).stroke(PDF_COLORS.grey400);
          doc.text("INICIO", cx + 2, rowY + 3, { width: colFrom - 4, align: "center" });
          cx += colFrom;
          doc.moveTo(cx, rowY).lineTo(cx, rowY + SESSION_ROW_H).stroke(PDF_COLORS.grey400);
          doc.text("FIN", cx + 2, rowY + 3, { width: colTo - 4, align: "center" });
          cx += colTo;
          doc.moveTo(cx, rowY).lineTo(cx, rowY + SESSION_ROW_H).stroke(PDF_COLORS.grey400);
          doc.text("DURACIÓN", cx + 2, rowY + 3, { width: colDur - 4, align: "center" });
        };

        drawColumnLabels(Y);
        Y += SESSION_ROW_H;

        sessions.forEach((session, idx) => {
          const isEven = idx % 2 === 0;
          const rowBg = isEven ? PDF_COLORS.white : PDF_COLORS.grey50;

          doc.rect(MARGIN, Y, W, SESSION_ROW_H)
            .fillAndStroke(rowBg, PDF_COLORS.grey300);

          const sessionDateStr = formatSessionDate(session.date);
          const dur = calcSessionDuration(session.startTime, session.endTime);
          const isOpen = !session.endTime;

          let cx = MARGIN;
          doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.grey700)
            .text(`${idx + 1}`, cx, Y + 2.5, { width: colN, align: "center" });
          cx += colN;
          doc.moveTo(cx, Y).lineTo(cx, Y + SESSION_ROW_H).stroke(PDF_COLORS.grey300);

          doc.fontSize(6).font("Helvetica").fillColor(PDF_COLORS.black)
            .text(sessionDateStr, cx + 3, Y + 2.5, { width: colDate - 6 });
          cx += colDate;
          doc.moveTo(cx, Y).lineTo(cx, Y + SESSION_ROW_H).stroke(PDF_COLORS.grey300);

          doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text(session.startTime, cx + 2, Y + 2.5, { width: colFrom - 4, align: "center" });
          cx += colFrom;
          doc.moveTo(cx, Y).lineTo(cx, Y + SESSION_ROW_H).stroke(PDF_COLORS.grey300);

          doc.fontSize(6).font(isOpen ? "Helvetica" : "Helvetica-Bold")
            .fillColor(isOpen ? PDF_COLORS.grey400 : PDF_COLORS.black)
            .text(session.endTime ?? "--:--", cx + 2, Y + 2.5, { width: colTo - 4, align: "center" });
          cx += colTo;
          doc.moveTo(cx, Y).lineTo(cx, Y + SESSION_ROW_H).stroke(PDF_COLORS.grey300);

          doc.fontSize(6).font("Helvetica")
            .fillColor(isOpen ? PDF_COLORS.orange : PDF_COLORS.grey700)
            .text(dur, cx + 2, Y + 2.5, { width: colDur - 4, align: "center" });

          Y += SESSION_ROW_H;
        });

        const FOOT_H = 10;
        doc.rect(MARGIN, Y, W, FOOT_H)
          .fillAndStroke(PDF_COLORS.grey100, PDF_COLORS.grey400);

        doc.fontSize(5.5).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
          .text("Norma de Referencia: NFPA", MARGIN + 4, Y + 3);

        doc.fontSize(5.5).font("Helvetica-Bold").fillColor(PDF_COLORS.grey600)
          .text("PERSONAL: ", MARGIN + W * 0.45, Y + 3);
        const personalLabelW = doc.widthOfString("PERSONAL: ");
        doc.fontSize(5.5).font("Helvetica").fillColor(PDF_COLORS.black)
          .text(staffNames || "N/A", MARGIN + W * 0.45 + personalLabelW, Y + 3, {
            width: W * 0.54 - personalLabelW - 4,
            ellipsis: true,
          });

        Y += FOOT_H + 8;
      }

      // ═══════════════════════════════════════════════════════════════════
      // DISPOSITIVOS
      // ═══════════════════════════════════════════════════════════════════

      const grouped = groupByDef(report.entries, policy.devices);

      for (const [defId, entries] of grouped) {
        const def = devices.find((d) => d.id === defId);
        if (!def) continue;

        const excludedIds = new Set<string>();
        const cumulativeIds = new Set<string>();
        for (const pd of policy.devices) {
          if (pd.definitionId !== defId) continue;
          if (pd.excludedActivities) {
            for (const exId of pd.excludedActivities) excludedIds.add(exId);
          }
          if (pd.cumulativeActivities) {
            for (const cumId of pd.cumulativeActivities) cumulativeIds.add(cumId);
          }
        }

        const isCumulativeReport = report.dateStr === "CUMULATIVE";
        const scheduledIds = new Set(entries.flatMap((e) => Object.keys(e.results)));

        const relevantActivities = def.activities.filter((a) => {
          if (!scheduledIds.has(a.id)) return false;
          if (excludedIds.has(a.id)) return false;
          if (isCumulativeReport) return cumulativeIds.has(a.id);
          return !cumulativeIds.has(a.id);
        });

        if (relevantActivities.length === 0) continue;

        const SECTION_HEADER_HEIGHT = 16;
        Y = addPageIfNeeded(doc, Y, SECTION_HEADER_HEIGHT + 30, drawHeader);

        const sectionTechIds = report.sectionAssignments[defId] ?? [];
        const sectionTechNames = sectionTechIds
          .map((id) => technicians.find((u) => u.id === id)?.name ?? id)
          .join(", ");

        doc.rect(MARGIN, Y, W, SECTION_HEADER_HEIGHT).fillAndStroke(PDF_COLORS.grey800, PDF_COLORS.black);

        doc.fontSize(7).font("Helvetica-Bold").fillColor(PDF_COLORS.white);
        const deviceNameWidth = doc.widthOfString(def.name.toUpperCase());

        doc.text(`${def.name.toUpperCase()}`, MARGIN + 5, Y + 4, { continued: false });

        doc.fontSize(6).font("Helvetica").fillColor(PDF_COLORS.grey400)
          .text(`  (${entries.length} U.)`, MARGIN + 5 + deviceNameWidth + 2, Y + 4);

        doc.fontSize(5).fillColor(PDF_COLORS.white)
          .text(`RESPONSABLES: ${sectionTechNames || "General"}`, MARGIN + W - 150, Y + 5, { width: 145, align: "right" });

        Y += SECTION_HEADER_HEIGHT;

        const isListView = def.viewMode === "list";

        if (!isListView) {
          // ══════ VISTA TABLA ══════
          const MAX_ACTIVITIES_PER_TABLE = 12;
          const activityGroups: ActivityConfig[][] = [];

          for (let i = 0; i < relevantActivities.length; i += MAX_ACTIVITIES_PER_TABLE) {
            activityGroups.push(relevantActivities.slice(i, i + MAX_ACTIVITIES_PER_TABLE));
          }

          for (let groupIdx = 0; groupIdx < activityGroups.length; groupIdx++) {
            const activityGroup = activityGroups[groupIdx];
            const activityColWidth = activityGroup.length > 8 ? 25.0 : 38.0;
            const idColWidth = 50;
            const locationColWidth = W - idColWidth - (activityGroup.length * activityColWidth);
            const FREQ_LINE_HEIGHT = 8;
            const HEADER_PADDING = 4;

            let maxNameHeight = 10;
            for (const act of activityGroup) {
              doc.fontSize(4.5).font("Helvetica-Bold");
              const nameH = doc.heightOfString(act.name, { width: activityColWidth - 4 });
              if (nameH > maxNameHeight) maxNameHeight = nameH;
            }

            const TABLE_HEADER_HEIGHT = HEADER_PADDING + Math.ceil(maxNameHeight) + FREQ_LINE_HEIGHT + HEADER_PADDING;

            if (activityGroups.length > 1) {
              Y = addPageIfNeeded(doc, Y, 12);
              doc.rect(MARGIN, Y, W, 10).fillAndStroke(PDF_COLORS.grey100, PDF_COLORS.grey400);
              doc.fontSize(5).font("Helvetica-Bold").fillColor(PDF_COLORS.grey700)
                .text(`Actividades ${groupIdx * MAX_ACTIVITIES_PER_TABLE + 1} - ${Math.min((groupIdx + 1) * MAX_ACTIVITIES_PER_TABLE, relevantActivities.length)}`,
                  MARGIN + 4, Y + 3);
              Y += 12;
            }

            const drawTableHeader = (currentY: number) => {
              doc.rect(MARGIN, currentY, W, TABLE_HEADER_HEIGHT).fillAndStroke(PDF_COLORS.grey200, PDF_COLORS.black);
              let cx = MARGIN;

              const labelY = currentY + TABLE_HEADER_HEIGHT / 2 - 3;
              doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
                .text("ID", cx + 2, labelY, { width: idColWidth - 4, align: "center" });
              doc.moveTo(cx + idColWidth, currentY).lineTo(cx + idColWidth, currentY + TABLE_HEADER_HEIGHT).stroke(PDF_COLORS.black);
              cx += idColWidth;

              doc.text("UBICACIÓN", cx + 2, labelY, { width: locationColWidth - 4 });
              doc.moveTo(cx + locationColWidth, currentY).lineTo(cx + locationColWidth, currentY + TABLE_HEADER_HEIGHT).stroke(PDF_COLORS.black);
              cx += locationColWidth;

              for (const act of activityGroup) {
                const nameAreaHeight = TABLE_HEADER_HEIGHT - FREQ_LINE_HEIGHT - HEADER_PADDING * 2;
                doc.fontSize(4.5).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
                  .text(act.name, cx + 2, currentY + HEADER_PADDING, {
                    width: activityColWidth - 4,
                    height: nameAreaHeight,
                    align: "center",
                  });

                const freqFull = act.frequency.split(".").pop() || act.frequency;
                doc.fontSize(3.5).font("Helvetica").fillColor(PDF_COLORS.grey600)
                  .text(freqFull, cx + 2, currentY + TABLE_HEADER_HEIGHT - FREQ_LINE_HEIGHT - HEADER_PADDING + 2, {
                    width: activityColWidth - 4,
                    align: "center",
                    ellipsis: true,
                  });

                doc.moveTo(cx + activityColWidth, currentY).lineTo(cx + activityColWidth, currentY + TABLE_HEADER_HEIGHT).stroke(PDF_COLORS.black);
                cx += activityColWidth;
              }
            };

            if (needsNewPage(doc, Y, TABLE_HEADER_HEIGHT + 45)) {
              doc.addPage();
              Y = drawHeader(doc);
            }

            drawTableHeader(Y);
            Y += TABLE_HEADER_HEIGHT;

            for (const entry of entries) {
              const photoCount = (groupIdx === 0) ? entry.photoUrls.length : 0;
              const BASE_ROW_HEIGHT = 25;
              const PHOTO_SIZE = 70;

              let ROW_HEIGHT = BASE_ROW_HEIGHT;
              if (photoCount > 0) ROW_HEIGHT = 85;

              if (needsNewPage(doc, Y, ROW_HEIGHT)) {
                doc.addPage();
                Y = drawHeader(doc);
                drawTableHeader(Y);
                Y += TABLE_HEADER_HEIGHT;
              }

              doc.rect(MARGIN, Y, W, ROW_HEIGHT).stroke(PDF_COLORS.black);
              let cx = MARGIN;

              doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
                .text(entry.customId, cx + 2, Y + ROW_HEIGHT / 2 - 3, { width: idColWidth - 4, align: "center", ellipsis: true });
              doc.moveTo(cx + idColWidth, Y).lineTo(cx + idColWidth, Y + ROW_HEIGHT).stroke(PDF_COLORS.black);
              cx += idColWidth;

              doc.fontSize(6).font("Helvetica").fillColor(PDF_COLORS.black)
                .text(entry.area, cx + 3, Y + 3, { width: locationColWidth - 6, height: 14, ellipsis: true });

              if (photoCount > 0) {
                let px = cx + 3;
                const photoY = Y + 10;
                for (let i = 0; i < photoCount; i++) {
                  const buf = imgCache.get(entry.photoUrls[i]);
                  if (buf && px + PHOTO_SIZE < cx + locationColWidth) {
                    drawClippedImage(doc, buf, px, photoY, PHOTO_SIZE, 65);
                    px += PHOTO_SIZE + 3;
                  }
                }
              }

              doc.moveTo(cx + locationColWidth, Y).lineTo(cx + locationColWidth, Y + ROW_HEIGHT).stroke(PDF_COLORS.black);
              cx += locationColWidth;

              for (const act of activityGroup) {
                const status = entry.results[act.id];
                const cellCx = cx + activityColWidth / 2;
                const cellCy = Y + ROW_HEIGHT / 2;

                if (status === "OK") {
                  doc.circle(cellCx, cellCy, 2.5).fill(PDF_COLORS.green);
                } else if (status === "NOK") {
                  doc.fontSize(12).font("Helvetica-Bold").fillColor(PDF_COLORS.red)
                    .text("X", cx, cellCy - 6, { width: activityColWidth, align: "center" });
                } else if (status === "NA") {
                  doc.fontSize(5).font("Helvetica").fillColor(PDF_COLORS.grey600)
                    .text("N/A", cx, cellCy - 3, { width: activityColWidth, align: "center" });
                } else if (status === "NR") {
                  doc.circle(cellCx, cellCy, 2.5).fill(PDF_COLORS.orange);
                } else if (status && status.trim() !== "") {
                  doc.fontSize(5).font("Helvetica-Bold").fillColor("#2563EB")
                    .text(status, cx + 1, cellCy - 3, {
                      width: activityColWidth - 2,
                      align: "center",
                      ellipsis: true,
                    });
                }

                doc.moveTo(cx + activityColWidth, Y).lineTo(cx + activityColWidth, Y + ROW_HEIGHT).stroke(PDF_COLORS.black);
                cx += activityColWidth;
              }

              Y += ROW_HEIGHT;
            }

            Y += 6;
          }
        } else {
          // ══════════════════════════════════════════════════════════════
          // VISTA LISTA — LAYOUT DOS COLUMNAS
          // ══════════════════════════════════════════════════════════════

          const COL_GAP = 4;
          const COL_W = (W - COL_GAP) / 2;
          const ENTRY_HEADER_HEIGHT = 12;
          const PHOTO_SIZE = 48;

          for (let entryIdx = 0; entryIdx < entries.length; entryIdx++) {
            const entry = entries[entryIdx];

            const entryActivities = relevantActivities.filter((a) =>
              Object.prototype.hasOwnProperty.call(entry.results, a.id)
            );
            if (entryActivities.length === 0) continue;

            const cells: ListActivityCell[] = entryActivities.map((activity, actIdx) => ({
              entry,
              entryIndex: entryIdx,
              activity,
              actData: entry.activityData[activity.id],
              isFirstActivityOfEntry: actIdx === 0,
              activityNumber: actIdx + 1,
            }));

            interface CellPair {
              left: ListActivityCell;
              right: ListActivityCell | null;
              leftH: number;
              rightH: number;
              rowH: number;
            }

            const pairs: CellPair[] = [];
            for (let i = 0; i < cells.length; i += 2) {
              const left = cells[i];
              const right = i + 1 < cells.length ? cells[i + 1] : null;
              const leftH = calcListCellHeight(doc, left, COL_W, PHOTO_SIZE);
              const rightH = right ? calcListCellHeight(doc, right, COL_W, PHOTO_SIZE) : 0;
              pairs.push({
                left,
                right,
                leftH,
                rightH,
                rowH: Math.max(leftH, rightH),
              });
            }

            const firstRowH = pairs.length > 0 ? pairs[0].rowH : 14;

            if (needsNewPage(doc, Y, ENTRY_HEADER_HEIGHT + firstRowH + 4)) {
              doc.addPage();
              Y = drawHeader(doc);
            }

            doc.rect(MARGIN, Y, W, ENTRY_HEADER_HEIGHT)
              .fillAndStroke(PDF_COLORS.grey200, PDF_COLORS.grey300);

            doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
              .text(entry.customId, MARGIN + 4, Y + 3, { width: 60 });
            doc.fontSize(5).font("Helvetica").fillColor(PDF_COLORS.grey600)
              .text(entry.area, MARGIN + 65, Y + 3, {
                width: W - 69,
                ellipsis: true,
              });

            Y += ENTRY_HEADER_HEIGHT;

            for (let pairIdx = 0; pairIdx < pairs.length; pairIdx++) {
              const pair = pairs[pairIdx];

              if (needsNewPage(doc, Y, pair.rowH + 2)) {
                doc.addPage();
                Y = drawHeader(doc);

                doc.rect(MARGIN, Y, W, ENTRY_HEADER_HEIGHT)
                  .fillAndStroke(PDF_COLORS.grey200, PDF_COLORS.grey300);
                doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
                  .text(`${entry.customId} (cont.)`, MARGIN + 4, Y + 3, { width: 100 });
                doc.fontSize(5).font("Helvetica").fillColor(PDF_COLORS.grey600)
                  .text(entry.area, MARGIN + 105, Y + 3, { width: W - 109, ellipsis: true });
                Y += ENTRY_HEADER_HEIGHT;
              }

              const rowY = Y;

              if (pairIdx % 2 === 0) {
                doc.rect(MARGIN, rowY, W, pair.rowH).fill(PDF_COLORS.grey50);
              }

              drawListCell(doc, imgCache, pair.left, MARGIN, rowY, COL_W, pair.rowH, PHOTO_SIZE);

              doc.save();
              doc.moveTo(MARGIN + COL_W + COL_GAP / 2, rowY)
                .lineTo(MARGIN + COL_W + COL_GAP / 2, rowY + pair.rowH)
                .dash(2, { space: 2 })
                .stroke(PDF_COLORS.grey300);
              doc.restore();

              if (pair.right) {
                drawListCell(doc, imgCache, pair.right, MARGIN + COL_W + COL_GAP, rowY, COL_W, pair.rowH, PHOTO_SIZE);
              }

              doc.rect(MARGIN, rowY, W, pair.rowH).stroke(PDF_COLORS.grey300);

              Y = rowY + pair.rowH;
            }

            Y += 4;
          }

          Y += 6;
        }

        Y += 8;
      }


      // ═══════════════════════════════════════════════════════════════════════
      // ★ CLASIFICACIÓN DE ENTRIES: Comentarios vs Hallazgos
      // ★ CORREGIDO: Filtra a NIVEL DE ACTIVIDAD, no de entry completo.
      // ★ Un mismo entry puede aparecer en ambas secciones si tiene
      // ★ actividades OK con comentario Y actividades NOK con comentario.
      // ═══════════════════════════════════════════════════════════════════════

      // ── Construir set global de IDs de actividades relevantes para este reporte ──
      const allRelevantActivityIds = new Set<string>();
      const isCumulativeForClassification = report.dateStr === "CUMULATIVE";

      for (const pd of policy.devices) {
        const def = devices.find((d) => d.id === pd.definitionId);
        if (!def) continue;

        const pdExcluded = new Set(pd.excludedActivities ?? []);
        const pdCumulative = new Set(pd.cumulativeActivities ?? []);

        for (const act of def.activities) {
          if (pdExcluded.has(act.id)) continue;
          if (isCumulativeForClassification) {
            if (pdCumulative.has(act.id)) allRelevantActivityIds.add(act.id);
          } else {
            if (!pdCumulative.has(act.id)) allRelevantActivityIds.add(act.id);
          }
        }
      }

      // Entries que tienen contenido de comentarios (actividades sin NOK)
      const entriesWithComments = report.entries.filter(
        (e) => hasVisibleContentFiltered(e, false, allRelevantActivityIds)
      );
      // Entries que tienen contenido de hallazgos (actividades con NOK)
      const entriesWithFindings = report.entries.filter(
        (e) => hasVisibleContentFiltered(e, true, allRelevantActivityIds)
      );

      // ═══════════════════════════════════════════════════════════════════════
      // SECCIÓN 1: COMENTARIOS Y FOTOS (solo de actividades sin NOK)
      // ═══════════════════════════════════════════════════════════════════════

      if (entriesWithComments.length > 0) {
        Y = addPageIfNeeded(doc, Y, 60);

        doc.rect(MARGIN, Y, W, 10).fill(PDF_COLORS.grey800);
        doc.rect(MARGIN, Y, W, 10).stroke(PDF_COLORS.black);
        doc.fontSize(7).font("Helvetica-Bold").fillColor(PDF_COLORS.white)
          .text("Comentarios y Observaciones de los Dispositivos", MARGIN + 5, Y + 2);
        Y += 10;

        const COMMENT_PHOTO_SIZE = 60;
        const COMMENT_PHOTO_GAP  = 4;
        const ID_COL_W           = 60;
        const commentPhotosPerRow = Math.max(
          1,
          Math.floor((W - ID_COL_W - 8) / (COMMENT_PHOTO_SIZE + COMMENT_PHOTO_GAP))
        );

        for (const e of entriesWithComments) {
          // ★ Solo observaciones y fotos de actividades SIN NOK
          const obs = collectFilteredObservations(e, false, allRelevantActivityIds);
          // ★ FIX: Validar que el buffer sea un Buffer real con contenido
          const photos = collectFilteredPhotoUrls(e, false, allRelevantActivityIds)
            .filter((u) => {
              const buf = imgCache.get(u);
              return buf && Buffer.isBuffer(buf) && buf.length > 100;
            });

          if (!obs && photos.length === 0) continue;

          const photoRows = photos.length > 0
            ? Math.ceil(photos.length / commentPhotosPerRow)
            : 0;
          const photoBlockH = photoRows * (COMMENT_PHOTO_SIZE + COMMENT_PHOTO_GAP + 4);
          // ★ FIX: No reservar espacio de foto si no hay fotos válidas
          const ROW_H = photos.length > 0
            ? Math.max(16, 18 + photoBlockH + 6)
            : Math.max(16, 24);

          Y = addPageIfNeeded(doc, Y, ROW_H + 4, drawHeader);

          doc.rect(MARGIN, Y, ID_COL_W, ROW_H).stroke(PDF_COLORS.grey300);
          doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text(e.customId, MARGIN + 2, Y + 5, { width: ID_COL_W - 4 });

          doc.rect(MARGIN + ID_COL_W, Y, W - ID_COL_W, ROW_H).stroke(PDF_COLORS.grey300);

          const contentX = MARGIN + ID_COL_W + 4;
          const contentW = W - ID_COL_W - 8;
          let contentY   = Y + 5;

          if (obs) {
            doc.fontSize(6).font("Helvetica").fillColor(PDF_COLORS.black)
              .text(obs, contentX, contentY, { width: contentW, ellipsis: true });
          }
          contentY += 13;

          if (photos.length > 0) {
            let photoX    = contentX;
            let inRow     = 0;
            let photoRowY = contentY;

            for (const url of photos) {
              if (inRow >= commentPhotosPerRow) {
                inRow     = 0;
                photoX    = contentX;
                photoRowY += COMMENT_PHOTO_SIZE + COMMENT_PHOTO_GAP + 4;
              }
              const buf = imgCache.get(url);
              if (buf) {
                try {
                  drawClippedImage(doc, buf, photoX, photoRowY, COMMENT_PHOTO_SIZE, COMMENT_PHOTO_SIZE);
                } catch (imgErr) {
                  logger.warn(`Error renderizando foto en comentarios: ${imgErr}`);
                }
              }
              photoX += COMMENT_PHOTO_SIZE + COMMENT_PHOTO_GAP;
              inRow++;
            }
          }

          Y += ROW_H;
        }

        Y += 8;
      }

      // ═══════════════════════════════════════════════════════════════════════
      // SECCIÓN 2: HALLAZGOS (solo de actividades con NOK)
      // ═══════════════════════════════════════════════════════════════════════

      if (entriesWithFindings.length > 0) {
        Y = addPageIfNeeded(doc, Y, 60);

        doc.rect(MARGIN, Y, W, 10).fill(PDF_COLORS.red);
        doc.rect(MARGIN, Y, W, 10).stroke(PDF_COLORS.black);
        doc.fontSize(7).font("Helvetica-Bold").fillColor(PDF_COLORS.white)
          .text("Resumen de Hallazgos", MARGIN + 5, Y + 2);
        Y += 10;

        const FINDING_PHOTO_SIZE = 60;
        const FINDING_PHOTO_GAP  = 4;
        const ID_COL_W           = 60;
        const findingPhotosPerRow = Math.max(
          1,
          Math.floor((W - ID_COL_W - 8) / (FINDING_PHOTO_SIZE + FINDING_PHOTO_GAP))
        );

        for (const e of entriesWithFindings) {
          // ★ Solo observaciones y fotos de actividades CON NOK
          const obs = collectFilteredObservations(e, true, allRelevantActivityIds);
          const photos = collectFilteredPhotoUrls(e, true, allRelevantActivityIds)
            .filter((u) => {
              const buf = imgCache.get(u);
              return buf && Buffer.isBuffer(buf) && buf.length > 100;
            });

          if (!obs && photos.length === 0) continue;

          const nokActivities = Object.entries(e.results)
            .filter(([actId, status]) => status === "NOK" && allRelevantActivityIds.has(actId))
            .map(([actId]) => actId);

          const photoRows = photos.length > 0
            ? Math.ceil(photos.length / findingPhotosPerRow)
            : 0;
          const photoBlockH = photoRows * (FINDING_PHOTO_SIZE + FINDING_PHOTO_GAP + 8);

          const NOK_LINE_H = 10;
          const ROW_H = Math.max(16, 18 + NOK_LINE_H + photoBlockH + 6);

          Y = addPageIfNeeded(doc, Y, ROW_H + 4, drawHeader);

          doc.rect(MARGIN, Y, ID_COL_W, ROW_H).stroke(PDF_COLORS.grey300);
          doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text(e.customId, MARGIN + 2, Y + 5, { width: ID_COL_W - 4 });

          doc.fontSize(4).font("Helvetica-Bold").fillColor(PDF_COLORS.red)
            .text(`${nokActivities.length} FALLA${nokActivities.length > 1 ? "S" : ""}`,
              MARGIN + 2, Y + 14, { width: ID_COL_W - 4 });

          doc.rect(MARGIN + ID_COL_W, Y, W - ID_COL_W, ROW_H).stroke(PDF_COLORS.grey300);

          const contentX = MARGIN + ID_COL_W + 4;
          const contentW = W - ID_COL_W - 8;
          let contentY   = Y + 5;

          if (obs) {
            doc.fontSize(6).font("Helvetica").fillColor(PDF_COLORS.black)
              .text(obs, contentX, contentY, { width: contentW, ellipsis: true });
          } else {
            doc.fontSize(6).font("Helvetica").fillColor(PDF_COLORS.grey600)
              .text("Sin comentarios adicionales.", contentX, contentY, { width: contentW });
          }
          contentY += 13;

          if (photos.length > 0) {
            let photoX    = contentX;
            let inRow     = 0;
            let photoRowY = contentY;

            for (const url of photos) {
              if (inRow >= findingPhotosPerRow) {
                inRow     = 0;
                photoX    = contentX;
                photoRowY += FINDING_PHOTO_SIZE + FINDING_PHOTO_GAP + 8;
              }
              const buf = imgCache.get(url);
              if (buf) drawClippedImage(doc, buf, photoX, photoRowY, FINDING_PHOTO_SIZE, FINDING_PHOTO_SIZE);
              photoX += FINDING_PHOTO_SIZE + FINDING_PHOTO_GAP;
              inRow++;
            }
          }

          Y += ROW_H;
        }

        Y += 8;
      }


      // ═══════════════════════════════════════════════════════════════════
      // OBSERVACIONES Y RESUMEN
      // ═══════════════════════════════════════════════════════════════════

      Y = addPageIfNeeded(doc, Y, 60);

      const stats = calcStats(report.entries);
      const obsWidth = W * 0.65;
      const sumWidth = W * 0.3;
      const sumX = MARGIN + obsWidth + W * 0.05;
      const SUMMARY_HEIGHT = 50;

      doc.rect(MARGIN, Y, obsWidth, SUMMARY_HEIGHT).stroke(PDF_COLORS.grey400);
      doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
        .text("Observaciones Generales", MARGIN + 4, Y + 4);
      doc.moveTo(MARGIN, Y + 12).lineTo(MARGIN + obsWidth, Y + 12).stroke(PDF_COLORS.grey300);
      doc.fontSize(6).font("Helvetica").fillColor(PDF_COLORS.black)
        .text(
          report.generalObservations || "Sin observaciones generales.",
          MARGIN + 4, Y + 15,
          { width: obsWidth - 8, height: SUMMARY_HEIGHT - 19 }
        );

      doc.rect(sumX, Y, sumWidth, SUMMARY_HEIGHT).stroke(PDF_COLORS.grey400);
      doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
        .text("Resumen", sumX, Y + 4, { width: sumWidth, align: "center" });
      doc.moveTo(sumX, Y + 12).lineTo(sumX + sumWidth, Y + 12).stroke(PDF_COLORS.grey300);

      const statW = sumWidth / 3;
      const statItems = [
        { label: "OK",    value: stats.ok,  color: PDF_COLORS.green },
        { label: "FALLA", value: stats.nok, color: PDF_COLORS.red },
        { label: "N/A",   value: stats.na,  color: PDF_COLORS.grey600 },
      ];

      for (let i = 0; i < statItems.length; i++) {
        const s = statItems[i];
        const sx = sumX + i * statW;
        doc.fontSize(5).font("Helvetica-Bold").fillColor(s.color)
          .text(s.label, sx, Y + 20, { width: statW, align: "center" });
        doc.fontSize(9).fillColor(s.color)
          .text(s.value.toString(), sx, Y + 30, { width: statW, align: "center" });
      }

      Y += SUMMARY_HEIGHT + 10;

      // ═══════════════════════════════════════════════════════════════════
      // FIRMAS
      // ═══════════════════════════════════════════════════════════════════

      const SIGNATURE_HEIGHT = 70;
      Y = addPageIfNeeded(doc, Y, SIGNATURE_HEIGHT);

      const sigWidth = (W - 15) / 2;
      const sig2X = MARGIN + sigWidth + 15;

      doc.rect(MARGIN, Y, sigWidth, SIGNATURE_HEIGHT).stroke(PDF_COLORS.black);
      doc.fontSize(5).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
        .text("Nombre y Firma del Responsable (Proveedor)", MARGIN + 4, Y + 2);

      if (report.providerSignature) {
        renderImage(doc, imgCache, report.providerSignature, MARGIN + sigWidth / 2 - 30, Y + 15, 60, 30);
      }

      doc.moveTo(MARGIN + 20, Y + 55).lineTo(MARGIN + sigWidth - 20, Y + 55).stroke(PDF_COLORS.grey400);
      doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
        .text(report.providerSignerName || "", MARGIN + 20, Y + 58, {
          width: sigWidth - 40,
          align: "center",
        });

      doc.rect(sig2X, Y, sigWidth, SIGNATURE_HEIGHT).stroke(PDF_COLORS.black);
      doc.fontSize(5).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
        .text("Nombre y Firma del Responsable (Cliente)", sig2X + 4, Y + 2);

      if (report.clientSignature) {
        renderImage(doc, imgCache, report.clientSignature, sig2X + sigWidth / 2 - 30, Y + 15, 60, 30);
      }

      doc.moveTo(sig2X + 20, Y + 55).lineTo(sig2X + sigWidth - 20, Y + 55).stroke(PDF_COLORS.grey400);
      doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
        .text(report.clientSignerName || "", sig2X + 20, Y + 58, {
          width: sigWidth - 40,
          align: "center",
        });

      doc.end();
    } catch (err) {
      reject(err);
    }
  });
}

// ─── DIBUJAR UNA CELDA DE ACTIVIDAD (VISTA LISTA 2-COL) ──────────────────

function drawListCell(
  doc: PDFKit.PDFDocument,
  imgCache: Map<string, Buffer | null>,
  cell: ListActivityCell,
  x: number,
  y: number,
  colW: number,
  rowH: number,
  photoSize: number
): void {
  const innerX = x + 3;
  const innerW = colW - 6;
  let cursorY = y + 2;

  const nameW = innerW * 0.50;
  const freqW = 30;
  const statusZoneX = innerX + nameW + freqW + 4;

  doc.fontSize(5).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
    .text(`${cell.activityNumber}. ${cell.activity.name}`, innerX, cursorY, { width: nameW, ellipsis: true });

  const freqText = cell.activity.frequency.split(".").pop() || "";
  doc.fontSize(4).font("Helvetica").fillColor(PDF_COLORS.grey600)
    .text(freqText, innerX + nameW + 2, cursorY + 0.5, { width: freqW, ellipsis: true });

  const status = cell.entry.results[cell.activity.id];
  const statusCenterX = statusZoneX + 4;
  const statusCenterY = cursorY + 3;

  if (status === "OK") {
    doc.circle(statusCenterX, statusCenterY, 3).fill(PDF_COLORS.green);
  } else if (status === "NOK") {
    doc.fontSize(9).font("Helvetica-Bold").fillColor(PDF_COLORS.red)
      .text("X", statusCenterX - 6, statusCenterY - 4.5, { width: 12, align: "center" });
  } else if (status === "NA") {
    doc.fontSize(4).font("Helvetica-Bold").fillColor(PDF_COLORS.grey600)
      .text("N/A", statusCenterX - 2, cursorY + 0.5);
  } else if (status === "NR") {
    doc.circle(statusCenterX, statusCenterY, 3).fill(PDF_COLORS.orange);
  } else if (status && status.trim() !== "") {
    const valueW = innerW - nameW - freqW - 10;
    doc.rect(statusZoneX - 1, cursorY - 1, valueW + 2, 8)
      .fillAndStroke("#EFF6FF", "#BFDBFE");
    doc.fontSize(4.5).font("Helvetica-Bold").fillColor("#2563EB")
      .text(status, statusZoneX, cursorY + 0.5, {
        width: valueW,
        align: "center",
        ellipsis: true,
      });
  } else {
    doc.fontSize(4).font("Helvetica").fillColor(PDF_COLORS.grey600)
      .text("-", statusCenterX - 2, cursorY + 0.5);
  }

  cursorY += 12;

  const hasPhotos = cell.actData?.photoUrls && cell.actData.photoUrls.length > 0;
  if (hasPhotos) {
    let photoX = innerX;
    const maxPhotosPerRow = Math.max(1, Math.floor(innerW / (photoSize + 3)));
    let photosInRow = 0;

    for (const url of cell.actData!.photoUrls) {
      const buf = imgCache.get(url);
      if (!buf) continue;

      if (photosInRow >= maxPhotosPerRow) {
        photosInRow = 0;
        photoX = innerX;
        cursorY += photoSize + 3;
      }

      drawClippedImage(doc, buf, photoX, cursorY, photoSize, photoSize);
      photoX += photoSize + 3;
      photosInRow++;
    }

    cursorY += photoSize + 3;
  }

  if (cell.actData?.observations?.trim()) {
    const obsW = innerW;
    doc.fontSize(4).font("Helvetica").fillColor(PDF_COLORS.grey600)
      .text(cell.actData.observations, innerX, cursorY, {
        width: obsW,
        height: 12,
        ellipsis: true,
      });
  }
}

// ─── CLOUD FUNCTION ────────────────────────────────────────────────────────

export const generateServiceReportPdf = onCall(
  {
    timeoutSeconds: 540,
    memory: "2GiB",
    region: "us-central1",
  },
  async (request) => {
    const { data, auth } = request;

    logger.info("=== INICIO generateServiceReportPdf ===");
    logger.info("📥 Data recibida:", JSON.stringify(data));

    if (!auth) {
      logger.warn("⚠️ Llamada sin autenticación");
    }

    const { reportId, policyId, dateStr } = data;

    logger.info("📄 Parámetros extraídos:", { reportId, policyId, dateStr });

    if (!reportId && (!policyId || !dateStr)) {
      throw new HttpsError(
        "invalid-argument",
        "Proporciona reportId o (policyId + dateStr)."
      );
    }

    const db = getFirestore();
    const storage = getStorage();

    let report: ServiceReport;
    let docId: string;

    if (reportId) {
      const snap = await db.collection("reports").doc(reportId).get();
      if (!snap.exists) {
        throw new HttpsError("not-found", "Reporte no encontrado.");
      }
      docId = snap.id;
      report = { id: docId, ...snap.data() } as ServiceReport;
    } else if (policyId && dateStr) {
      const q = await db
        .collection("reports")
        .where("policyId", "==", policyId)
        .where("dateStr", "==", dateStr)
        .limit(1)
        .get();

      if (q.empty) {
        throw new HttpsError("not-found", "No existe reporte para ese periodo.");
      }
      docId = q.docs[0].id;
      report = { id: docId, ...q.docs[0].data() } as ServiceReport;
    } else {
      throw new HttpsError("invalid-argument", "Parámetros inválidos.");
    }

    const policySnap = await db.collection("policies").doc(report.policyId).get();
    if (!policySnap.exists) {
      throw new HttpsError("not-found", "Póliza no encontrada.");
    }
    const policy = { id: policySnap.id, ...policySnap.data() } as Policy;

    const clientSnap = await db.collection("clients").doc(policy.clientId).get();
    if (!clientSnap.exists) {
      throw new HttpsError("not-found", "Cliente no encontrado.");
    }
    const client = { id: clientSnap.id, ...clientSnap.data() } as Client;

    const settingsSnap = await db.collection("settings").doc("company_profile").get();
    const company = (settingsSnap.exists
      ? settingsSnap.data()
      : {
          name: "Mi Empresa",
          legalName: "",
          address: "",
          phone: "",
          email: "",
          logoUrl: "",
        }) as CompanySettings;

    const devsSnap = await db.collection("devices").get();
    const devices = devsSnap.docs.map(
      (d) => ({ id: d.id, ...d.data() } as DeviceDefinition)
    );

    const techIds = report.assignedTechnicianIds ?? [];
    const technicians: UserModel[] = [];
    for (let i = 0; i < techIds.length; i += 10) {
      const batch = techIds.slice(i, i + 10);
      const usersSnap = await db
        .collection("users")
        .where(FieldPath.documentId(), "in", batch)
        .get();
      technicians.push(
        ...usersSnap.docs.map((d) => ({ id: d.id, ...d.data() } as UserModel))
      );
    }

    const pdfBuffer = await buildPdf({
      report,
      policy,
      client,
      company,
      devices,
      technicians,
    });
    logger.info(`✅ PDF generado: ${pdfBuffer.length} bytes`);

    const bucket = storage.bucket();
    const timestamp = Date.now();
    const path = `generated_pdfs/${report.policyId}/${report.dateStr}_${timestamp}.pdf`;
    const file = bucket.file(path);

    await file.save(pdfBuffer, {
      metadata: { contentType: "application/pdf" },
      public: true,
    });

    const publicUrl = `https://storage.googleapis.com/${bucket.name}/${path}`;

    logger.info("✅ PDF guardado con URL pública");

    return {
      success: true,
      downloadUrl: publicUrl,
      sizeBytes: pdfBuffer.length,
    };
  }
);