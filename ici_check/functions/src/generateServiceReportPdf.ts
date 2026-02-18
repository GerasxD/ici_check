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

interface ServiceReport {
  id: string;
  policyId: string;
  dateStr: string;
  serviceDate: Timestamp;
  startTime?: string;
  endTime?: string;
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

// ✅ ACTUALIZADO: Cliente con nuevos campos
interface Client {
  id: string;
  name: string;
  razonSocial: string; // ← NUEVO
  nombreContacto: string; // ← NUEVO
  contact: string;
  address: string;
  logoUrl: string;
}

// ✅ ACTUALIZADO: Empresa con email
interface CompanySettings {
  name: string;
  legalName: string;
  address: string;
  phone: string;
  email: string; // ← YA ESTABA, pero lo hacemos explícito
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
const PAGE_HEIGHT = 792; // Letter size en puntos
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

// ─── HELPER: Verifica si un instanceId de entry corresponde a un PolicyDevice ───
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
    // ✅ Buscar por coincidencia de base, no exacta
    const pd = policyDevices.find((p) => instanceIdMatchesBase(entry.instanceId, p.instanceId));
    if (!pd) {
      logger.warn(`Entry sin PolicyDevice: ${entry.instanceId}`);
      continue;
    }
    if (!map.has(pd.definitionId)) map.set(pd.definitionId, []);
    map.get(pd.definitionId)!.push(entry);
  }
  return map;
}

function periodLabel(dateStr: string): string {
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
  let ok = 0;
  let nok = 0;
  let na = 0;
  let nr = 0;
  
  for (const e of entries) {
    for (const s of Object.values(e.results)) {
      if (s === "OK") ok++;
      else if (s === "NOK") nok++;
      else if (s === "NA") na++;
      else if (s === "NR") nr++;
    }
  }
  
  return { ok, nok, na, nr };
}

