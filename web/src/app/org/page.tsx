"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  createHousehold,
  joinHousehold,
  listMyMemberships,
  type MembershipWithHousehold,
} from "@/lib/api/households";
import { Button, Card, Input, Sheet, TextArea, Spinner } from "@/components/ui";
import styles from "./org.module.css";

export default function OrgPage() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [rows, setRows] = useState<MembershipWithHousehold[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [joinOpen, setJoinOpen] = useState(false);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);

  async function refresh() {
    setLoading(true);
    setError(null);
    try {
      const list = await listMyMemberships();
      setRows(list);
      if (list.length === 1) {
        localStorage.setItem("wesync.selectedHouseholdId", list[0].household_id);
        router.replace("/app/calendar");
        return;
      }
      const saved = localStorage.getItem("wesync.selectedHouseholdId");
      if (saved && list.some((r) => r.household_id === saved)) {
        router.replace("/app/calendar");
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load groups");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void refresh();
  }, []);

  function enterHousehold(id: string) {
    localStorage.setItem("wesync.selectedHouseholdId", id);
    router.push("/app/calendar");
  }

  async function onCreate(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const id = await createHousehold(name, description || null);
      localStorage.setItem("wesync.selectedHouseholdId", id);
      router.push("/app/calendar");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Create failed");
    } finally {
      setBusy(false);
    }
  }

  async function onJoin(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const id = await joinHousehold(code);
      localStorage.setItem("wesync.selectedHouseholdId", id);
      router.push("/app/calendar");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Join failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <h1>你的群组</h1>
        <p>创建新群组，或用邀请码加入。与 iOS App 同一账号、同一数据。</p>
      </header>

      {loading ? (
        <div className={styles.center}>
          <Spinner />
        </div>
      ) : (
        <div className={styles.list}>
          {rows.map((row) => (
            <button
              key={row.id}
              type="button"
              className={styles.row}
              onClick={() => enterHousehold(row.household_id)}
            >
              <span className={styles.rowName}>{row.household?.name ?? "Group"}</span>
              <span className={styles.rowMeta}>{row.role}</span>
            </button>
          ))}
          {rows.length === 0 ? (
            <Card>
              <p className={styles.empty}>还没有群组。先创建一个，或输入邀请码加入。</p>
            </Card>
          ) : null}
        </div>
      )}

      {error ? <p className={styles.error}>{error}</p> : null}

      <div className={styles.actions}>
        <Button fullWidth onClick={() => setCreateOpen(true)}>
          创建群组
        </Button>
        <Button fullWidth variant="secondary" onClick={() => setJoinOpen(true)}>
          加入群组
        </Button>
      </div>

      <Sheet open={createOpen} onClose={() => setCreateOpen(false)} title="创建群组">
        <form className={styles.form} onSubmit={onCreate}>
          <Input
            label="群组名称"
            value={name}
            onChange={(e) => setName(e.target.value)}
            required
            placeholder="例如：高家 / Trip Kyoto"
          />
          <TextArea
            label="简介（可选）"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={3}
          />
          <Button fullWidth type="submit" disabled={busy || !name.trim()}>
            {busy ? "创建中…" : "创建"}
          </Button>
        </form>
      </Sheet>

      <Sheet open={joinOpen} onClose={() => setJoinOpen(false)} title="加入群组">
        <form className={styles.form} onSubmit={onJoin}>
          <Input
            label="邀请码"
            value={code}
            onChange={(e) => setCode(e.target.value.toUpperCase())}
            required
            placeholder="6 位邀请码"
            autoCapitalize="characters"
          />
          <Button fullWidth type="submit" disabled={busy || code.trim().length < 4}>
            {busy ? "加入中…" : "加入"}
          </Button>
        </form>
      </Sheet>
    </div>
  );
}
