"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { addMonths, format, isSameMonth, startOfMonth } from "date-fns";
import { Sheet } from "@/components/ui";
import {
  formatMonthLabel,
  monthGridCells,
  toLocalDateInput,
  todayStart,
  weekdayHeaders,
} from "@/lib/date-utils";
import type { AppLocale } from "@/lib/i18n";
import { t } from "@/lib/i18n";
import styles from "./MonthCalendarSheet.module.css";

interface MonthCalendarSheetProps {
  open: boolean;
  onClose: () => void;
  selectedDay: Date;
  onSelectDay: (day: Date) => void;
  daysWithTasks: Set<string>;
  locale: AppLocale;
}

export function MonthCalendarSheet({
  open,
  onClose,
  selectedDay,
  onSelectDay,
  daysWithTasks,
  locale,
}: MonthCalendarSheetProps) {
  const strings = t(locale);
  const [displayMonth, setDisplayMonth] = useState(() => startOfMonth(selectedDay));
  const [dragOffset, setDragOffset] = useState(0);
  const [settling, setSettling] = useState(false);

  useEffect(() => {
    if (open) {
      setDisplayMonth(startOfMonth(selectedDay));
      setDragOffset(0);
    }
  }, [open, selectedDay]);

  const headers = useMemo(() => weekdayHeaders(locale, 0), [locale]);
  const cells = useMemo(() => monthGridCells(displayMonth, 0), [displayMonth]);
  const selectedKey = toLocalDateInput(selectedDay);

  const goToday = useCallback(() => {
    const today = todayStart();
    onSelectDay(today);
    setDisplayMonth(startOfMonth(today));
  }, [onSelectDay]);

  const shiftMonth = useCallback((delta: number) => {
    setDisplayMonth((month) => startOfMonth(addMonths(month, delta)));
  }, []);

  return (
    <Sheet
      open={open}
      onClose={onClose}
      variant="dark"
      header={
        <div className={styles.header}>
          <h2 className={styles.title}>{formatMonthLabel(displayMonth, locale)}</h2>
          <div className={styles.headerActions}>
            <button type="button" className={styles.todayBtn} onClick={goToday}>
              {strings.today}
            </button>
            <button type="button" className={styles.closeBtn} aria-label={strings.cancel} onClick={onClose}>
              ×
            </button>
          </div>
        </div>
      }
    >
      <div
        className={[styles.monthPane, settling ? styles.settling : ""].filter(Boolean).join(" ")}
        style={{ transform: `translateX(${dragOffset}px)` }}
        onPointerDown={(e) => {
          if (e.button !== 0) return;
          const target = e.currentTarget;
          const startX = e.clientX;
          const startY = e.clientY;
          let axis: "h" | "v" | null = null;
          setSettling(false);
          target.setPointerCapture(e.pointerId);

          const onMove = (ev: PointerEvent) => {
            const dx = ev.clientX - startX;
            const dy = ev.clientY - startY;
            if (axis === null) {
              if (Math.abs(dx) < 24 && Math.abs(dy) < 24) return;
              axis = Math.abs(dx) > Math.abs(dy) ? "h" : "v";
            }
            if (axis !== "h") return;
            ev.preventDefault();
            setDragOffset(Math.max(-96, Math.min(96, dx * 0.55)));
          };

          const onUp = (ev: PointerEvent) => {
            const dx = ev.clientX - startX;
            target.releasePointerCapture(e.pointerId);
            target.removeEventListener("pointermove", onMove);
            target.removeEventListener("pointerup", onUp);
            target.removeEventListener("pointercancel", onUp);
            if (axis === "h" && Math.abs(dx) >= 50) {
              shiftMonth(dx > 0 ? -1 : 1);
            }
            setSettling(true);
            setDragOffset(0);
          };

          target.addEventListener("pointermove", onMove);
          target.addEventListener("pointerup", onUp);
          target.addEventListener("pointercancel", onUp);
        }}
        onTransitionEnd={() => setSettling(false)}
      >
        <div className={styles.weekdayRow}>
          {headers.map((label, index) => (
            <span key={`${label}-${index}`} className={styles.weekday}>
              {label}
            </span>
          ))}
        </div>

        <div className={styles.grid}>
          {cells.map((day, index) => {
            if (!day) {
              return <div key={`empty-${index}`} className={styles.cellEmpty} />;
            }
            const key = toLocalDateInput(day);
            const selected = key === selectedKey;
            const hasTasks = daysWithTasks.has(key);
            const inMonth = isSameMonth(day, displayMonth);
            return (
              <button
                key={key}
                type="button"
                className={[
                  styles.cell,
                  selected ? styles.cellSelected : "",
                  !inMonth ? styles.cellMuted : "",
                ]
                  .filter(Boolean)
                  .join(" ")}
                onClick={() => {
                  onSelectDay(day);
                  onClose();
                }}
              >
                <span className={styles.dayNum}>{format(day, "d")}</span>
                <span className={styles.dotSlot} aria-hidden>
                  {hasTasks ? (
                    <span className={[styles.dot, selected ? styles.dotOnSelected : ""].join(" ")} />
                  ) : null}
                </span>
              </button>
            );
          })}
        </div>
      </div>
    </Sheet>
  );
}
