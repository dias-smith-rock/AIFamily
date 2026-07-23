"use client";

import {
  ChangeEvent,
  FormEvent,
  PointerEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  deleteAttachments,
  fetchAttachments,
  maxAttachments,
  uploadTaskAttachments,
  type TaskAttachment,
} from "@/lib/api/attachments";
import {
  completeTask,
  createScheduledTask,
  deleteTask,
  fetchTasks,
  patchStatus,
  updateTask,
} from "@/lib/api/tasks";
import { fetchRoster, type RosterEntry } from "@/lib/api/members";
import {
  formatMonthLabel,
  formatTime,
  formatWeekLabel,
  formatWeekdayShort,
  isSameCalendarDay,
  shiftDay,
  shiftWeek,
  todayStart,
  toDate,
  toLocalDateInput,
  weekDays,
} from "@/lib/date-utils";
import { useHousehold } from "@/lib/household-context";
import { useShellChrome } from "@/components/AppShell";
import { t } from "@/lib/i18n";
import type { FamilyTask, TaskStatus } from "@/lib/types";
import { Button, Empty, Input, Sheet, Spinner, TextArea } from "@/components/ui";
import { format } from "date-fns";
import { MonthCalendarSheet } from "./MonthCalendarSheet";
import { WeekTimelineGrid } from "./WeekTimelineGrid";
import { CreateEventSheet, type CreateEventValues, reminderOffsetsFromKey } from "./CreateEventSheet";
import styles from "./calendar.module.css";

type ViewMode = "day" | "week";
const LONG_IDLE_MS = 60 * 60 * 1000;
const SWIPE_MIN_DISTANCE = 24;
const SWIPE_COMMIT_DISTANCE = 50;
const SWIPE_MAX_OFFSET = 96;

type SwipeAxis = "h" | "v" | null;

interface SwipeDragState {
  pointerId: number | null;
  startX: number;
  startY: number;
  axis: SwipeAxis;
}

function useHorizontalSwipe(onSwipe: (direction: -1 | 1) => void, enabled = true) {
  const [offset, setOffset] = useState(0);
  const [settling, setSettling] = useState(false);
  const drag = useRef<SwipeDragState>({
    pointerId: null,
    startX: 0,
    startY: 0,
    axis: null,
  });

  const resetOffset = useCallback(() => {
    setSettling(true);
    setOffset(0);
  }, []);

  const onPointerDown = useCallback(
    (e: PointerEvent<HTMLElement>) => {
      if (!enabled || e.button !== 0) return;
      // Delay capture so child buttons (week-day taps) still receive click.
      drag.current = {
        pointerId: e.pointerId,
        startX: e.clientX,
        startY: e.clientY,
        axis: null,
      };
      setSettling(false);
    },
    [enabled]
  );

  const onPointerMove = useCallback(
    (e: PointerEvent<HTMLElement>) => {
      if (!enabled || drag.current.pointerId !== e.pointerId) return;
      const dx = e.clientX - drag.current.startX;
      const dy = e.clientY - drag.current.startY;

      if (drag.current.axis === null) {
        if (Math.abs(dx) < SWIPE_MIN_DISTANCE && Math.abs(dy) < SWIPE_MIN_DISTANCE) return;
        const nextAxis = Math.abs(dx) > Math.abs(dy) ? "h" : "v";
        drag.current.axis = nextAxis;
        if (nextAxis === "v") {
          drag.current.pointerId = null;
          setOffset(0);
          return;
        }
        e.currentTarget.setPointerCapture(e.pointerId);
      }
      if (drag.current.axis !== "h") return;

      e.preventDefault();
      const damped = dx * 0.55;
      setOffset(Math.max(-SWIPE_MAX_OFFSET, Math.min(SWIPE_MAX_OFFSET, damped)));
    },
    [enabled]
  );

  const finishPointer = useCallback(
    (e: PointerEvent<HTMLElement>) => {
      if (!enabled || drag.current.pointerId !== e.pointerId) return;
      const dx = e.clientX - drag.current.startX;
      const axis = drag.current.axis;
      drag.current.pointerId = null;
      drag.current.axis = null;

      if (e.currentTarget.hasPointerCapture(e.pointerId)) {
        e.currentTarget.releasePointerCapture(e.pointerId);
      }

      if (axis === "h" && Math.abs(dx) >= SWIPE_COMMIT_DISTANCE) {
        onSwipe(dx > 0 ? -1 : 1);
      }
      resetOffset();
    },
    [enabled, onSwipe, resetOffset]
  );

  const onTransitionEnd = useCallback(() => {
    setSettling(false);
  }, []);

  return {
    offset,
    settling,
    handlers: {
      onPointerDown,
      onPointerMove,
      onPointerUp: finishPointer,
      onPointerCancel: finishPointer,
      onTransitionEnd,
    },
  };
}

