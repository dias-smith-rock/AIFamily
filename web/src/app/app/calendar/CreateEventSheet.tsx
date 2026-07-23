"use client";

import { FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { format } from "date-fns";
import { enUS, zhCN, zhTW } from "date-fns/locale";
import { Sheet } from "@/components/ui";
import type { RosterEntry } from "@/lib/api/members";
import type { AppLocale } from "@/lib/i18n";
import { t } from "@/lib/i18n";
import styles from "./CreateEventSheet.module.css";

const DATE_LOCALES = {
  en: enUS,
  "zh-Hans": zhCN,
  "zh-Hant": zhTW,
} as const;

export interface CreateEventValues {
  title: string;
  notes: string;
  dueDate: string;
  dueTime: string;
  durationMinutes: string;
  isAllDay: boolean;
  involvedIds: string[];
  recurrence: string;
  attachmentFiles: File[];
  reminder: string;
  priority: "urgent" | "normal";
  emergencyPhone: string;
  locationName: string;
  cost: string;
  financeDetail: string;
}

type ReminderKey = "none" | "atTime" | "5" | "15" | "30" | "60";

const REMINDER_OFFSETS: Record<ReminderKey, number[] | null> = {
  none: null,
  atTime: [0],
  "5": [5],
  "15": [15],
  "30": [30],
  "60": [60],
};

export function reminderOffsetsFromKey(key: string): number[] | null {
  return REMINDER_OFFSETS[key as ReminderKey] ?? [15];
}

interface CreateEventSheetProps {
  open: boolean;
  busy: boolean;
  locale: AppLocale;
  roster: RosterEntry[];
  myMembershipId: string | null;
  initial: Omit<CreateEventValues, "attachmentFiles">;
  onClose: () => void;
  onSubmit: (values: CreateEventValues) => void | Promise<void>;
}

function minutesToDurationInput(minutes: number): string {
  const h = Math.floor(Math.max(0, minutes) / 60);
  const m = Math.max(0, minutes) % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

function durationInputToMinutes(value: string): number {
  const [hRaw, mRaw] = value.split(":");
  const h = Number(hRaw);
  const m = Number(mRaw);
  if (!Number.isFinite(h) || !Number.isFinite(m)) return 60;
  return Math.max(5, h * 60 + m);
}

function initialLetter(name: string): string {
  const trimmed = name.trim();
  return trimmed ? trimmed.slice(0, 1).toUpperCase() : "?";
}

export function CreateEventSheet({
  open,
  busy,
  locale,
  roster,
  myMembershipId,
  initial,
  onClose,
  onSubmit,
}: CreateEventSheetProps) {
  const strings = t(locale);
  const fileRef = useRef<HTMLInputElement>(null);

  const [title, setTitle] = useState(initial.title);
  const [notes, setNotes] = useState(initial.notes);
  const [dueDate, setDueDate] = useState(initial.dueDate);
  const [dueTime, setDueTime] = useState(initial.dueTime);
  const [durationMinutes, setDurationMinutes] = useState(initial.durationMinutes);
  const [isAllDay, setIsAllDay] = useState(initial.isAllDay);
  const [involvedIds, setInvolvedIds] = useState<string[]>(initial.involvedIds);
  const [recurrence, setRecurrence] = useState(initial.recurrence);
  const [showMore, setShowMore] = useState(false);
  const [attachmentFiles, setAttachmentFiles] = useState<File[]>([]);
  const [reminder, setReminder] = useState(initial.reminder);
  const [priority, setPriority] = useState<"urgent" | "normal">(initial.priority);
  const [emergencyPhone, setEmergencyPhone] = useState(initial.emergencyPhone);
  const [locationName, setLocationName] = useState(initial.locationName);
  const [cost, setCost] = useState(initial.cost);
  const [financeDetail, setFinanceDetail] = useState(initial.financeDetail);

  useEffect(() => {
    if (!open) return;
    setTitle(initial.title);
    setNotes(initial.notes);
    setDueDate(initial.dueDate);
    setDueTime(initial.dueTime);
    setDurationMinutes(initial.durationMinutes);
    setIsAllDay(initial.isAllDay);
    setInvolvedIds(initial.involvedIds);
    setRecurrence(initial.recurrence);
    setShowMore(false);
    setAttachmentFiles([]);
    setReminder(initial.reminder);
    setPriority(initial.priority);
    setEmergencyPhone(initial.emergencyPhone);
    setLocationName(initial.locationName);
    setCost(initial.cost);
    setFinanceDetail(initial.financeDetail);
  }, [open, initial]);

  const canSave = title.trim().length > 0 && !busy;

  const datePillLabel = useMemo(() => {
    try {
      const date = new Date(`${dueDate}T12:00:00`);
      return format(date, "MMM d, yyyy", { locale: DATE_LOCALES[locale] });
    } catch {
      return dueDate;
    }
  }, [dueDate, locale]);

  const durationValue = minutesToDurationInput(Number(durationMinutes) || 60);

  const everyoneSelected = involvedIds.length === 0;
  const meSelected =
    Boolean(myMembershipId) &&
    involvedIds.length === 1 &&
    involvedIds[0] === myMembershipId;

  function selectEveryone() {
    setInvolvedIds([]);
  }

  function selectMe() {
    if (!myMembershipId) return;
    setInvolvedIds([myMembershipId]);
  }

  function toggleMember(membershipId: string) {
    setInvolvedIds((prev) => {
      if (prev.includes(membershipId)) {
        return prev.filter((id) => id !== membershipId);
      }
      return [...prev, membershipId];
    });
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!canSave) return;
    await onSubmit({
      title: title.trim(),
      notes,
      dueDate,
      dueTime,
      durationMinutes: String(durationInputToMinutes(durationValue)),
      isAllDay,
      involvedIds,
      recurrence,
      attachmentFiles,
      reminder,
      priority,
      emergencyPhone,
      locationName,
      cost,
      financeDetail,
    });
  }

  const reminderLabel =
    reminder === "none"
      ? strings.remindNone
      : reminder === "atTime"
        ? strings.remindOnTime
        : reminder === "5"
          ? strings.remind5Min
          : reminder === "30"
            ? strings.remind30Min
            : reminder === "60"
              ? strings.remind1Hour
              : strings.remind15Min;

  const recurrenceLabel =
    recurrence === "daily"
      ? strings.repeatDaily
      : recurrence === "weekly"
        ? strings.repeatWeekly
        : recurrence === "monthly"
          ? strings.repeatMonthly
          : strings.doesNotRepeat;

  return (
    <Sheet
      open={open}
      onClose={onClose}
      variant="dark"
      header={
        <div className={styles.nav}>
          <button type="button" className={styles.navBtn} onClick={onClose} disabled={busy}>
            {strings.cancel}
          </button>
          <h2 className={styles.navTitle}>{strings.newEvent}</h2>
          <button
            type="submit"
            form="create-event-form"
            className={[styles.navBtn, styles.navSave, canSave ? styles.navSaveReady : ""].filter(Boolean).join(" ")}
            disabled={!canSave}
          >
            {strings.save}
          </button>
        </div>
      }
    >
      <form id="create-event-form" className={styles.form} onSubmit={(e) => void handleSubmit(e)}>
        <section className={styles.card}>
          <textarea
            className={styles.titleInput}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder={strings.whatWouldYouLikeToDo}
            rows={3}
            required
          />
          <button
            type="button"
            className={styles.attachBtn}
            onClick={() => fileRef.current?.click()}
          >
            <PaperclipIcon />
            {strings.addAttachment}
            {attachmentFiles.length > 0 ? ` (${attachmentFiles.length})` : ""}
          </button>
          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            multiple
            className={styles.hiddenFile}
            onChange={(e) => {
              const files = e.target.files ? Array.from(e.target.files) : [];
              setAttachmentFiles(files);
              e.target.value = "";
            }}
          />
        </section>

        <section className={styles.card}>
          <p className={styles.sectionLabel}>{strings.timeSetting}</p>

          <div className={styles.row}>
            <span className={styles.rowLabel}>{strings.allDay}</span>
            <label className={styles.switch}>
              <input
                type="checkbox"
                checked={isAllDay}
                onChange={(e) => setIsAllDay(e.target.checked)}
              />
              <span className={styles.switchTrack} />
            </label>
          </div>

          <div className={styles.row}>
            <span className={styles.rowLabelWithIcon}>
              <CalendarIcon />
              {strings.executionTime}
            </span>
            <div className={styles.pillGroup}>
              <label className={styles.pill}>
                <span>{datePillLabel}</span>
                <input
                  type="date"
                  value={dueDate}
                  onChange={(e) => setDueDate(e.target.value)}
                  required
                />
              </label>
              {!isAllDay ? (
                <label className={styles.pill}>
                  <span>{dueTime}</span>
                  <input
                    type="time"
                    value={dueTime}
                    onChange={(e) => setDueTime(e.target.value)}
                    required
                  />
                </label>
              ) : null}
            </div>
          </div>

          <div className={styles.row}>
            <span className={styles.rowLabelWithIcon}>
              <HourglassIcon />
              {strings.duration}
            </span>
            <label className={styles.pill}>
              <span>{durationValue}</span>
              <input
                type="time"
                value={durationValue}
                onChange={(e) =>
                  setDurationMinutes(String(durationInputToMinutes(e.target.value || "01:00")))
                }
              />
            </label>
          </div>
        </section>

        <section className={styles.card}>
          <div className={styles.row}>
            <span className={styles.rowLabel}>{strings.repeat}</span>
            <label className={styles.repeatControl}>
              <span>{recurrenceLabel}</span>
              <ChevronSwapIcon />
              <select
                value={recurrence}
                onChange={(e) => setRecurrence(e.target.value)}
                aria-label={strings.repeat}
              >
                <option value="none">{strings.doesNotRepeat}</option>
                <option value="daily">{strings.repeatDaily}</option>
                <option value="weekly">{strings.repeatWeekly}</option>
                <option value="monthly">{strings.repeatMonthly}</option>
              </select>
            </label>
          </div>
        </section>

        <section className={styles.forWhom}>
          <p className={styles.sectionLabel}>{strings.forWhom}</p>
          {renderAssigneeAvatars()}
        </section>

        {!showMore ? (
          <button type="button" className={styles.moreBtn} onClick={() => setShowMore(true)}>
            {strings.showMoreOptions}
            <span className={styles.chevronDown}>▾</span>
          </button>
        ) : (
          <>
            <section className={styles.card}>
              <div className={styles.row}>
                <span className={styles.rowLabel}>{strings.remind}</span>
                <label className={styles.repeatControl}>
                  <span>{reminderLabel}</span>
                  <ChevronSwapIcon />
                  <select
                    value={reminder}
                    onChange={(e) => setReminder(e.target.value)}
                    aria-label={strings.remind}
                  >
                    <option value="none">{strings.remindNone}</option>
                    <option value="atTime">{strings.remindOnTime}</option>
                    <option value="5">{strings.remind5Min}</option>
                    <option value="15">{strings.remind15Min}</option>
                    <option value="30">{strings.remind30Min}</option>
                    <option value="60">{strings.remind1Hour}</option>
                  </select>
                </label>
              </div>

              <div className={styles.divider} />

              <p className={styles.sectionLabel}>{strings.taskPriority}</p>
              <div className={styles.prioritySeg} role="radiogroup" aria-label={strings.taskPriority}>
                <button
                  type="button"
                  role="radio"
                  aria-checked={priority === "urgent"}
                  className={[styles.priorityOpt, priority === "urgent" ? styles.priorityOptOn : ""]
                    .filter(Boolean)
                    .join(" ")}
                  onClick={() => setPriority("urgent")}
                >
                  <span className={styles.urgentDot} aria-hidden />
                  {strings.urgent}
                </button>
                <button
                  type="button"
                  role="radio"
                  aria-checked={priority === "normal"}
                  className={[styles.priorityOpt, priority === "normal" ? styles.priorityOptOn : ""]
                    .filter(Boolean)
                    .join(" ")}
                  onClick={() => setPriority("normal")}
                >
                  {strings.generally}
                </button>
              </div>
            </section>

            <section className={styles.card}>
              <p className={styles.sectionLabel}>{strings.emergencyContact}</p>
              <div className={styles.emergencyRow}>
                <input
                  className={styles.plainInput}
                  value={emergencyPhone}
                  onChange={(e) => setEmergencyPhone(e.target.value)}
                  placeholder={strings.enterNumberOrLink}
                  inputMode="tel"
                />
                <span className={styles.contactIcon} aria-hidden>
                  <ContactIcon />
                </span>
              </div>
            </section>

            <section className={styles.card}>
              <p className={styles.sectionLabel}>{strings.assignee}</p>
              <div className={styles.assigneeBox}>{renderAssigneeAvatars()}</div>
            </section>

            <section className={styles.card}>
              <label className={styles.locationRow}>
                <PinIcon />
                <input
                  className={styles.plainInput}
                  value={locationName}
                  onChange={(e) => setLocationName(e.target.value)}
                  placeholder={strings.searchOrAddLocation}
                />
                <span className={styles.chevronRight} aria-hidden>
                  ›
                </span>
              </label>
            </section>

            <section className={styles.card}>
              <p className={styles.sectionLabel}>{strings.moreDetails}</p>
              <textarea
                className={styles.notesInput}
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                rows={3}
                placeholder={strings.addNote}
              />
            </section>

            <section className={styles.card}>
              <p className={styles.sectionLabel}>{strings.financeAndNotes}</p>
              <div className={styles.expenseRow}>
                <span className={styles.rowLabelWithIcon}>
                  <BanknoteIcon />
                  {strings.expenses}
                </span>
                <div className={styles.costField}>
                  <span className={styles.currency}>HK$</span>
                  <input
                    className={styles.costInput}
                    value={cost}
                    onChange={(e) => setCost(e.target.value.replace(/[^\d.]/g, ""))}
                    inputMode="decimal"
                    placeholder="0"
                  />
                </div>
              </div>
              <p className={styles.sectionLabel}>{strings.detailedDescription}</p>
              <textarea
                className={styles.notesInput}
                value={financeDetail}
                onChange={(e) => setFinanceDetail(e.target.value)}
                rows={3}
                placeholder={strings.expenseDetailsPlaceholder}
              />
            </section>

            <button type="button" className={styles.moreBtn} onClick={() => setShowMore(false)}>
              {strings.hideMoreOptions}
              <span className={styles.chevronUp}>▾</span>
            </button>
          </>
        )}
      </form>
    </Sheet>
  );

  function renderAssigneeAvatars() {
    return (
      <div className={styles.avatarRow}>
        <button type="button" className={styles.avatarItem} onClick={selectEveryone}>
          <span
            className={[
              styles.avatarCircle,
              styles.avatarEveryone,
              everyoneSelected ? styles.avatarSelected : "",
            ]
              .filter(Boolean)
              .join(" ")}
          >
            <PeopleIcon />
            {everyoneSelected ? <span className={styles.checkBadge}>✓</span> : null}
          </span>
          <span className={styles.avatarName}>{strings.everyone}</span>
        </button>

        {myMembershipId ? (
          <button type="button" className={styles.avatarItem} onClick={selectMe}>
            <span
              className={[styles.avatarCircle, meSelected ? styles.avatarSelected : ""]
                .filter(Boolean)
                .join(" ")}
            >
              {initialLetter(strings.me)}
              {meSelected ? <span className={styles.checkBadge}>✓</span> : null}
            </span>
            <span className={styles.avatarName}>{strings.me}</span>
          </button>
        ) : null}

        {roster
          .filter((entry) => entry.membership.id !== myMembershipId)
          .map((entry) => {
            const mid = entry.membership.id;
            const label =
              entry.profile?.display_name ?? entry.membership.display_name ?? "Member";
            const on = involvedIds.includes(mid);
            return (
              <button
                key={mid}
                type="button"
                className={styles.avatarItem}
                onClick={() => toggleMember(mid)}
              >
                <span
                  className={[styles.avatarCircle, on ? styles.avatarSelected : ""]
                    .filter(Boolean)
                    .join(" ")}
                >
                  {initialLetter(label)}
                  {on ? <span className={styles.checkBadge}>✓</span> : null}
                </span>
                <span className={styles.avatarName}>{label}</span>
              </button>
            );
          })}
      </div>
    );
  }
}

function PaperclipIcon() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" aria-hidden>
      <path
        d="M8.5 12.5 14 7a3 3 0 1 1 4.2 4.2l-7.4 7.4a4.5 4.5 0 0 1-6.4-6.4l7.1-7.1"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
    </svg>
  );
}

