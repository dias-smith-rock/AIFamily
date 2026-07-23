"use client";

import { ChangeEvent, FormEvent, useCallback, useEffect, useMemo, useState } from "react";
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
  formatDayLabel,
  formatTime,
  formatWeekLabel,
  formatWeekdayShort,
  isSameCalendarDay,
  shiftDay,
  shiftWeek,
  todayStart,
  toLocalDateInput,
  weekDays,
} from "@/lib/date-utils";
import { useHousehold } from "@/lib/household-context";
import { t } from "@/lib/i18n";
import type { FamilyTask, TaskStatus } from "@/lib/types";
import {
  Button,
  Empty,
  IconButton,
  Input,
  Segmented,
  Sheet,
  Spinner,
  TextArea,
} from "@/components/ui";
import { format } from "date-fns";
import styles from "./calendar.module.css";

type ViewMode = "day" | "week";
const WEEK_TASK_PREVIEW = 4;

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

export default function CalendarPage() {
  const { session, locale, loading: sessionLoading } = useHousehold();
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

  const [createOpen, setCreateOpen] = useState(false);
  const [detailOpen, setDetailOpen] = useState(false);
  const [selectedTask, setSelectedTask] = useState<FamilyTask | null>(null);

  const [title, setTitle] = useState("");
  const [notes, setNotes] = useState("");
  const [dueDate, setDueDate] = useState(() => toLocalDateInput(todayStart()));
  const [dueTime, setDueTime] = useState("09:00");
  const [durationMinutes, setDurationMinutes] = useState("60");
  const [isAllDay, setIsAllDay] = useState(false);

  const loadTasks = useCallback(async () => {
    if (!session?.householdId) {
      setTasks([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const [rows, rosterRows] = await Promise.all([
        fetchTasks(session.householdId),
        fetchRoster(session.householdId),
      ]);
      setTasks(rows.filter(isScheduledTask));
      setRoster(rosterRows);
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

  const weekDaysList = useMemo(() => weekDays(selectedDay), [selectedDay]);

  const tasksByWeekDay = useMemo(() => {
    const map = new Map<string, FamilyTask[]>();
    for (const day of weekDaysList) {
      map.set(
        toLocalDateInput(day),
        tasks.filter((task) => isSameCalendarDay(task.due_date, day)).sort(sortTasksByTime)
      );
    }
    return map;
  }, [tasks, weekDaysList]);

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

  function resetCreateForm() {
    setTitle("");
    setNotes("");
    setDueDate(toLocalDateInput(selectedDay));
    setDueTime("09:00");
    setDurationMinutes("60");
    setIsAllDay(false);
    setInvolvedIds([]);
    setRecurrence("none");
  }

  function openCreate() {
    resetCreateForm();
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

  async function onCreate(e: FormEvent) {
    e.preventDefault();
    if (!session?.householdId || !session.membershipId) return;

    setBusy(true);
    setError(null);
    try {
      const dueIso = isAllDay
        ? new Date(`${dueDate}T00:00:00`).toISOString()
        : new Date(`${dueDate}T${dueTime}:00`).toISOString();

      await createScheduledTask({
        householdId: session.householdId,
        creatorMembershipId: session.membershipId,
        title,
        notes: notes || null,
        dueDate: dueIso,
        durationMinutes: Number(durationMinutes) || 60,
        isAllDay,
        involvedMemberIds: involvedIds.length ? involvedIds : null,
        recurrenceRule: recurrence === "none" ? null : recurrence,
      });

      setCreateOpen(false);
      resetCreateForm();
      await loadTasks();
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
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

  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <h1 className={styles.title}>{strings.tabSchedule}</h1>
        <Segmented
          options={[
            { value: "day" as const, label: "Day" },
            { value: "week" as const, label: "Week" },
          ]}
          value={viewMode}
          onChange={setViewMode}
        />
      </header>

      <div className={styles.dayNav}>
        <IconButton
          label={viewMode === "day" ? "Previous day" : "Previous week"}
          onClick={() =>
            setSelectedDay((d) => (viewMode === "day" ? shiftDay(d, -1) : shiftWeek(d, -1)))
          }
        >
          ‹
        </IconButton>
        <div>
          <p className={styles.dayLabel}>
            {viewMode === "day"
              ? formatDayLabel(selectedDay, locale)
              : formatWeekLabel(selectedDay, locale)}
          </p>
          <button type="button" className={styles.todayBtn} onClick={() => setSelectedDay(todayStart())}>
            Today
          </button>
        </div>
        <IconButton
          label={viewMode === "day" ? "Next day" : "Next week"}
          onClick={() =>
            setSelectedDay((d) => (viewMode === "day" ? shiftDay(d, 1) : shiftWeek(d, 1)))
          }
        >
          ›
        </IconButton>
      </div>

      {error ? <p className={styles.error}>{error}</p> : null}

      {loading ? (
        <div className={styles.center}>
          <Spinner />
        </div>
      ) : viewMode === "week" ? (
        <div className={styles.weekGridWrap}>
          <div className={styles.weekGrid}>
            {weekDaysList.map((day) => {
              const dayKey = toLocalDateInput(day);
              const columnTasks = tasksByWeekDay.get(dayKey) ?? [];
              const previewTasks = columnTasks.slice(0, WEEK_TASK_PREVIEW);
              const overflowCount = columnTasks.length - previewTasks.length;
              const isToday = toLocalDateInput(day) === toLocalDateInput(todayStart());
              const isSelected = toLocalDateInput(day) === toLocalDateInput(selectedDay);

              return (
                <div
                  key={dayKey}
                  className={[
                    styles.weekCol,
                    isToday ? styles.weekColToday : "",
                    isSelected ? styles.weekColSelected : "",
                  ]
                    .filter(Boolean)
                    .join(" ")}
                >
                  <button
                    type="button"
                    className={styles.weekColHeader}
                    onClick={() => setSelectedDay(day)}
                  >
                    <span className={styles.weekColWeekday}>{formatWeekdayShort(day, locale)}</span>
                    <span className={styles.weekColDate}>{format(day, "d")}</span>
                  </button>
                  {previewTasks.map((task) => (
                    <button
                      key={task.id}
                      type="button"
                      className={styles.weekTask}
                      onClick={() => openDetail(task)}
                    >
                      {task.title}
                    </button>
                  ))}
                  {overflowCount > 0 ? (
                    <span className={styles.weekTaskMore}>+{overflowCount}</span>
                  ) : null}
                </div>
              );
            })}
          </div>
        </div>
      ) : dayTasks.length === 0 ? (
        <Empty title={strings.emptyTasks} action={<Button onClick={openCreate}>{strings.create}</Button>} />
      ) : (
        <div className={styles.taskList}>
          {dayTasks.map((task) => (
            <button
              key={task.id}
              type="button"
              className={[
                styles.taskCard,
                task.status === "completed" ? styles.taskCardDone : "",
              ]
                .filter(Boolean)
                .join(" ")}
              onClick={() => openDetail(task)}
            >
              <p className={styles.taskTitle}>{task.title}</p>
              <div className={styles.taskMeta}>
                <span>{task.is_all_day ? "All day" : formatTime(task.due_date, locale)}</span>
                {!task.is_all_day ? <span>{task.duration_minutes} min</span> : null}
                <span className={styles.statusBadge}>{statusLabel(task.status)}</span>
              </div>
            </button>
          ))}
        </div>
      )}

      <button type="button" className={styles.fab} aria-label={strings.create} onClick={openCreate}>
        +
      </button>

      <Sheet open={createOpen} onClose={() => setCreateOpen(false)} title={strings.create}>
        <form className={styles.form} onSubmit={onCreate}>
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
                  entry.profile?.display_name ??
                  entry.membership.display_name ??
                  "Member";
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
          <Button fullWidth type="submit" loading={busy} disabled={!title.trim()}>
            {strings.create}
          </Button>
        </form>
      </Sheet>

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
                  entry.profile?.display_name ??
                  entry.membership.display_name ??
                  "Member";
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
              <Button fullWidth variant="destructive" type="button" onClick={() => void onDelete()} disabled={busy}>
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
