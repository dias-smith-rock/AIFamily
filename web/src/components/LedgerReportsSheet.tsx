"use client";

import { useMemo, useState } from "react";
import type { ExpenseCategory, LedgerEntryType, LedgerTransaction } from "@/lib/types";
import type { RosterEntry } from "@/lib/api/members";
import {
  formatReportAnchor,
  isInReportPeriod,
  shiftReportAnchor,
  type ReportPeriod,
} from "@/lib/date-utils";
import type { AppLocale } from "@/lib/i18n";
import { Button, IconButton, Segmented, Sheet } from "@/components/ui";
import styles from "./reports.module.css";

function formatMoney(amount: number, currency = "HKD"): string {
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency,
    maximumFractionDigits: 0,
  }).format(amount);
}

export interface LedgerReportsSheetProps {
  open: boolean;
  onClose: () => void;
  locale: AppLocale;
  transactions: LedgerTransaction[];
  categories: ExpenseCategory[];
  roster: RosterEntry[];
  title: string;
}

export function LedgerReportsSheet({
  open,
  onClose,
  locale,
  transactions,
  categories,
  roster,
  title,
}: LedgerReportsSheetProps) {
  const [period, setPeriod] = useState<ReportPeriod>("month");
  const [anchor, setAnchor] = useState(() => new Date());
  const [payerFilter, setPayerFilter] = useState<string>("all");
  const [targetFilter, setTargetFilter] = useState<string>("all");

  const profiles = useMemo(() => {
    const map = new Map<string, string>();
    for (const entry of roster) {
      if (entry.profile) {
        map.set(
          entry.profile.id,
          entry.profile.display_name || entry.membership.display_name || "Member"
        );
      }
    }
    return [...map.entries()].map(([id, name]) => ({ id, name }));
  }, [roster]);

  const filtered = useMemo(() => {
    return transactions.filter((tx) => {
      if (!isInReportPeriod(tx.transaction_time, period, anchor)) return false;
      if (payerFilter !== "all" && !tx.payer_ids.includes(payerFilter)) return false;
      if (targetFilter !== "all" && !tx.target_member_ids.includes(targetFilter)) return false;
      return true;
    });
  }, [transactions, period, anchor, payerFilter, targetFilter]);

  const expenseTotal = useMemo(
    () => filtered.filter((t) => t.type === "expense").reduce((s, t) => s + t.amount, 0),
    [filtered]
  );
  const incomeTotal = useMemo(
    () => filtered.filter((t) => t.type === "income").reduce((s, t) => s + t.amount, 0),
    [filtered]
  );
  const net = incomeTotal - expenseTotal;

  const breakdown = useMemo(() => {
    const expenses = filtered.filter((t) => t.type === "expense");
    const groups = new Map<string, { name: string; icon: string; amount: number }>();
    for (const tx of expenses) {
      const key = tx.category_id ?? `snap:${tx.category_name_snapshot}`;
      const cat = tx.category_id
        ? categories.find((c) => c.id === tx.category_id)
        : undefined;
      const name = cat?.name ?? tx.category_name_snapshot;
      const icon = cat?.icon ?? tx.category_icon_snapshot ?? "🏷️";
      const prev = groups.get(key);
      groups.set(key, {
        name,
        icon,
        amount: (prev?.amount ?? 0) + tx.amount,
      });
    }
    return [...groups.values()].sort((a, b) => b.amount - a.amount);
  }, [filtered, categories]);

  const maxAmount = breakdown[0]?.amount ?? 1;

  return (
    <Sheet open={open} onClose={onClose} title={title}>
      <div className={styles.root}>
        <Segmented
          options={[
            { value: "day", label: "Day" },
            { value: "week", label: "Week" },
            { value: "month", label: "Month" },
            { value: "year", label: "Year" },
          ]}
          value={period}
          onChange={(v) => setPeriod(v)}
        />

        <div className={styles.nav}>
          <IconButton
            label="Previous"
            onClick={() => setAnchor((a) => shiftReportAnchor(period, a, -1))}
          >
            ‹
          </IconButton>
          <p className={styles.navLabel}>{formatReportAnchor(period, anchor, locale)}</p>
          <IconButton
            label="Next"
            onClick={() => setAnchor((a) => shiftReportAnchor(period, a, 1))}
          >
            ›
          </IconButton>
        </div>

        <div className={styles.filters}>
          <label className={styles.filter}>
            <span>Payer</span>
            <select value={payerFilter} onChange={(e) => setPayerFilter(e.target.value)}>
              <option value="all">All payers</option>
              {profiles.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </label>
          <label className={styles.filter}>
            <span>For whom</span>
            <select value={targetFilter} onChange={(e) => setTargetFilter(e.target.value)}>
              <option value="all">All targets</option>
              {profiles.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </label>
        </div>

        <div className={styles.totals}>
          <div className={styles.tile}>
            <span className={styles.tileLabel}>Expense</span>
            <strong className={styles.expense}>{formatMoney(expenseTotal)}</strong>
          </div>
          <div className={styles.tile}>
            <span className={styles.tileLabel}>Income</span>
            <strong className={styles.income}>{formatMoney(incomeTotal)}</strong>
          </div>
          <div className={styles.tile}>
            <span className={styles.tileLabel}>Net</span>
            <strong>{formatMoney(net)}</strong>
          </div>
        </div>

        <section className={styles.breakdown}>
          <h3>Category breakdown</h3>
          {breakdown.length === 0 ? (
            <p className={styles.empty}>No expense entries in this period.</p>
          ) : (
            <ul className={styles.bars}>
              {breakdown.map((item) => (
                <li key={`${item.name}-${item.icon}`}>
                  <div className={styles.barHead}>
                    <span>
                      {item.icon} {item.name}
                    </span>
                    <span>{formatMoney(item.amount)}</span>
                  </div>
                  <div className={styles.barTrack}>
                    <div
                      className={styles.barFill}
                      style={{ width: `${Math.max(6, (item.amount / maxAmount) * 100)}%` }}
                    />
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>

        <Button fullWidth variant="secondary" onClick={onClose}>
          Close
        </Button>
      </div>
    </Sheet>
  );
}

export type { LedgerEntryType };