const STATUS_OPTIONS: TaskStatus[] = ["new", "accepted", "inProgress", "completed"];

function isScheduledTask(task: FamilyTask): boolean {
  return task.task_type !== "flexible";
}

function isImageAttachment(fileType: string): boolean {
  return fileType.startsWith("image/");
}

function sortTasksByTime(a: FamilyTask, b: FamilyTask): number {
  if (a.is_all_day && !b.is_all_day) return -1;
  if (!a.is_all_day && b.is_all_day) return 1;
  const aTime = a.due_date ?? "";
  const bTime = b.due_date ?? "";
  return aTime.localeCompare(bTime);
}

function statusLabel(status: TaskStatus): string {
  switch (status) {
    case "new":
      return "New";
    case "accepted":
      return "Accepted";
    case "inProgress":
      return "In progress";
    case "completed":
      return "Completed";
    default:
      return status;
  }
}

function statusDotClass(status: TaskStatus): string {
  switch (status) {
    case "accepted":
    case "inProgress":
      return styles.axisDotOrange;
    case "completed":
      return styles.axisDotGreen;
    case "issue":
    case "expired":
    case "failed":
    case "cancelled":
      return styles.axisDotRed;
    default:
      return "";
  }
}

function clockHHMM(value: string | null | undefined): string {
  const date = toDate(value);
  if (!date) return "—";
  return format(date, "HH:mm");
}

function taskEndDate(task: FamilyTask): Date | null {
  const start = toDate(task.due_date);
  if (!start) return null;
  const minutes = task.duration_minutes ?? 60;
  return new Date(start.getTime() + minutes * 60_000);
}

function clockRange(task: FamilyTask): string {
  if (task.is_all_day) return "All day";
  const start = clockHHMM(task.due_date);
  const end = taskEndDate(task);
  if (!end) return start;
  return `${start}–${format(end, "HH:mm")}`;
}

function durationLabel(minutes: number | null | undefined): string {
  const m = minutes ?? 60;
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  const rem = m % 60;
  if (rem === 0) return h === 1 ? "1 hr" : `${h} hr`;
  return `${h}h ${rem}m`;
}

function sameMinute(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate() &&
    a.getHours() === b.getHours() &&
    a.getMinutes() === b.getMinutes()
  );
}

function assigneeInitial(name: string): string {
  const trimmed = name.trim();
  if (!trimmed) return "?";
  return trimmed.slice(0, 1).toUpperCase();
}

function MenuIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" aria-hidden>
      <path d="M4 7h16M4 12h16M4 17h16" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

function ClockIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" aria-hidden>
      <circle cx="12" cy="12" r="8" stroke="currentColor" strokeWidth="1.8" />
      <path d="M12 8v4.5l3 1.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
    </svg>
  );
}

function CameraIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M4 8.5A2.5 2.5 0 0 1 6.5 6h2l1.2-1.6A1.5 1.5 0 0 1 10.9 4h2.2a1.5 1.5 0 0 1 1.2.4L15.5 6h2A2.5 2.5 0 0 1 20 8.5v8A2.5 2.5 0 0 1 17.5 19h-11A2.5 2.5 0 0 1 4 16.5v-8Z"
        stroke="currentColor"
        strokeWidth="1.7"
      />
      <circle cx="12" cy="12.5" r="3.2" stroke="currentColor" strokeWidth="1.7" />
    </svg>
  );
}

