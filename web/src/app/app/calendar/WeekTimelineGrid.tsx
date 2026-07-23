"use client";

import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { FamilyTask } from "@/lib/types";
import { toLocalDateInput } from "@/lib/date-utils";
import {
  layoutWeekTasks,
  nowLineY,
  WEEK_GRID_HEIGHT,
  WEEK_HOUR_ROW_HEIGHT,
  WEEK_HOURS_PER_DAY,
  WEEK_TIME_COLUMN_WIDTH,
} from "./week-layout";
import styles from "./WeekTimelineGrid.module.css";

interface WeekTimelineGridProps {
  weekDays: Date[];
  tasks: FamilyTask[];
  selectedDay: Date;
  onSelectDay: (day: Date) => void;
  onSelectTask: (task: FamilyTask) => void;
  onSwipeWeek: (direction: -1 | 1) => void;
  label?: string;
}

export function WeekTimelineGrid({
  weekDays,
  tasks,
  selectedDay,
  onSelectTask,
  label,
}: WeekTimelineGridProps) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const gridRef = useRef<HTMLDivElement>(null);
  const [columnWidth, setColumnWidth] = useState(0);
  const [nowY, setNowY] = useState(() => nowLineY());

  const todayKey = toLocalDateInput(new Date());
  const weekContainsToday = weekDays.some((day) => toLocalDateInput(day) === todayKey);
  const selectedKey = toLocalDateInput(selectedDay);

  const weekTimedTasks = useMemo(() => {
    const keys = new Set(weekDays.map((day) => toLocalDateInput(day)));
    return tasks.filter((task) => {
      if (task.is_all_day || !task.due_date) return false;
      return keys.has(toLocalDateInput(new Date(task.due_date)));
    });
  }, [tasks, weekDays]);

  const layoutItems = useMemo(
    () => layoutWeekTasks(weekTimedTasks, weekDays, columnWidth),
    [weekTimedTasks, weekDays, columnWidth]
  );

  const allDayByDay = useMemo(() => {
    const map = new Map<string, FamilyTask[]>();
    for (const day of weekDays) {
      map.set(toLocalDateInput(day), []);
    }
    for (const task of tasks) {
      if (!task.is_all_day || !task.due_date) continue;
      const key = toLocalDateInput(new Date(task.due_date));
      const list = map.get(key);
      if (list) list.push(task);
    }
    return map;
  }, [tasks, weekDays]);

  const hasAllDay = useMemo(
    () => Array.from(allDayByDay.values()).some((list) => list.length > 0),
    [allDayByDay]
  );

  useEffect(() => {
    const el = gridRef.current;
    if (!el) return;

    const measure = () => {
      const width = el.clientWidth;
      setColumnWidth(width > 0 ? width / 7 : 0);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, [weekDays]);

  useEffect(() => {
    if (!weekContainsToday) return;
    const tick = () => setNowY(nowLineY());
    tick();
    const id = window.setInterval(tick, 30_000);
    return () => window.clearInterval(id);
  }, [weekContainsToday]);

  useLayoutEffect(() => {
    const scroller = scrollRef.current;
    if (!scroller) return;
    const targetY = weekContainsToday
      ? Math.max(0, nowLineY() - scroller.clientHeight * 0.34)
      : layoutItems.length > 0
        ? Math.max(0, Math.min(...layoutItems.map((item) => item.y)) - 8)
        : WEEK_HOUR_ROW_HEIGHT * 8;
    scroller.scrollTop = targetY;
  }, [weekDays, weekContainsToday, layoutItems]);

  const hours = useMemo(() => Array.from({ length: WEEK_HOURS_PER_DAY }, (_, i) => i), []);

  return (
    <div className={styles.root} aria-label={label}>
      {hasAllDay ? (
        <div className={styles.allDayRow}>
          <div className={styles.allDayLabel}>All day</div>
          <div className={styles.allDayCols}>
            {weekDays.map((day) => {
              const key = toLocalDateInput(day);
              const dayTasks = allDayByDay.get(key) ?? [];
              return (
                <div key={key} className={styles.allDayCol}>
                  {dayTasks.slice(0, 2).map((task) => (
                    <button
                      key={task.id}
                      type="button"
                      className={styles.allDayChip}
                      onClick={() => onSelectTask(task)}
                    >
                      {task.title}
                    </button>
                  ))}
                  {dayTasks.length > 2 ? (
                    <span className={styles.allDayMore}>+{dayTasks.length - 2}</span>
                  ) : null}
                </div>
              );
            })}
          </div>
        </div>
      ) : null}

      <div className={styles.scroll} ref={scrollRef}>
        <div className={styles.scrollInner} style={{ height: WEEK_GRID_HEIGHT }}>
          <div className={styles.timeColumn} aria-hidden>
            {hours.map((hour) => (
              <div key={hour} className={styles.hourLabel} style={{ height: WEEK_HOUR_ROW_HEIGHT }}>
                {hour === 0 ? "" : `${String(hour).padStart(2, "0")}:00`}
              </div>
            ))}
          </div>

          <div className={styles.grid} ref={gridRef}>
            <div className={styles.gridLines} aria-hidden>
              {hours.map((hour) => (
                <div
                  key={`h-${hour}`}
                  className={styles.hLine}
                  style={{ top: hour * WEEK_HOUR_ROW_HEIGHT }}
                />
              ))}
              {weekDays.map((day, index) => (
                <div
                  key={`v-${toLocalDateInput(day)}`}
                  className={[
                    styles.vLine,
                    toLocalDateInput(day) === selectedKey ? styles.vLineSelected : "",
                  ]
                    .filter(Boolean)
                    .join(" ")}
                  style={{ left: `${(index / 7) * 100}%` }}
                />
              ))}
              <div className={styles.vLine} style={{ left: "100%" }} />
            </div>

            {layoutItems.map((item) => (
              <button
                key={item.id}
                type="button"
                className={styles.event}
                style={{
                  left: item.x,
                  top: item.y,
                  width: item.width,
                  height: item.height,
                }}
                onClick={() => onSelectTask(item.task)}
              >
                <span className={styles.eventAccent} aria-hidden />
                <span className={styles.eventTitle}>{item.task.title}</span>
              </button>
            ))}

            {weekContainsToday ? (
              <div className={styles.nowLine} style={{ top: nowY }} aria-hidden>
                <span className={styles.nowDot} />
                <span className={styles.nowRule} />
              </div>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  );
}

export const WEEK_GRID_TIME_GUTTER = WEEK_TIME_COLUMN_WIDTH;