function drawClippedImage(
  doc: PDFKit.PDFDocument,
  buffer: Buffer,
  x: number,
  y: number,
  w: number,
  h: number
) {
  doc.save();
  doc.roundedRect(x, y, w, h, 2).clip();
  try {
    doc.image(buffer, x, y, {
      fit: [w, h],
      align: "center",
      valign: "center",
    });
  } catch (e) {
    // Si falla, no rompe el PDF
  }
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
  x: number,
  y: number,
  w: number,
  h: number
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
      // ✅ HEADER ACTUALIZADO CON TODOS LOS CAMPOS
      // ═══════════════════════════════════════════════════════════════════
      const drawHeader = (doc: PDFKit.PDFDocument): number => {
        const startY = MARGIN;
        const HEADER_HEIGHT = 80; // ← Aumentado un poco para más info
        
        doc.rect(MARGIN, startY, W, HEADER_HEIGHT).stroke(PDF_COLORS.black);

        // ── Columna 1: PROVEEDOR (con email agregado) ──
        const col1Width = W * 0.28;
        renderImage(doc, imgCache, company.logoUrl, MARGIN + 8, startY + 8, 35, 35);
        
        const infoX = MARGIN + (company.logoUrl ? 49 : 8);
        
        // Nombre empresa
        doc.fontSize(7).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text(company.name, infoX, startY + 6, { width: col1Width - (infoX - MARGIN) - 4, ellipsis: true });
        
        // Razón social
        doc.fontSize(6).font("Helvetica").fillColor(PDF_COLORS.grey700)
            .text(company.legalName, infoX, startY + 15, { width: col1Width - (infoX - MARGIN) - 4, ellipsis: true });
        
        // Dirección
        doc.fontSize(5.5).fillColor(PDF_COLORS.grey700)
            .text(company.address, infoX, startY + 24, { width: col1Width - (infoX - MARGIN) - 4, height: 14, ellipsis: true });
        
        // ✅ Email de la empresa
        doc.fontSize(5).font("Helvetica").fillColor(PDF_COLORS.grey600)
            .text(company.email || "", infoX, startY + 40, { width: col1Width - (infoX - MARGIN) - 4, ellipsis: true });
        
        // Teléfono
        doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text(company.phone, infoX, startY + 48, { width: col1Width - (infoX - MARGIN) - 4, ellipsis: true });

        doc.moveTo(MARGIN + col1Width, startY).lineTo(MARGIN + col1Width, startY + HEADER_HEIGHT).stroke(PDF_COLORS.grey400);

        // ── Columna 2: TÍTULO ──
        const col2Width = W * 0.44;
        const col2X = MARGIN + col1Width;
        
        const executionDate = new Intl.DateTimeFormat("es", { day: "2-digit", month: "short", year: "numeric" }).format(report.serviceDate.toDate()).toUpperCase();
        const periodLabelText = periodLabel(report.dateStr);

        doc.fontSize(10).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text("REPORTE DE SERVICIO", col2X, startY + 12, { width: col2Width, align: "center" });
        doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.grey700)
            .text("SISTEMA DE DETECCIÓN DE INCENDIOS", col2X, startY + 24, { width: col2Width, align: "center" });

        const boxW = 180;
        const boxX = col2X + (col2Width - boxW) / 2;
        doc.rect(boxX, startY + 38, boxW, 11).fillAndStroke(PDF_COLORS.grey200, PDF_COLORS.grey400);
        
        doc.fontSize(5.5).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text(`EJECUCIÓN: ${executionDate}  |  PERIODO: ${periodLabelText.toUpperCase()}`, boxX + 3, startY + 40.5, { width: boxW - 6, align: "center" });

        const frequencies = getInvolvedFrequencies(report, devices);
        doc.fontSize(5).font("Helvetica").fillColor(PDF_COLORS.grey600)
            .text(`Frecuencias: ${frequencies}`, col2X, startY + 56, { width: col2Width, align: "center", ellipsis: true });

        doc.moveTo(col2X + col2Width, startY).lineTo(col2X + col2Width, startY + HEADER_HEIGHT).stroke(PDF_COLORS.grey400);

        // ── Columna 3: CLIENTE (con nuevos campos) ──
        const col3Width = W * 0.28;
        const col3X = col2X + col2Width;

        // ✅ ACTUALIZADO: Mostrar nombre comercial
        doc.fontSize(7).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text(client.name, col3X + 8, startY + 6, { width: col3Width - 50, ellipsis: true });
        
        // ✅ NUEVO: Razón social del cliente
        if (client.razonSocial) {
          doc.fontSize(5.5).font("Helvetica").fillColor(PDF_COLORS.grey700)
              .text(client.razonSocial, col3X + 8, startY + 14, { width: col3Width - 50, ellipsis: true });
        }
        
        // ✅ NUEVO: Nombre de contacto
        if (client.nombreContacto) {
          doc.fontSize(5.5).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
              .text(`Contacto: ${client.nombreContacto}`, col3X + 8, startY + 22, { width: col3Width - 50, ellipsis: true });
        }
        
        // Teléfono
        doc.fontSize(5.5).font("Helvetica").fillColor(PDF_COLORS.black)
            .text(`Tel: ${client.contact}`, col3X + 8, startY + 30, { width: col3Width - 50, ellipsis: true });
        
        // Dirección
        doc.fontSize(5).fillColor(PDF_COLORS.grey700)
            .text(client.address, col3X + 8, startY + 38, { width: col3Width - 50, height: 18, ellipsis: true });

        renderImage(doc, imgCache, client.logoUrl, col3X + col3Width - 40, startY + 8, 35, 35);

        return MARGIN + HEADER_HEIGHT + 10;
      };

      // EJECUTAMOS EL PRIMER HEADER
      let Y = drawHeader(doc);
      
      // ═══════════════════════════════════════════════════════════════════
      // INFO BAR
      // ═══════════════════════════════════════════════════════════════════

      const staffNames = report.assignedTechnicianIds
        .map((id) => technicians.find((u) => u.id === id)?.name ?? "Desconocido")
        .join(", ");

      const sd = report.serviceDate.toDate();
      const dateStr = `${sd.getDate().toString().padStart(2, "0")}/${(sd.getMonth() + 1).toString().padStart(2, "0")}/${sd.getFullYear()}`;

      // ✅ Primera fila: Fecha, Horario y Personal
      const INFO_BAR_HEIGHT = 12;
      doc.rect(MARGIN, Y, W, INFO_BAR_HEIGHT).fillAndStroke(PDF_COLORS.grey100, PDF_COLORS.grey400);
      
      doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.grey600)
        .text("FECHA: ", MARGIN + 4, Y + 4);
      doc.font("Helvetica").fillColor(PDF_COLORS.black)
        .text(dateStr, MARGIN + 30, Y + 4);

      doc.font("Helvetica-Bold").fillColor(PDF_COLORS.grey600)
        .text("HORARIO: ", MARGIN + 90, Y + 4);
      doc.font("Helvetica").fillColor(PDF_COLORS.black)
        .text(`${report.startTime ?? "--:--"} - ${report.endTime ?? "--:--"}`, MARGIN + 125, Y + 4);

      doc.font("Helvetica-Bold").fillColor(PDF_COLORS.black)
        .text("PERSONAL DESIGNADO: ", MARGIN + 200, Y + 4);
      doc.font("Helvetica").fillColor(PDF_COLORS.black)
        .text(staffNames || "N/A", MARGIN + 285, Y + 4, { width: W - 289, ellipsis: true });

      Y += INFO_BAR_HEIGHT;

      // ✅ Segunda fila: NFPA
      const NFPA_BAR_HEIGHT = 10;
      doc.rect(MARGIN, Y, W, NFPA_BAR_HEIGHT).fillAndStroke(PDF_COLORS.grey200, PDF_COLORS.grey400);
      
      doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
        .text("Norma de Referencia: NFPA", MARGIN + 4, Y + 3, { 
          width: W - 8, 
          align: "center" 
        });

      Y += NFPA_BAR_HEIGHT + 8;

    /// ═══════════════════════════════════════════════════════════════════
    // DISPOSITIVOS
    // ═══════════════════════════════════════════════════════════════════

    const grouped = groupByDef(report.entries, policy.devices);

    for (const [defId, entries] of grouped) {
    const def = devices.find((d) => d.id === defId);
    if (!def) continue;

    const scheduledIds = new Set(entries.flatMap((e) => Object.keys(e.results)));
    const relevantActivities = def.activities.filter((a) => scheduledIds.has(a.id));
    
    if (relevantActivities.length === 0) continue;

    // HEADER SECCIÓN
    const SECTION_HEADER_HEIGHT = 16;
    Y = addPageIfNeeded(doc, Y, SECTION_HEADER_HEIGHT + 30, drawHeader);

    const sectionTechIds = report.sectionAssignments[defId] ?? [];
    const sectionTechNames = sectionTechIds.map((id) => technicians.find((u) => u.id === id)?.name ?? id).join(", ");

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
    // ══════ VISTA TABLA CON DIVISIÓN AUTOMÁTICA ══════
    
    const MAX_ACTIVITIES_PER_TABLE = 12;
    const activityGroups: ActivityConfig[][] = [];
    
    for (let i = 0; i < relevantActivities.length; i += MAX_ACTIVITIES_PER_TABLE) {
        activityGroups.push(relevantActivities.slice(i, i + MAX_ACTIVITIES_PER_TABLE));
    }

    for (let groupIdx = 0; groupIdx < activityGroups.length; groupIdx++) {
        const activityGroup = activityGroups[groupIdx];
        const activityColWidth = activityGroup.length > 8 ? 25.0 : 38.0;
        const idColWidth = 30;
        const locationColWidth = W - idColWidth - (activityGroup.length * activityColWidth);
        const TABLE_HEADER_HEIGHT = 20;

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
        
        doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text("ID", cx, currentY + 8, { width: idColWidth, align: "center" });
        doc.moveTo(cx + idColWidth, currentY).lineTo(cx + idColWidth, currentY + TABLE_HEADER_HEIGHT).stroke(PDF_COLORS.black);
        cx += idColWidth;

        doc.text("UBICACIÓN", cx + 2, currentY + 8, { width: locationColWidth - 4 });
        doc.moveTo(cx + locationColWidth, currentY).lineTo(cx + locationColWidth, currentY + TABLE_HEADER_HEIGHT).stroke(PDF_COLORS.black);
        cx += locationColWidth;

        for (const act of activityGroup) {
            doc.fontSize(5).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text(act.name, cx + 2, currentY + 2, { width: activityColWidth - 4, height: 12, align: "center", ellipsis: true });
            
            doc.rect(cx + 2, currentY + 14, activityColWidth - 4, 5).stroke(PDF_COLORS.grey400);
            
            doc.fontSize(4).font("Helvetica").fillColor(PDF_COLORS.black)
            .text(act.frequency.split(".").pop()!.substring(0, 1), cx + 2, currentY + 15, { width: activityColWidth - 4, align: "center" });
            
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
            .text(entry.customId, cx, Y + ROW_HEIGHT / 2 - 3, { width: idColWidth, align: "center" });
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
            } else if (status === "NA" || status === "NR") {
                doc.fontSize(5).font("Helvetica").fillColor(PDF_COLORS.grey600)
                    .text(status || "-", cx, cellCy - 3, { width: activityColWidth, align: "center" });
            }

            doc.moveTo(cx + activityColWidth, Y).lineTo(cx + activityColWidth, Y + ROW_HEIGHT).stroke(PDF_COLORS.black);
            cx += activityColWidth;
            }

            Y += ROW_HEIGHT;
        }
        
        Y += 6;
    }
    } else {
        // ══════ VISTA LISTA ══════
        const ENTRY_AREA_WIDTH = W - 8;
        const ENTRY_HEADER_HEIGHT = 14;
        const ACTIVITY_ROW_HEIGHT = 18;
        const PHOTO_SIZE = 64;

        interface ActivityRow {
        entry: ReportEntry;
        entryIndex: number;
        activity: ActivityConfig;
        actData: ActivityData | undefined;
        isFirstActivityOfEntry: boolean;
        }

        const allActivityRows: ActivityRow[] = [];
        entries.forEach((entry, entryIdx) => {
        const entryActivities = relevantActivities.filter((a) => Object.prototype.hasOwnProperty.call(entry.results, a.id));
        entryActivities.forEach((activity, actIdx) => {
            allActivityRows.push({
            entry,
            entryIndex: entryIdx,
            activity,
            actData: entry.activityData[activity.id],
            isFirstActivityOfEntry: actIdx === 0,
            });
        });
        });

        for (let rowIdx = 0; rowIdx < allActivityRows.length; rowIdx++) {
        const row = allActivityRows[rowIdx];
        const hasPhotos = row.actData?.photoUrls && row.actData.photoUrls.length > 0;
        
        let dynamicHeight = ACTIVITY_ROW_HEIGHT;

        if (hasPhotos) {
            const photos = row.actData!.photoUrls.length;
            const maxPhotosPerRow = Math.floor((ENTRY_AREA_WIDTH - 8) / (PHOTO_SIZE + 4));
            const photoRows = Math.ceil(photos / maxPhotosPerRow);
            dynamicHeight += photoRows * (PHOTO_SIZE + 6);
        }

        if (row.actData?.observations?.trim()) {
            const obsWidth = Math.min(300, ENTRY_AREA_WIDTH - 8);
            const obsHeight = doc.heightOfString(row.actData.observations, {
                width: obsWidth,
            });
            dynamicHeight += obsHeight + 4;
        }

        const rowHeight = dynamicHeight;

        if (row.isFirstActivityOfEntry) {
            if (needsNewPage(doc, Y, rowHeight + 4)) {
            doc.addPage();
            Y = drawHeader(doc);
            }

            const headerX = MARGIN + 4;
            doc.rect(MARGIN, Y, ENTRY_AREA_WIDTH, ENTRY_HEADER_HEIGHT)
            .fillAndStroke(PDF_COLORS.grey200, PDF_COLORS.grey300);

            doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text(row.entry.customId, headerX, Y + 3, { width: 60 });
            doc.fontSize(5).font("Helvetica").fillColor(PDF_COLORS.grey600)
            .text(row.entry.area, headerX + 65, Y + 3, { width: ENTRY_AREA_WIDTH - 73, align: "right", ellipsis: true });

            Y += ENTRY_HEADER_HEIGHT;
        } else {
            if (needsNewPage(doc, Y, rowHeight + 2)) {
            doc.addPage();
            Y = drawHeader(doc);

            const headerX = MARGIN + 4;
            doc.rect(MARGIN, Y, ENTRY_AREA_WIDTH, ENTRY_HEADER_HEIGHT)
                .fillAndStroke(PDF_COLORS.grey200, PDF_COLORS.grey300);

            doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
                .text(row.entry.customId, headerX, Y + 3, { width: 60 });
            doc.fontSize(5).font("Helvetica").fillColor(PDF_COLORS.grey600)
                .text(row.entry.area, headerX + 65, Y + 3, { width: ENTRY_AREA_WIDTH - 73, align: "right", ellipsis: true });

            Y += ENTRY_HEADER_HEIGHT;
            }
        }

        const rowX = MARGIN + 4;
        const rowY = Y;

        if (rowIdx % 2 === 0) {
            doc.rect(MARGIN, rowY, ENTRY_AREA_WIDTH, rowHeight).fill(PDF_COLORS.grey50);
        }

        doc.fontSize(5).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text(row.activity.name, rowX, rowY + 2, { width: 100, ellipsis: true });

        const freqText = row.activity.frequency.split(".").pop() || "";
        const freqBadgeX = rowX + 110;
        doc.rect(freqBadgeX, rowY + 2, 20, 8).stroke(PDF_COLORS.grey400);
        doc.fontSize(4).font("Helvetica").fillColor(PDF_COLORS.grey600)
            .text(freqText, freqBadgeX, rowY + 3, { width: 20, align: "center" });

        const status = row.entry.results[row.activity.id];
        let statusText = "";
        let statusColor = PDF_COLORS.grey600;
        const statusBgColor = status === "OK" ? PDF_COLORS.green : status === "NOK" ? PDF_COLORS.red : PDF_COLORS.grey300;

        doc.circle(freqBadgeX + 35, rowY + 6, 4).fill(statusBgColor);

        if (status === "OK") {
        statusColor = PDF_COLORS.green;
        statusText = "";
        } else if (status === "NOK") {
        statusColor = PDF_COLORS.red;
        statusText = "X";
        } else if (status === "NA") {
        statusColor = PDF_COLORS.grey600;
        statusText = "N/A";
        } else if (status === "NR") {
        statusColor = PDF_COLORS.grey600;
        statusText = "NR";
        } else {
        statusColor = PDF_COLORS.grey600;
        statusText = "-";
        }

        if (statusText) {
        const statusFontSize = status === "NOK" ? 10 : 5;
        doc.fontSize(statusFontSize).font("Helvetica-Bold").fillColor(statusColor)
            .text(statusText, freqBadgeX + 50, rowY + 2, { width: ENTRY_AREA_WIDTH - 160, align: "left" });
        }

        if (hasPhotos) {
            let photoY = rowY + 12;
            let photoX = rowX;
            const maxPhotosPerRow = Math.floor((ENTRY_AREA_WIDTH - 8) / (PHOTO_SIZE + 4));
            let photosDrawn = 0;

            for (const url of row.actData!.photoUrls) {
            if (photosDrawn >= maxPhotosPerRow) break;
            const buf = imgCache.get(url);
            if (buf) {
                drawClippedImage(doc, buf, photoX, photoY, PHOTO_SIZE, PHOTO_SIZE);
                photoX += PHOTO_SIZE + 4;
                photosDrawn++;
            }
            }
        }

        if (row.actData?.observations && row.actData.observations.trim()) {
            const obsY = hasPhotos ? rowY + 12 + PHOTO_SIZE + 2 : rowY + 12;
            const obsWidth = Math.min(300, ENTRY_AREA_WIDTH - 8);
            doc.fontSize(4).font("Helvetica").fillColor(PDF_COLORS.grey600)
            .text(row.actData.observations, rowX, obsY, {
                width: obsWidth,
                height: 6,
                ellipsis: true,
            });
        }

        doc.rect(MARGIN, rowY, ENTRY_AREA_WIDTH, rowHeight).stroke(PDF_COLORS.grey300);

        Y = rowY + rowHeight;
        }

        Y += 6;
    }
    Y += 8;
    }

      // ═══════════════════════════════════════════════════════════════════
      // HALLAZGOS GENERALES
      // ═══════════════════════════════════════════════════════════════════

      const entriesWithObs = report.entries.filter((e) => e.observations.trim());
      if (entriesWithObs.length > 0) {
        Y = addPageIfNeeded(doc, Y, 60);

        doc.rect(MARGIN, Y, W, 10).fill(PDF_COLORS.grey800);
        doc.rect(MARGIN, Y, W, 10).stroke(PDF_COLORS.black);
        doc.fontSize(7).font("Helvetica-Bold").fillColor(PDF_COLORS.white)
          .text("HALLAZGOS GENERALES", MARGIN + 5, Y + 2);
        Y += 10;

        for (const e of entriesWithObs) {
          Y = addPageIfNeeded(doc, Y, 16);

          doc.rect(MARGIN, Y, 60, 16).stroke(PDF_COLORS.grey300);
          doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
            .text(e.customId, MARGIN + 2, Y + 5, { width: 56 });

          doc.rect(MARGIN + 60, Y, W - 60, 16).stroke(PDF_COLORS.grey300);
          doc.fontSize(6).font("Helvetica").fillColor(PDF_COLORS.black)
            .text(e.observations, MARGIN + 62, Y + 5, { width: W - 64, ellipsis: true });

          Y += 16;
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
          MARGIN + 4,
          Y + 15,
          { width: obsWidth - 8, height: SUMMARY_HEIGHT - 19 }
        );

      doc.rect(sumX, Y, sumWidth, SUMMARY_HEIGHT).stroke(PDF_COLORS.grey400);
      doc.fontSize(6).font("Helvetica-Bold").fillColor(PDF_COLORS.black)
        .text("Resumen", sumX, Y + 4, { width: sumWidth, align: "center" });
      doc.moveTo(sumX, Y + 12).lineTo(sumX + sumWidth, Y + 12).stroke(PDF_COLORS.grey300);

      const statW = sumWidth / 3;
      const statItems = [
        { label: "OK", value: stats.ok, color: PDF_COLORS.green },
        { label: "FALLA", value: stats.nok, color: PDF_COLORS.red },
        { label: "N/A", value: stats.na, color: PDF_COLORS.grey600 },
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

    // 1. Obtener Reporte
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

    // 2. Póliza
    const policySnap = await db.collection("policies").doc(report.policyId).get();
    if (!policySnap.exists) {
      throw new HttpsError("not-found", "Póliza no encontrada.");
    }
    const policy = { id: policySnap.id, ...policySnap.data() } as Policy;

    // 3. Cliente
    const clientSnap = await db.collection("clients").doc(policy.clientId).get();
    if (!clientSnap.exists) {
      throw new HttpsError("not-found", "Cliente no encontrado.");
    }
    const client = { id: clientSnap.id, ...clientSnap.data() } as Client;

    // 4. Configuración empresa
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

    // 5. Dispositivos
    const devsSnap = await db.collection("devices").get();
    const devices = devsSnap.docs.map(
      (d) => ({ id: d.id, ...d.data() } as DeviceDefinition)
    );

    // 6. Técnicos
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

    // 7. Generar PDF
    const pdfBuffer = await buildPdf({
      report,
      policy,
      client,
      company,
      devices,
      technicians,
    });
    logger.info(`✅ PDF generado: ${pdfBuffer.length} bytes`);

    // 8. Guardar en Storage
    const bucket = storage.bucket();
    const timestamp = Date.now();
    const path = `generated_pdfs/${report.policyId}/${report.dateStr}_${timestamp}.pdf`;
    const file = bucket.file(path);

    await file.save(pdfBuffer, {
      metadata: {
        contentType: "application/pdf",
      },
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