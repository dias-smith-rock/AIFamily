"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { addMonths, startOfMonth } from "date-fns";
import {
  createCategory,
  createTransaction,
  deleteTransaction,
  ensurePresets,
  fetchCategories,
  fetchTransactions,
  softDeleteCategory,
  updateSortOrders,
} from "@/lib/api/ledger";
import { fetchRoster, type RosterEntry } from "@/lib/api/members";
import { formatMonthLabel, isInMonth } from "@/lib/date-utils";
import { useHousehold } from "@/lib/household-context";
import { t } from "@/lib/i18n";
import type { ExpenseCategory, LedgerEntryType, LedgerTransaction } from "@/lib/types";
import { LedgerReportsSheet } from "@/components/LedgerReportsSheet";
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
import styles from "./wallet.module.css";

function formatMoney(amount: number, currency = "HKD"): string {
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency,
    maximumFractionDigits: 0,
  }).format(amount);
}

function canRecordExpense(role: string): boolean {
  return role === "creator" || role === "admin";
}

export default function WalletPage() {
  const { session, locale, loading: sessionLoading } = useHousehold();
  const strings = t(locale);

  const [month, setMonth] = useState(() => startOfMonth(new Date()));
  const [entryType, setEntryType] = useState<LedgerEntryType>("expense");
  const [categories, setCategories] = useState<ExpenseCategory[]>([]);
  const [transactions, setTransactions] = useState<LedgerTransaction[]>([]);
  const [roster, setRoster] = useState<RosterEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [entryOpen, setEntryOpen] = useState(false);
  const [manageOpen, setManageOpen] = useState(false);
  const [txOpen, setTxOpen] = useState(false);
  const [reportsOpen, setReportsOpen] = useState(false);
  const [selectedCategory, setSelectedCategory] = useState<ExpenseCategory | null>(null);

  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [categoryId, setCategoryId] = useState<string | null>(null);
  const [newCategoryName, setNewCategoryName] = useState("");

  const expenseAllowed = session ? canRecordExpense(session.role) : false;

  const loadData = useCallback(async () => {
    if (!session?.householdId) {
      setCategories([]);
      setTransactions([]);
      setRoster([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      await ensurePresets(session.householdId);
      const [cats, txs, members] = await Promise.all([
        fetchCategories(session.householdId),
        fetchTransactions(session.householdId),
        fetchRoster(session.householdId),
      ]);
      setCategories(cats);
      setTransactions(txs);
      setRoster(members);
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setLoading(false);
    }
  }, [session?.householdId, strings.error]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  useEffect(() => {
    if (!expenseAllowed && entryType === "expense") {
      setEntryType("income");
    }
  }, [expenseAllowed, entryType]);

  useEffect(() => {
    if (!entryOpen) return;
    const first = categories.find((c) => c.type === entryType);
    setCategoryId(first?.id ?? null);
  }, [entryOpen, entryType, categories]);

  const monthTransactions = useMemo(
    () => transactions.filter((tx) => isInMonth(tx.transaction_time, month)),
    [transactions, month]
  );

  const summary = useMemo(() => {
    let expense = 0;
    let income = 0;
    for (const tx of monthTransactions) {
      if (tx.type === "expense") expense += tx.amount;
      else income += tx.amount;
    }
    return { expense, income, net: income - expense };
  }, [monthTransactions]);

  const filteredCategories = useMemo(
    () => categories.filter((c) => c.type === entryType).sort((a, b) => a.sort_order - b.sort_order),
    [categories, entryType]
  );

  const categoryTotals = useMemo(() => {
    const totals = new Map<string, number>();
    for (const tx of monthTransactions) {
      if (tx.type !== entryType || !tx.category_id) continue;
      totals.set(tx.category_id, (totals.get(tx.category_id) ?? 0) + tx.amount);
    }
    return totals;
  }, [monthTransactions, entryType]);

  const categoryTransactions = useMemo(() => {
    if (!selectedCategory) return [];
    return monthTransactions
      .filter((tx) => tx.category_id === selectedCategory.id)
      .sort((a, b) => b.transaction_time.localeCompare(a.transaction_time));
  }, [monthTransactions, selectedCategory]);

  function openEntry(type: LedgerEntryType) {
    if (type === "expense" && !expenseAllowed) return;
    setEntryType(type);
    setAmount("");
    setNote("");
    const first = categories.find((c) => c.type === type);
    setCategoryId(first?.id ?? null);
    setEntryOpen(true);
  }

  async function onCreateEntry(e: FormEvent) {
    e.preventDefault();
    if (!session?.householdId || !session.profileId) return;

    const category = categories.find((c) => c.id === categoryId);
    if (!category) {
      setError("Select a category");
      return;
    }

    const parsed = Number(amount);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      setError("Enter a valid amount");
      return;
    }

    setBusy(true);
    setError(null);
    try {
      await createTransaction({
        householdId: session.householdId,
        creatorProfileId: session.profileId,
        type: entryType,
        amount: parsed,
        categoryId: category.id,
        categoryNameSnapshot: category.name,
        categoryIconSnapshot: category.icon,
        payerIds: [session.profileId],
        note: note.trim() || null,
      });
      setEntryOpen(false);
      await loadData();
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  async function onAddCategory(e: FormEvent) {
    e.preventDefault();
    if (!session?.householdId || !newCategoryName.trim()) return;

    setBusy(true);
    setError(null);
    try {
      await createCategory({
        householdId: session.householdId,
        type: entryType,
        name: newCategoryName.trim(),
        sortOrder: (filteredCategories.at(-1)?.sort_order ?? 100) + 10,
      });
      setNewCategoryName("");
      await loadData();
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  async function onDeleteCategory(id: string) {
    if (!window.confirm(strings.delete + "?")) return;
    setBusy(true);
    try {
      await softDeleteCategory(id);
      await loadData();
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  async function moveCategory(id: string, direction: -1 | 1) {
    const list = [...filteredCategories];
    const index = list.findIndex((c) => c.id === id);
    const swapIndex = index + direction;
    if (index < 0 || swapIndex < 0 || swapIndex >= list.length) return;

    [list[index], list[swapIndex]] = [list[swapIndex], list[index]];
    const orders = list.map((c, i) => ({ id: c.id, sortOrder: (i + 1) * 10 }));

    setBusy(true);
    try {
      await updateSortOrders(orders);
      await loadData();
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  async function onDeleteTransaction(id: string) {
    if (!window.confirm(strings.delete + "?")) return;
    setBusy(true);
    try {
      await deleteTransaction(id);
      await loadData();
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
    return <Empty title={strings.noOrgSelected} />;
  }

  if (!session.profileId) {
    return (
      <div className={styles.page}>
        <h1 className={styles.title}>{strings.tabWallet}</h1>
        <p className={styles.notice}>
          Link your family profile in Settings before recording wallet entries on the web.
        </p>
      </div>
    );
  }

  return (
    <div className={styles.page}>
      <h1 className={styles.title}>{strings.tabWallet}</h1>

      <div className={styles.monthNav}>
        <IconButton label="Previous month" onClick={() => setMonth((m) => addMonths(m, -1))}>
          ‹
        </IconButton>
        <p className={styles.monthLabel}>{formatMonthLabel(month, locale)}</p>
        <IconButton label="Next month" onClick={() => setMonth((m) => addMonths(m, 1))}>
          ›
        </IconButton>
      </div>

      <div className={styles.summary}>
        <div className={styles.summaryCard}>
          <p className={styles.summaryLabel}>Expense</p>
          <p className={[styles.summaryValue, styles.expenseValue].join(" ")}>
            {formatMoney(summary.expense)}
          </p>
        </div>
        <div className={styles.summaryCard}>
          <p className={styles.summaryLabel}>Income</p>
          <p className={[styles.summaryValue, styles.incomeValue].join(" ")}>
            {formatMoney(summary.income)}
          </p>
        </div>
        <div className={styles.summaryCard}>
          <p className={styles.summaryLabel}>Net</p>
          <p className={styles.summaryValue}>{formatMoney(summary.net)}</p>
        </div>
      </div>

      <div className={styles.toolbar}>
        <Segmented
          options={
            expenseAllowed
              ? [
                  { value: "expense" as const, label: "Expense" },
                  { value: "income" as const, label: "Income" },
                ]
              : [{ value: "income" as const, label: "Income" }]
          }
          value={entryType}
          onChange={setEntryType}
        />
        <Button variant="secondary" onClick={() => setReportsOpen(true)}>
          Reports
        </Button>
        <Button variant="secondary" onClick={() => setManageOpen(true)}>
          Categories
        </Button>
      </div>

      {!expenseAllowed ? (
        <p className={styles.notice}>Members can record income only. Expenses require admin or creator.</p>
      ) : null}

      {error ? <p className={styles.error}>{error}</p> : null}

      {loading ? (
        <div className={styles.center}>
          <Spinner />
        </div>
      ) : filteredCategories.length === 0 ? (
        <Empty title={strings.emptyWallet} />
      ) : (
        <div className={styles.categoryGrid}>
          {filteredCategories.map((category) => (
            <button
              key={category.id}
              type="button"
              className={styles.categoryCard}
              onClick={() => {
                setSelectedCategory(category);
                setTxOpen(true);
              }}
            >
              <span className={styles.categoryIcon}>{category.icon}</span>
              <p className={styles.categoryName}>{category.name}</p>
              <p className={styles.categoryTotal}>
                {formatMoney(categoryTotals.get(category.id) ?? 0)}
              </p>
            </button>
          ))}
        </div>
      )}

      <button
        type="button"
        className={styles.fab}
        aria-label={strings.create}
        onClick={() => openEntry(entryType)}
      >
        +
      </button>

      <Sheet open={entryOpen} onClose={() => setEntryOpen(false)} title="Manual entry">
        <form className={styles.form} onSubmit={onCreateEntry}>
          <Segmented
            options={
              expenseAllowed
                ? [
                    { value: "expense" as const, label: "Expense" },
                    { value: "income" as const, label: "Income" },
                  ]
                : [{ value: "income" as const, label: "Income" }]
            }
            value={entryType}
            onChange={setEntryType}
          />
          <Input
            label="Amount"
            type="number"
            min={0}
            step={1}
            inputMode="decimal"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            required
          />
          <div>
            <p className={styles.summaryLabel}>Category</p>
            <div className={styles.categoryPicker}>
              {categories
                .filter((c) => c.type === entryType)
                .map((c) => (
                  <button
                    key={c.id}
                    type="button"
                    className={[
                      styles.categoryChip,
                      categoryId === c.id ? styles.categoryChipActive : "",
                    ]
                      .filter(Boolean)
                      .join(" ")}
                    onClick={() => setCategoryId(c.id)}
                  >
                    {c.icon} {c.name}
                  </button>
                ))}
            </div>
          </div>
          <TextArea label="Note" value={note} onChange={(e) => setNote(e.target.value)} rows={2} />
          <Button fullWidth type="submit" loading={busy}>
            {strings.save}
          </Button>
        </form>
      </Sheet>

      <Sheet open={manageOpen} onClose={() => setManageOpen(false)} title="Manage categories">
        <div className={styles.form}>
          <Segmented
            options={
              expenseAllowed
                ? [
                    { value: "expense" as const, label: "Expense" },
                    { value: "income" as const, label: "Income" },
                  ]
                : [{ value: "income" as const, label: "Income" }]
            }
            value={entryType}
            onChange={setEntryType}
          />
          <div className={styles.manageList}>
            {filteredCategories.map((category) => (
              <div key={category.id} className={styles.manageRow}>
                <span>{category.icon}</span>
                <span className={styles.manageName}>{category.name}</span>
                <IconButton label="Move up" onClick={() => void moveCategory(category.id, -1)}>
                  ↑
                </IconButton>
                <IconButton label="Move down" onClick={() => void moveCategory(category.id, 1)}>
                  ↓
                </IconButton>
                {!category.is_preset ? (
                  <IconButton label="Delete" onClick={() => void onDeleteCategory(category.id)}>
                    ✕
                  </IconButton>
                ) : null}
              </div>
            ))}
          </div>
          <form className={styles.form} onSubmit={onAddCategory}>
            <Input
              label="New category"
              value={newCategoryName}
              onChange={(e) => setNewCategoryName(e.target.value)}
              placeholder="Category name"
            />
            <Button fullWidth type="submit" loading={busy} disabled={!newCategoryName.trim()}>
              Add category
            </Button>
          </form>
        </div>
      </Sheet>

      <Sheet
        open={txOpen}
        onClose={() => {
          setTxOpen(false);
          setSelectedCategory(null);
        }}
        title={selectedCategory?.name ?? "Transactions"}
      >
        <div className={styles.txList}>
          {categoryTransactions.length === 0 ? (
            <Empty title="No transactions this month" />
          ) : (
            categoryTransactions.map((tx) => (
              <div key={tx.id} className={styles.txRow}>
                <div>
                  <p>{formatMoney(tx.amount, tx.currency)}</p>
                  {tx.note ? <p className={styles.txNote}>{tx.note}</p> : null}
                </div>
                <Button variant="ghost" onClick={() => void onDeleteTransaction(tx.id)} disabled={busy}>
                  {strings.delete}
                </Button>
              </div>
            ))
          )}
        </div>
      </Sheet>

      <LedgerReportsSheet
        open={reportsOpen}
        onClose={() => setReportsOpen(false)}
        locale={locale}
        transactions={transactions}
        categories={categories}
        roster={roster}
        title="Reports"
      />
    </div>
  );
}
