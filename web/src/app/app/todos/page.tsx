"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import {
  completeTask,
  createFlexibleTask,
  deleteTask,
  fetchTasks,
  updateTask,
} from "@/lib/api/tasks";
import { formatDateTime, isBeforeToday, toLocalDateInput } from "@/lib/date-utils";
import { useHousehold } from "@/lib/household-context";
import { t } from "@/lib/i18n";
import type { FamilyTask } from "@/lib/types";
import { Button, Empty, Input, Sheet, Spinner, TextArea } from "@/components/ui";
import styles from "./todos.module.css";

function isFlexibleTask(task: FamilyTask): boolean {
  return task.task_type === "flexible";
}

export default function TodosPage() {
  const { session, locale, loading: sessionLoading } = useHousehold();
  const strings = t(locale);

  const [tasks, setTasks] = useState<FamilyTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [createOpen, setCreateOpen] = useState(false);
  const [detailOpen, setDetailOpen] = useState(false);
  const [selectedTask, setSelectedTask] = useState<FamilyTask | null>(null);

  const [title, setTitle] = useState("");
  const [notes, setNotes] = useState("");
  const [deadline, setDeadline] = useState("");

  const loadTasks = useCallback(async () => {
    if (!session?.householdId) {
      setTasks([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const rows = await fetchTasks(session.householdId);
      setTasks(rows.filter(isFlexibleTask));
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setLoading(false);
    }
  }, [session?.householdId, strings.error]);

  useEffect(() => {
    void loadTasks();
  }, [loadTasks]);

  const grouped = useMemo(() => {
    const active: FamilyTask[] = [];
    const overdue: FamilyTask[] = [];
    const completed: FamilyTask[] = [];

    for (const task of tasks) {
      if (task.status === "completed") {
        completed.push(task);
      } else if (task.due_date && isBeforeToday(task.due_date)) {
        overdue.push(task);
      } else {
        active.push(task);
      }
    }

    return { active, overdue, completed };
  }, [tasks]);

  function resetForm() {
    setTitle("");
    setNotes("");
    setDeadline("");
  }

  function openDetail(task: FamilyTask) {
    setSelectedTask(task);
    setTitle(task.title);
    setNotes(task.notes ?? "");
    setDeadline(task.due_date ? toLocalDateInput(new Date(task.due_date)) : "");
    setDetailOpen(true);
  }

  async function onCreate(e: FormEvent) {
    e.preventDefault();
    if (!session?.householdId || !session.membershipId) return;

    setBusy(true);
    setError(null);
    try {
      await createFlexibleTask({
        householdId: session.householdId,
        creatorMembershipId: session.membershipId,
        title,
        notes: notes || null,
        dueDate: deadline ? new Date(`${deadline}T23:59:59`).toISOString() : null,
      });
      setCreateOpen(false);
      resetForm();
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
      await updateTask(selectedTask.id, {
        title: title.trim(),
        notes: notes.trim() || null,
        due_date: deadline ? new Date(`${deadline}T23:59:59`).toISOString() : null,
      });
      setDetailOpen(false);
      setSelectedTask(null);
      await loadTasks();
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  async function onToggleComplete(task: FamilyTask, checked: boolean) {
    if (!session?.membershipId) return;

    setBusy(true);
    setError(null);
    try {
      if (checked) {
        await completeTask(task.id, session.membershipId);
      } else {
        await updateTask(task.id, { status: "new" });
      }
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
      setDetailOpen(false);
      setSelectedTask(null);
      await loadTasks();
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  function renderSection(
    heading: string,
    items: FamilyTask[],
    options?: { overdue?: boolean; done?: boolean }
  ) {
    if (items.length === 0) return null;

    return (
      <section className={styles.section}>
        <h2 className={[styles.sectionTitle, options?.overdue ? styles.overdueTitle : ""].filter(Boolean).join(" ")}>
          {heading}
        </h2>
        {items.map((task) => (
          <div key={task.id} className={[styles.todoRow, options?.done ? styles.todoRowDone : ""].filter(Boolean).join(" ")}>
            <input
              type="checkbox"
              className={styles.checkbox}
              checked={task.status === "completed"}
              disabled={busy}
              onChange={(e) => void onToggleComplete(task, e.target.checked)}
              aria-label={`Complete ${task.title}`}
            />
            <button type="button" className={styles.todoBody} onClick={() => openDetail(task)}>
              <p className={[styles.todoTitle, options?.done ? styles.todoTitleDone : ""].filter(Boolean).join(" ")}>
                {task.title}
              </p>
              {task.due_date ? (
                <p className={[styles.todoMeta, options?.overdue ? styles.overdueMeta : ""].filter(Boolean).join(" ")}>
                  Due {formatDateTime(task.due_date, locale)}
                </p>
              ) : null}
            </button>
          </div>
        ))}
      </section>
    );
  }

  if (sessionLoading) {
    return (
      <div className={styles.center}>
        <Spinner />
      </div>
    );
  }

  if (!session) {
    return <Empty title={strings.noOrgSelected} />;
  }

  const hasAny =
    grouped.active.length + grouped.overdue.length + grouped.completed.length > 0;

  return (
    <div className={styles.page}>
      <h1 className={styles.title}>{strings.tabTodos}</h1>

      {error ? <p className={styles.error}>{error}</p> : null}

      {loading ? (
        <div className={styles.center}>
          <Spinner />
        </div>
      ) : !hasAny ? (
        <Empty title={strings.emptyTodos} action={<Button onClick={() => setCreateOpen(true)}>{strings.create}</Button>} />
      ) : (
        <>
          {renderSection("Overdue", grouped.overdue, { overdue: true })}
          {renderSection("Active", grouped.active)}
          {renderSection("Completed", grouped.completed, { done: true })}
        </>
      )}

      <button type="button" className={styles.fab} aria-label={strings.create} onClick={() => setCreateOpen(true)}>
        +
      </button>

      <Sheet open={createOpen} onClose={() => setCreateOpen(false)} title={strings.create}>
        <form className={styles.form} onSubmit={onCreate}>
          <Input label="Title" value={title} onChange={(e) => setTitle(e.target.value)} required />
          <Input label="Deadline (optional)" type="date" value={deadline} onChange={(e) => setDeadline(e.target.value)} />
          <TextArea label="Notes" value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} />
          <Button fullWidth type="submit" loading={busy} disabled={!title.trim()}>
            {strings.create}
          </Button>
        </form>
      </Sheet>

      <Sheet
        open={detailOpen}
        onClose={() => {
          setDetailOpen(false);
          setSelectedTask(null);
        }}
        title="Todo details"
      >
        {selectedTask ? (
          <form className={styles.form} onSubmit={onSaveDetail}>
            <Input label="Title" value={title} onChange={(e) => setTitle(e.target.value)} required />
            <Input label="Deadline (optional)" type="date" value={deadline} onChange={(e) => setDeadline(e.target.value)} />
            <TextArea label="Notes" value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} />
            <div className={styles.actions}>
              <Button fullWidth type="submit" loading={busy}>
                {strings.save}
              </Button>
              <Button fullWidth variant="destructive" type="button" onClick={() => void onDelete()} disabled={busy}>
                {strings.delete}
              </Button>
            </div>
          </form>
        ) : null}
      </Sheet>
    </div>
  );
}
