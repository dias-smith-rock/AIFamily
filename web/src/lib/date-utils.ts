import {
  addDays,
  addMonths,
  addWeeks,
  addYears,
  endOfDay,
  endOfMonth,
  endOfWeek,
  endOfYear,
  format,
  isSameDay,
  isWithinInterval,
  parseISO,
  startOfDay,
  startOfMonth,
  startOfWeek,
  startOfYear,
} from "date-fns";
import { enUS, zhCN, zhTW } from "date-fns/locale";
import type { AppLocale } from "@/lib/i18n";

const LOCALES = {
  en: enUS,
  "zh-Hans": zhCN,
  "zh-Hant": zhTW,
} as const;

export type ReportPeriod = "day" | "week" | "month" | "year";

export function toDate(value: string | null | undefined): Date | null {
  if (!value) return null;
  try {
    return parseISO(value);
  } catch {
    return null;
  }
}

export function isSameCalendarDay(value: string | null | undefined, day: Date): boolean {
  const date = toDate(value);
  if (!date) return false;
  return isSameDay(date, day);
}

export function formatDayLabel(day: Date, locale: AppLocale): string {
  return format(day, "EEE, MMM d", { locale: LOCALES[locale] });
}

export function formatMonthLabel(month: Date, locale: AppLocale): string {
  return format(month, "MMMM yyyy", { locale: LOCALES[locale] });
}

export function formatWeekLabel(anchor: Date, locale: AppLocale): string {
  const start = startOfWeek(anchor, { weekStartsOn: 1 });
  const end = endOfWeek(anchor, { weekStartsOn: 1 });
  const left = format(start, "MMM d", { locale: LOCALES[locale] });
  const right = format(end, "MMM d", { locale: LOCALES[locale] });
  return `${left} – ${right}`;
}

export function formatWeekdayShort(day: Date, locale: AppLocale): string {
  return format(day, "EEE", { locale: LOCALES[locale] });
}

export function formatDateTime(value: string | null | undefined, locale: AppLocale): string {
  const date = toDate(value);
  if (!date) return "—";
  return format(date, "MMM d, HH:mm", { locale: LOCALES[locale] });
}

export function formatTime(value: string | null | undefined, locale: AppLocale): string {
  const date = toDate(value);
  if (!date) return "—";
  return format(date, "HH:mm", { locale: LOCALES[locale] });
}

export function shiftDay(day: Date, delta: number): Date {
  return startOfDay(addDays(day, delta));
}

export function shiftWeek(day: Date, delta: number): Date {
  return startOfDay(addWeeks(day, delta));
}

export function todayStart(): Date {
  return startOfDay(new Date());
}

export function weekDays(anchor: Date): Date[] {
  const start = startOfWeek(anchor, { weekStartsOn: 1 });
  return Array.from({ length: 7 }, (_, i) => startOfDay(addDays(start, i)));
}

export function isBeforeToday(value: string | null | undefined): boolean {
  const date = toDate(value);
  if (!date) return false;
  return startOfDay(date) < todayStart();
}

export function isInMonth(value: string, month: Date): boolean {
  const date = toDate(value);
  if (!date) return false;
  return isWithinInterval(date, {
    start: startOfMonth(month),
    end: endOfMonth(month),
  });
}

export function periodInterval(period: ReportPeriod, anchor: Date): { start: Date; end: Date } {
  switch (period) {
    case "day":
      return { start: startOfDay(anchor), end: endOfDay(anchor) };
    case "week":
      return {
        start: startOfWeek(anchor, { weekStartsOn: 1 }),
        end: endOfWeek(anchor, { weekStartsOn: 1 }),
      };
    case "year":
      return { start: startOfYear(anchor), end: endOfYear(anchor) };
    case "month":
    default:
      return { start: startOfMonth(anchor), end: endOfMonth(anchor) };
  }
}

export function isInReportPeriod(
  value: string,
  period: ReportPeriod,
  anchor: Date
): boolean {
  const date = toDate(value);
  if (!date) return false;
  const { start, end } = periodInterval(period, anchor);
  return isWithinInterval(date, { start, end });
}

export function shiftReportAnchor(period: ReportPeriod, anchor: Date, delta: number): Date {
  switch (period) {
    case "day":
      return addDays(anchor, delta);
    case "week":
      return addWeeks(anchor, delta);
    case "year":
      return addYears(anchor, delta);
    case "month":
    default:
      return addMonths(anchor, delta);
  }
}

export function formatReportAnchor(period: ReportPeriod, anchor: Date, locale: AppLocale): string {
  switch (period) {
    case "day":
      return formatDayLabel(anchor, locale);
    case "week":
      return formatWeekLabel(anchor, locale);
    case "year":
      return format(anchor, "yyyy", { locale: LOCALES[locale] });
    case "month":
    default:
      return formatMonthLabel(anchor, locale);
  }
}

export function toLocalDateInput(day: Date): string {
  return format(day, "yyyy-MM-dd");
}

export function toLocalDateTimeInput(value: string | null | undefined): string {
  const date = toDate(value) ?? new Date();
  return format(date, "yyyy-MM-dd'T'HH:mm");
}

export function combineDateAndTime(dateStr: string, timeStr: string): string {
  return new Date(`${dateStr}T${timeStr}:00`).toISOString();
}