export default function CalendarPage() {
  const { session, locale, loading: sessionLoading } = useHousehold();
  const { openOrgSwitcher } = useShellChrome();
  const strings = t(locale);

  const [viewMode, setViewMode] = useState<ViewMode>("day");
  const [selectedDay, setSelectedDay] = useState(() => todayStart());
  const [tasks, setTasks] = useState<FamilyTask[]>([]);
  const [attachments, setAttachments] = useState<TaskAttachment[]>([]);
  const [attachmentsLoading, setAttachmentsLoading] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [roster, setRoster] = useState<RosterEntry[]>([]);
  const [involvedIds, setInvolvedIds] = useState<string[]>([]);
  const [recurrence, setRecurrence] = useState<string>("none");
  const [menuOpen, setMenuOpen] = useState(false);
  const [quickTitle, setQuickTitle] = useState("");
  const [monthSheetOpen, setMonthSheetOpen] = useState(false);

  const [createOpen, setCreateOpen] = useState(false);
  const [detailOpen, setDetailOpen] = useState(false);
  const [selectedTask, setSelectedTask] = useState<FamilyTask | null>(null);

  const [title, setTitle] = useState("");
  const [notes, setNotes] = useState("");
  const [dueDate, setDueDate] = useState(() => toLocalDateInput(todayStart()));
  const [dueTime, setDueTime] = useState("09:00");
  const [durationMinutes, setDurationMinutes] = useState("60");
  const [isAllDay, setIsAllDay] = useState(false);

  const onWeekStripSwipe = useCallback((direction: -1 | 1) => {
    setSelectedDay((day) => shiftWeek(day, direction));
  }, []);

  const onDayContentSwipe = useCallback((direction: -1 | 1) => {
    setViewMode("day");
    setSelectedDay((day) => shiftDay(day, direction));
  }, []);

  const weekSwipe = useHorizontalSwipe(onWeekStripSwipe, true);
  const daySwipe = useHorizontalSwipe(onDayContentSwipe, viewMode === "day");

  const loadTasks = useCallback(async () => {
    if (!session?.householdId) {
      setTasks([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const [tasksResult, rosterResult] = await Promise.allSettled([
        fetchTasks(session.householdId),
        fetchRoster(session.householdId),
      ]);
      if (tasksResult.status === "fulfilled") {
        setTasks(tasksResult.value.filter(isScheduledTask));
      } else {
        throw tasksResult.reason;
      }
      if (rosterResult.status === "fulfilled") {
        setRoster(rosterResult.value);
      } else {
        console.warn("[calendar] roster:", rosterResult.reason);
        setRoster([]);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setLoading(false);
    }
  }, [session?.householdId, strings.error]);

  useEffect(() => {
    void loadTasks();
  }, [loadTasks]);

  const dayTasks = useMemo(
    () =>
      tasks
        .filter((task) => isSameCalendarDay(task.due_date, selectedDay))
        .sort(sortTasksByTime),
    [tasks, selectedDay]
  );

  const allDayTasks = useMemo(() => dayTasks.filter((task) => task.is_all_day), [dayTasks]);
  const timedTasks = useMemo(() => dayTasks.filter((task) => !task.is_all_day), [dayTasks]);

  const weekDaysList = useMemo(() => weekDays(selectedDay), [selectedDay]);

  const taskCountByDay = useMemo(() => {
    const map = new Map<string, number>();
    for (const day of weekDaysList) {
      const key = toLocalDateInput(day);
      map.set(
        key,
        tasks.filter((task) => isSameCalendarDay(task.due_date, day)).length
      );
    }
    return map;
  }, [tasks, weekDaysList]);

  const daysWithTasks = useMemo(() => {
    const set = new Set<string>();
    for (const task of tasks) {
      if (!task.due_date) continue;
      const date = toDate(task.due_date);
      if (!date) continue;
      set.add(toLocalDateInput(date));
    }
    return set;
  }, [tasks]);

  const rosterByMembership = useMemo(() => {
    const map = new Map<string, string>();
    for (const entry of roster) {
      map.set(
        entry.membership.id,
        entry.profile?.display_name ?? entry.membership.display_name ?? "Member"
      );
    }
    return map;
  }, [roster]);

  const attachmentLimit = maxAttachments(false);

  useEffect(() => {
    if (!detailOpen || !selectedTask) return;

    let cancelled = false;
    setAttachmentsLoading(true);
    void fetchAttachments(selectedTask.id)
      .then((rows) => {
        if (!cancelled) setAttachments(rows);
      })
      .catch((err) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : strings.error);
        }
      })
      .finally(() => {
        if (!cancelled) setAttachmentsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [detailOpen, selectedTask, strings.error]);

  function closeDetail() {
    setDetailOpen(false);
    setSelectedTask(null);
    setAttachments([]);
  }

  function resetCreateForm(prefillTitle = "") {
    const now = new Date();
    const rounded = new Date(now);
    rounded.setSeconds(0, 0);
    const minutes = rounded.getMinutes();
    const add = minutes === 0 ? 0 : 30 - (minutes % 30);
    rounded.setMinutes(minutes + add);
    if (add === 0 && now.getSeconds() > 0) {
      rounded.setMinutes(rounded.getMinutes() + 30);
    }

    setTitle(prefillTitle);
    setNotes("");
    setDueDate(toLocalDateInput(selectedDay));
    setDueTime(format(rounded, "HH:mm"));
    setDurationMinutes("60");
    setIsAllDay(false);
    setInvolvedIds([]);
    setRecurrence("none");
  }

  function openCreate(prefillTitle = "") {
    resetCreateForm(prefillTitle);
    setCreateOpen(true);
  }

  function openDetail(task: FamilyTask) {
    setSelectedTask(task);
    setTitle(task.title);
    setNotes(task.notes ?? "");
    const due = task.due_date ? new Date(task.due_date) : selectedDay;
    setDueDate(toLocalDateInput(due));
    setDueTime(formatTime(task.due_date, locale).replace("—", "09:00"));
    setDurationMinutes(String(task.duration_minutes ?? 60));
    setIsAllDay(task.is_all_day);
    setInvolvedIds(task.involved_member_ids ?? []);
    setRecurrence(task.recurrence_rule ?? "none");
    setDetailOpen(true);
  }

  function primaryAssigneeName(task: FamilyTask): string | null {
    const ids = task.involved_member_ids ?? [];
    if (!ids.length) return null;
    return rosterByMembership.get(ids[0]) ?? null;
  }

  async function onCreate(values: CreateEventValues) {
    if (!session?.householdId || !session.membershipId) return;

    setBusy(true);
    setError(null);
    try {
      const dueIso = values.isAllDay
        ? new Date(`${values.dueDate}T00:00:00`).toISOString()
        : new Date(`${values.dueDate}T${values.dueTime}:00`).toISOString();

      const noteParts = [values.notes.trim(), values.financeDetail.trim()].filter(Boolean);
      const mergedNotes = noteParts.length ? noteParts.join("\n\n") : null;
      const costMajor = Number.parseFloat(values.cost);
      const estimatedCost = Number.isFinite(costMajor)
        ? Math.round(costMajor * 100)
        : 0;
      const locationName = values.locationName.trim();

      const created = await createScheduledTask({
        householdId: session.householdId,
        creatorMembershipId: session.membershipId,
        title: values.title,
        notes: mergedNotes,
        dueDate: dueIso,
        durationMinutes: Number(values.durationMinutes) || 60,
        isAllDay: values.isAllDay,
        involvedMemberIds: values.involvedIds.length ? values.involvedIds : null,
        recurrenceRule: values.recurrence === "none" ? null : values.recurrence,
        priority: values.priority,
        emergencyPhone: values.emergencyPhone.trim() || null,
        reminderOffsets: reminderOffsetsFromKey(values.reminder),
        estimatedCost,
        locationData: locationName ? { name: locationName } : null,
      });

      if (values.attachmentFiles.length > 0) {
        await uploadTaskAttachments(created.id, session.householdId, values.attachmentFiles, {
          existingCount: 0,
          hasPremium: false,
        }).catch((err) => {
          console.warn("[calendar] attachment upload:", err);
        });
      }

      setCreateOpen(false);
      resetCreateForm();
      setQuickTitle("");
      await loadTasks();
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  function onQuickSubmit(e: FormEvent) {
    e.preventDefault();
    const trimmed = quickTitle.trim();
    if (!trimmed) return;
    openCreate(trimmed);
    setQuickTitle("");
  }

  async function onSaveDetail(e: FormEvent) {
    e.preventDefault();
    if (!selectedTask) return;

    setBusy(true);
    setError(null);
    try {
      const dueIso = isAllDay
        ? new Date(`${dueDate}T00:00:00`).toISOString()
        : new Date(`${dueDate}T${dueTime}:00`).toISOString();

      await updateTask(selectedTask.id, {
        title: title.trim(),
        notes: notes.trim() || null,
        due_date: dueIso,
        duration_minutes: Number(durationMinutes) || 60,
        is_all_day: isAllDay,
        involved_member_ids: involvedIds.length ? involvedIds : null,
        recurrence_rule: recurrence === "none" ? null : recurrence,
      });

      closeDetail();
      await loadTasks();
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  async function onUploadAttachments(e: ChangeEvent<HTMLInputElement>) {
    if (!selectedTask || !session?.householdId) return;

    const files = e.target.files;
    if (!files?.length) return;

    setBusy(true);
    setError(null);
    try {
      await uploadTaskAttachments(selectedTask.id, session.householdId, Array.from(files), {
        existingCount: attachments.length,
        hasPremium: false,
      });
      const rows = await fetchAttachments(selectedTask.id);
      setAttachments(rows);
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
      e.target.value = "";
    }
  }

  async function onDeleteAttachment(attachmentId: string) {
    setBusy(true);
    setError(null);
    try {
      await deleteAttachments([attachmentId]);
      setAttachments((prev) => prev.filter((item) => item.id !== attachmentId));
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  async function onStatusChange(status: TaskStatus) {
    if (!selectedTask || !session?.membershipId) return;

    setBusy(true);
    setError(null);
    try {
      if (status === "completed") {
        await completeTask(selectedTask.id, session.membershipId);
      } else {
        await patchStatus(selectedTask.id, status);
      }
      closeDetail();
      await loadTasks();
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  async function onDelete() {
    if (!selectedTask) return;
    if (!window.confirm(strings.delete + "?")) return;

    setBusy(true);
    setError(null);
    try {
      await deleteTask(selectedTask.id);
      closeDetail();
      await loadTasks();
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  if (sessionLoading) {
    return (
      <div className={styles.center}>
        <Spinner />
      </div>
    );
  }

  if (!session) {
    return (
      <Empty
        title={strings.noOrgSelected}
        description="Choose a household from the header to view your schedule."
      />
    );
  }

  const householdLabel = session.householdName ?? strings.noOrgSelected;
  const todayKey = toLocalDateInput(todayStart());
  const selectedKey = toLocalDateInput(selectedDay);

  return (
    <div className={styles.page}>
      <header className={styles.toolbar}>
        <button type="button" className={styles.pill} onClick={openOrgSwitcher}>
          <span className={styles.pillText}>{householdLabel}</span>
          <span className={styles.pillChevron} aria-hidden>
            ▼
          </span>
        </button>

        <button type="button" className={styles.pill} onClick={() => setMonthSheetOpen(true)}>
          <span className={styles.pillText}>{formatMonthLabel(selectedDay, locale)}</span>
          <span className={styles.pillChevron} aria-hidden>
            ▼
          </span>
        </button>

        <div className={styles.toolbarSpacer} />

        <button
          type="button"
          className={styles.menuBtn}
          aria-label="View options"
          aria-expanded={menuOpen}
          onClick={() => setMenuOpen((open) => !open)}
        >
          <MenuIcon />
        </button>
      </header>

      {menuOpen ? (
        <div className={styles.menuPopover} role="menu">
          <button
            type="button"
            className={[styles.menuItem, viewMode === "day" ? styles.menuItemActive : ""]
              .filter(Boolean)
              .join(" ")}
            onClick={() => {
              setViewMode("day");
              setMenuOpen(false);
            }}
          >
            Day
          </button>
          <button
            type="button"
            className={[styles.menuItem, viewMode === "week" ? styles.menuItemActive : ""]
              .filter(Boolean)
              .join(" ")}
            onClick={() => {
              setViewMode("week");
              setMenuOpen(false);
            }}
          >
            Week
          </button>
          <button
            type="button"
            className={styles.menuItem}
            onClick={() => {
              setSelectedDay(todayStart());
              setMenuOpen(false);
            }}
          >
            Today
          </button>
          <button
            type="button"
            className={styles.menuItem}
            onClick={() => {
              setSelectedDay((d) => shiftWeek(d, -1));
              setMenuOpen(false);
            }}
          >
            Previous week
          </button>
          <button
            type="button"
            className={styles.menuItem}
            onClick={() => {
              setSelectedDay((d) => shiftWeek(d, 1));
              setMenuOpen(false);
            }}
          >
            Next week
          </button>
        </div>
      ) : null}

      <div
        className={[
          styles.weekStripSwipe,
          weekSwipe.settling ? styles.swipeSettling : "",
        ]
          .filter(Boolean)
          .join(" ")}
        style={{ transform: `translateX(${weekSwipe.offset}px)` }}
        {...weekSwipe.handlers}
      >
        <div className={styles.weekStrip}>
          {weekDaysList.map((day) => {
            const key = toLocalDateInput(day);
            const selected = key === selectedKey;
            const isToday = key === todayKey;
            const count = taskCountByDay.get(key) ?? 0;
            return (
              <button
                key={key}
                type="button"
                className={styles.weekDay}
                onClick={() => {
                  setSelectedDay(day);
                  setViewMode("day");
                }}
              >
                <span
                  className={[styles.weekDayLabel, selected ? styles.weekDayLabelSelected : ""]
                    .filter(Boolean)
                    .join(" ")}
                >
                  {formatWeekdayShort(day, locale)}
                </span>
                <span
                  className={[
                    styles.weekDayNum,
                    selected ? styles.weekDayNumSelected : "",
                    !selected && isToday ? styles.weekDayNumToday : "",
                  ]
                    .filter(Boolean)
                    .join(" ")}
                >
                  {format(day, "d")}
                </span>
                <span className={styles.weekDots} aria-hidden>
                  {count >= 1 ? (
                    <span className={[styles.weekDot, styles.weekDotBlue].join(" ")} />
                  ) : null}
                  {count >= 3 ? (
                    <span className={[styles.weekDot, styles.weekDotOrange].join(" ")} />
                  ) : null}
                  {count >= 5 ? (
                    <span className={[styles.weekDot, styles.weekDotRed].join(" ")} />
                  ) : null}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      {error ? <p className={styles.error}>{error}</p> : null}

      {loading ? (
        <div className={styles.center}>
          <Spinner />
        </div>
      ) : viewMode === "week" ? (
        <WeekTimelineGrid
          weekDays={weekDaysList}
          tasks={tasks}
          selectedDay={selectedDay}
          onSelectDay={(day) => setSelectedDay(day)}
          onSelectTask={openDetail}
          onSwipeWeek={(direction) => setSelectedDay((day) => shiftWeek(day, direction))}
          label={formatWeekLabel(selectedDay, locale)}
        />
      ) : (
        <div
          className={[
            styles.daySwipePane,
            daySwipe.settling ? styles.swipeSettling : "",
          ]
            .filter(Boolean)
            .join(" ")}
          style={{ transform: `translateX(${daySwipe.offset}px)` }}
          {...daySwipe.handlers}
        >
          {allDayTasks.length > 0 ? (
            <div className={styles.allDayStrip}>
              {allDayTasks.map((task) => (
                <button
                  key={task.id}
                  type="button"
                  className={styles.allDayCard}
                  onClick={() => openDetail(task)}
                >
                  <p className={styles.taskTitle}>{task.title}</p>
                  <div className={styles.taskMeta}>All day</div>
                </button>
              ))}
            </div>
          ) : null}

          {timedTasks.length === 0 && allDayTasks.length === 0 ? (
            <div className={styles.empty}>
              <p className={styles.emptyTitle}>{strings.emptyTasks}</p>
              <Button onClick={() => openCreate()}>{strings.create}</Button>
            </div>
          ) : timedTasks.length > 0 ? (
            <div className={styles.timeline}>
              {timedTasks.map((task, index) => {
                const start = toDate(task.due_date) ?? selectedDay;
                const prev = index > 0 ? timedTasks[index - 1] : null;
                const prevStart = prev ? toDate(prev.due_date) : null;
                const showTime = !prevStart || !sameMinute(prevStart, start);
                const longIdle =
                  prevStart != null &&
                  showTime &&
                  start.getTime() - prevStart.getTime() >= LONG_IDLE_MS;
                const assignee = primaryAssigneeName(task);

                return (
                  <div key={task.id}>
                    {index > 0 && showTime ? (
                      <div className={styles.gapRow} aria-hidden>
                        <div />
                        <div className={styles.axisCol}>
                          <div className={longIdle ? styles.gapLineDashed : styles.gapLine} />
                        </div>
                        <div />
                      </div>
                    ) : null}

                    <div className={styles.timelineRow}>
                      <div
                        className={[styles.timeCol, showTime ? "" : styles.timeColHidden]
                          .filter(Boolean)
                          .join(" ")}
                      >
                        {clockHHMM(task.due_date)}
                      </div>
                      <div className={styles.axisCol}>
                        <span
                          className={[
                            styles.axisDot,
                            statusDotClass(task.status),
                            showTime ? "" : styles.axisDotHidden,
                          ]
                            .filter(Boolean)
                            .join(" ")}
                        />
                      </div>
                      <div className={styles.cardCol}>
                        <button
                          type="button"
                          className={[
                            styles.taskCard,
                            task.status === "completed" ? styles.taskCardDone : "",
                          ]
                            .filter(Boolean)
                            .join(" ")}
                          onClick={() => openDetail(task)}
                        >
                          <div className={styles.taskCardMain}>
                            <p className={styles.taskTitle}>
                              {task.status === "completed" ? `✅ ${task.title}` : task.title}
                            </p>
                            <div className={styles.taskMeta}>
                              <span className={styles.taskMetaTime}>
                                <ClockIcon />
                                {clockRange(task)}
                              </span>
                              <span className={styles.durationBadge}>
                                {durationLabel(task.duration_minutes)}
                              </span>
                            </div>
                          </div>
                          {assignee ? (
                            <span className={styles.avatar} title={assignee}>
                              {assigneeInitial(assignee)}
                            </span>
                          ) : null}
                        </button>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          ) : null}
        </div>
      )}

      <button type="button" className={styles.fab} aria-label={strings.create} onClick={() => openCreate()}>
        +
      </button>

      <MonthCalendarSheet
        open={monthSheetOpen}
        onClose={() => setMonthSheetOpen(false)}
        selectedDay={selectedDay}
        onSelectDay={(day) => {
          setSelectedDay(day);
          setViewMode("day");
        }}
        daysWithTasks={daysWithTasks}
        locale={locale}
      />

      <form className={styles.quickBar} onSubmit={onQuickSubmit}>
        <input
          className={styles.quickInput}
          value={quickTitle}
          onChange={(e) => setQuickTitle(e.target.value)}
          placeholder="Enter task title..."
          aria-label="Quick create task"
        />
        <button
          type="button"
          className={styles.cameraBtn}
          aria-label="Create from photo"
          onClick={() => openCreate()}
        >
          <CameraIcon />
        </button>
      </form>

      <CreateEventSheet
        open={createOpen}
        busy={busy}
        locale={locale}
        roster={roster}
        myMembershipId={session.membershipId}
        initial={{
          title,
          notes,
          dueDate,
          dueTime,
          durationMinutes,
          isAllDay,
          involvedIds,
          recurrence,
          reminder: "15",
          priority: "normal",
          emergencyPhone: "",
          locationName: "",
          cost: "",
          financeDetail: "",
        }}
        onClose={() => setCreateOpen(false)}
        onSubmit={onCreate}
      />

      <Sheet open={detailOpen} onClose={closeDetail} title="Task details">
        {selectedTask ? (
          <form className={styles.form} onSubmit={onSaveDetail}>
            <Input label="Title" value={title} onChange={(e) => setTitle(e.target.value)} required />
            <Input label="Date" type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} required />
            <label className={styles.toggleLabel}>
              <input type="checkbox" checked={isAllDay} onChange={(e) => setIsAllDay(e.target.checked)} />
              All day
            </label>
            {!isAllDay ? (
              <>
                <Input label="Time" type="time" value={dueTime} onChange={(e) => setDueTime(e.target.value)} required />
                <Input
                  label="Duration (minutes)"
                  type="number"
                  min={5}
                  step={5}
                  value={durationMinutes}
                  onChange={(e) => setDurationMinutes(e.target.value)}
                />
              </>
            ) : null}

            <div className={styles.fieldBlock}>
              <p className={styles.fieldLabel}>Assignees</p>
              <div className={styles.chipRow}>
                {roster.map((entry) => {
                  const mid = entry.membership.id;
                  const label =
                    entry.profile?.display_name ?? entry.membership.display_name ?? "Member";
                  const on = involvedIds.includes(mid);
                  return (
                    <button
                      key={mid}
                      type="button"
                      className={[styles.chip, on ? styles.chipOn : ""].filter(Boolean).join(" ")}
                      onClick={() =>
                        setInvolvedIds((prev) =>
                          on ? prev.filter((id) => id !== mid) : [...prev, mid]
                        )
                      }
                    >
                      {label}
                    </button>
                  );
                })}
              </div>
            </div>
            <label className={styles.fieldBlock}>
              <span className={styles.fieldLabel}>Repeat</span>
              <select
                className={styles.select}
                value={recurrence}
                onChange={(e) => setRecurrence(e.target.value)}
              >
                <option value="none">Does not repeat</option>
                <option value="daily">Daily</option>
                <option value="weekly">Weekly</option>
                <option value="monthly">Monthly</option>
              </select>
            </label>

            <TextArea label="Notes" value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} />

            <div className={styles.fieldBlock}>
              <p className={styles.fieldLabel}>Attachments</p>
              <p className={styles.attachHint}>
                Free plan: up to {attachmentLimit} attachment{attachmentLimit === 1 ? "" : "s"}
              </p>
              {attachmentsLoading ? (
                <div className={styles.center}>
                  <Spinner />
                </div>
              ) : attachments.length > 0 ? (
                <div className={styles.attachGrid}>
                  {attachments.map((attachment) => (
                    <div key={attachment.id} className={styles.attachThumb}>
                      {isImageAttachment(attachment.file_type) ? (
                        <a href={attachment.file_url} target="_blank" rel="noopener noreferrer">
                          <img src={attachment.file_url} alt="" />
                        </a>
                      ) : (
                        <a
                          href={attachment.file_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className={styles.attachThumbLink}
                        >
                          File
                        </a>
                      )}
                      <button
                        type="button"
                        className={styles.attachDelete}
                        aria-label="Delete attachment"
                        onClick={() => void onDeleteAttachment(attachment.id)}
                        disabled={busy}
                      >
                        ×
                      </button>
                    </div>
                  ))}
                </div>
              ) : null}
              <input
                type="file"
                accept="image/*"
                multiple
                className={styles.attachInput}
                onChange={(e) => void onUploadAttachments(e)}
                disabled={busy || attachments.length >= attachmentLimit}
              />
            </div>

            <div className={styles.statusRow}>
              {STATUS_OPTIONS.map((status) => (
                <button
                  key={status}
                  type="button"
                  className={[
                    styles.statusBtn,
                    selectedTask.status === status ? styles.statusBtnActive : "",
                  ]
                    .filter(Boolean)
                    .join(" ")}
                  onClick={() => void onStatusChange(status)}
                  disabled={busy}
                >
                  {statusLabel(status)}
                </button>
              ))}
            </div>

            <div className={styles.actions}>
              <Button fullWidth type="submit" loading={busy}>
                {strings.save}
              </Button>
              <Button
                fullWidth
                variant="destructive"
                type="button"
                onClick={() => void onDelete()}
                disabled={busy}
              >
                {strings.delete}
              </Button>
              <Button fullWidth variant="secondary" type="button" onClick={closeDetail}>
                {strings.cancel}
              </Button>
            </div>
          </form>
        ) : null}
      </Sheet>
    </div>
  );
}
