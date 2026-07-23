import type { FamilyTask } from "@/lib/types";
import { toDate } from "@/lib/date-utils";

export const WEEK_HOUR_ROW_HEIGHT = 60;
export const WEEK_HOURS_PER_DAY = 24;
export const WEEK_GRID_HEIGHT = WEEK_HOUR_ROW_HEIGHT * WEEK_HOURS_PER_DAY;
export const WEEK_TIME_COLUMN_WIDTH = 45;
export const WEEK_COMPACT_EVENT_MIN_HEIGHT = 36;
export const WEEK_COLUMN_SPACING = 1;
export const WEEK_EVENT_INSET = 1;

export interface WeekLayoutItem {
  id: string;
  task: FamilyTask;
  x: number;
  y: number;
  width: number;
  height: number;
  dayIndex: number;
}

function fractionalHour(date: Date): number {
  return date.getHours() + date.getMinutes() / 60 + date.getSeconds() / 3600;
}

export function yOffsetForDate(date: Date): number {
  return fractionalHour(date) * WEEK_HOUR_ROW_HEIGHT;
}

export function taskEndDate(task: FamilyTask): Date | null {
  const start = toDate(task.due_date);
  if (!start) return null;
  const minutes = task.duration_minutes ?? 60;
  return new Date(start.getTime() + minutes * 60_000);
}

function isSameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

/** Pack overlapping timed tasks into lanes per day column (mirrors iOS WeekTaskLayoutEngine). */
export function layoutWeekTasks(
  tasks: FamilyTask[],
  weekDays: Date[],
  columnWidth: number
): WeekLayoutItem[] {
  if (columnWidth <= 0 || weekDays.length !== 7) return [];

  const timed = tasks.filter((task) => !task.is_all_day);
  const items: WeekLayoutItem[] = [];

  for (let dayIndex = 0; dayIndex < 7; dayIndex += 1) {
    const dayStart = weekDays[dayIndex];
    const dayEnd = new Date(dayStart);
    dayEnd.setDate(dayEnd.getDate() + 1);

    const dayTasks = timed
      .map((task) => {
        const start = toDate(task.due_date);
        if (!start || !isSameDay(start, dayStart)) return null;
        const rawEnd = taskEndDate(task) ?? new Date(start.getTime() + 60 * 60_000);
        const clippedEnd = rawEnd.getTime() < dayEnd.getTime() ? rawEnd : dayEnd;
        const startY = yOffsetForDate(start);
        let endY = yOffsetForDate(clippedEnd);
        if (endY <= startY) {
          endY = startY + WEEK_COMPACT_EVENT_MIN_HEIGHT;
        }
        return { task, startY, endY };
      })
      .filter((row): row is { task: FamilyTask; startY: number; endY: number } => row != null)
      .sort((a, b) => a.startY - b.startY);

    if (dayTasks.length === 0) continue;

    const laneEnds: number[] = [];
    const placements: { task: FamilyTask; lane: number; startY: number; endY: number }[] = [];

    for (const { task, startY, endY } of dayTasks) {
      let lane = 0;
      while (lane < laneEnds.length && laneEnds[lane] > startY + 0.5) {
        lane += 1;
      }
      if (lane === laneEnds.length) {
        laneEnds.push(endY);
      } else {
        laneEnds[lane] = Math.max(laneEnds[lane], endY);
      }
      placements.push({ task, lane, startY, endY });
    }

    const laneCount = Math.max(1, laneEnds.length);
    const laneWidth = Math.max(
      8,
      (columnWidth - WEEK_EVENT_INSET * 2) / laneCount
    );

    for (const { task, lane, startY, endY } of placements) {
      const height = Math.max(WEEK_COMPACT_EVENT_MIN_HEIGHT, endY - startY);
      const x = dayIndex * columnWidth + WEEK_EVENT_INSET + lane * laneWidth;
      items.push({
        id: task.id,
        task,
        x,
        y: startY,
        width: Math.max(6, laneWidth - WEEK_COLUMN_SPACING),
        height,
        dayIndex,
      });
    }
  }

  return items;
}

export function nowLineY(now = new Date()): number {
  return yOffsetForDate(now);
}