function CalendarIcon() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" aria-hidden>
      <rect x="3.5" y="5" width="17" height="15" rx="2.5" stroke="currentColor" strokeWidth="1.6" />
      <path d="M8 3.5v3M16 3.5v3M3.5 10h17" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}

function HourglassIcon() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" aria-hidden>
      <path
        d="M7 4h10M7 20h10M8 4c0 4 3 5 4 8-1 3-4 4-4 8M16 4c0 4-3 5-4 8 1 3 4 4 4 8"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function ChevronSwapIcon() {
  return (
    <svg viewBox="0 0 24 24" width="12" height="12" fill="none" aria-hidden>
      <path d="M8 9l4-4 4 4M8 15l4 4 4-4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function PeopleIcon() {
  return (
    <svg viewBox="0 0 24 24" width="20" height="20" fill="none" aria-hidden>
      <circle cx="9" cy="9" r="3" stroke="currentColor" strokeWidth="1.7" />
      <circle cx="16.5" cy="10" r="2.4" stroke="currentColor" strokeWidth="1.7" />
      <path
        d="M4.5 18c.8-2.4 2.8-3.6 4.5-3.6S12.7 15.6 13.5 18M14 16.5c1.1-.7 2.4-1 3.5-.6.9.3 1.7 1 2.2 2.1"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
      />
    </svg>
  );
}

function ContactIcon() {
  return (
    <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor" aria-hidden>
      <circle cx="12" cy="12" r="10" opacity="0.2" />
      <circle cx="12" cy="10" r="3.2" />
      <path d="M6.5 18.2c1.2-2.4 3.2-3.6 5.5-3.6s4.3 1.2 5.5 3.6" />
    </svg>
  );
}

function PinIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="none" aria-hidden>
      <path
        d="M12 21s6-5.2 6-10a6 6 0 1 0-12 0c0 4.8 6 10 6 10Z"
        stroke="currentColor"
        strokeWidth="1.7"
      />
      <circle cx="12" cy="11" r="2.2" stroke="currentColor" strokeWidth="1.7" />
    </svg>
  );
}

function BanknoteIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="none" aria-hidden>
      <rect x="3" y="6" width="18" height="12" rx="2" stroke="currentColor" strokeWidth="1.6" />
      <circle cx="12" cy="12" r="2.2" stroke="currentColor" strokeWidth="1.6" />
      <path d="M6 9.5h1.5M16.5 14.5H18" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}
