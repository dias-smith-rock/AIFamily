"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { disbandHousehold, leaveHousehold, getOrCreateInviteNonce } from "@/lib/api/households";
import { createVirtualProfile, fetchRoster, type RosterEntry } from "@/lib/api/members";
import { createClient } from "@/lib/supabase/client";
import { useHousehold } from "@/lib/household-context";
import { t, type AppLocale } from "@/lib/i18n";
import { Button, Empty, Input, Sheet, Spinner } from "@/components/ui";
import styles from "./settings.module.css";

const LOCALE_OPTIONS: { value: AppLocale; label: string }[] = [
  { value: "en", label: "English" },
  { value: "zh-Hans", label: "简体中文" },
  { value: "zh-Hant", label: "繁體中文" },
];

export default function SettingsPage() {
  const router = useRouter();
  const {
    session,
    locale,
    setLocale,
    signOut,
    refreshHouseholds,
    loading: sessionLoading,
  } = useHousehold();
  const strings = t(locale);

  const [roster, setRoster] = useState<RosterEntry[]>([]);
  const [inviteCode, setInviteCode] = useState<string | null>(null);
  const [inviteHint, setInviteHint] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [addMemberOpen, setAddMemberOpen] = useState(false);
  const [virtualName, setVirtualName] = useState("");
  const [disbandName, setDisbandName] = useState("");
  const [disbandOpen, setDisbandOpen] = useState(false);

  const loadData = useCallback(async () => {
    if (!session?.householdId) {
      setRoster([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const members = await fetchRoster(session.householdId);
      setRoster(members.filter((m) => m.membership.status === "active"));

      const supabase = createClient();
      const { data, error: inviteError } = await supabase
        .from("invite_link_nonces")
        .select("nonce, expires_at, is_used")
        .eq("household_id", session.householdId)
        .eq("is_used", false)
        .gt("expires_at", new Date().toISOString())
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (inviteError) {
        setInviteCode(null);
        setInviteHint("Generate a fresh invite code in the iOS app (Settings → Invite).");
      } else if (data?.nonce) {
        setInviteCode(String(data.nonce));
        setInviteHint(null);
      } else {
        setInviteCode(null);
        setInviteHint("No active invite code. Open the iOS app to create one or scan a QR invite.");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setLoading(false);
    }
  }, [session?.householdId, strings.error]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  async function onAddVirtualMember(e: FormEvent) {
    e.preventDefault();
    if (!session?.householdId || !virtualName.trim()) return;

    setBusy(true);
    setError(null);
    try {
      await createVirtualProfile(session.householdId, virtualName.trim());
      setVirtualName("");
      setAddMemberOpen(false);
      await loadData();
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  async function onLeave() {
    if (!session?.householdId) return;
    if (!window.confirm(strings.leaveOrg + "?")) return;

    setBusy(true);
    setError(null);
    try {
      await leaveHousehold(session.householdId);
      await refreshHouseholds();
      router.push("/org");
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  async function onDisband(e: FormEvent) {
    e.preventDefault();
    if (!session?.householdId) return;

    setBusy(true);
    setError(null);
    try {
      await disbandHousehold(session.householdId, disbandName);
      setDisbandOpen(false);
      setDisbandName("");
      await refreshHouseholds();
      router.push("/org");
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setBusy(false);
    }
  }

  async function onSignOut() {
    setBusy(true);
    setError(null);
    try {
      await signOut();
      router.push("/login");
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

  const isCreator = session.role === "creator";

  async function generateInvite() {
    if (!session?.householdId || !session.membershipId) return;
    if (session.role !== "creator" && session.role !== "admin") {
      setError("Only admins can create invite codes");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const code = await getOrCreateInviteNonce(session.householdId, session.membershipId);
      setInviteCode(code);
    } catch (e) {
      setError(e instanceof Error ? e.message : strings.error);
    } finally {
      setBusy(false);
    }
  }


  return (
    <div className={styles.page}>
      <h1 className={styles.title}>{strings.tabSettings}</h1>

      {error ? <p className={styles.error}>{error}</p> : null}

      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>Language</h2>
        <div className={styles.localeRow}>
          {LOCALE_OPTIONS.map((option) => (
            <button
              key={option.value}
              type="button"
              className={[
                styles.localeBtn,
                locale === option.value ? styles.localeBtnActive : "",
              ]
                .filter(Boolean)
                .join(" ")}
              onClick={() => setLocale(option.value)}
            >
              {option.label}
            </button>
          ))}
        </div>
      </section>

      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>Session</h2>
        <div className={styles.card}>
          <div className={styles.infoRow}>
            <span className={styles.infoLabel}>{strings.orgName}</span>
            <span className={styles.infoValue}>{session.householdName}</span>
          </div>
          <div className={styles.infoRow}>
            <span className={styles.infoLabel}>Role</span>
            <span className={styles.infoValue}>{session.role}</span>
          </div>
        </div>
      </section>

      <section className={styles.section}>
        <div className={styles.infoRow}>
          <h2 className={styles.sectionTitle}>{strings.inviteCode}</h2>
          <Button variant="secondary" onClick={() => setAddMemberOpen(true)}>
            Add virtual member
          </Button>
        </div>
        <div className={styles.card}>
          <Button fullWidth variant="secondary" onClick={() => void generateInvite()} disabled={busy}>
            Generate / refresh invite code
          </Button>
          {inviteCode ? (
            <p className={styles.inviteCode}>{inviteCode}</p>
          ) : (
            <p className={styles.hint}>{inviteHint ?? "Invite code unavailable."}</p>
          )}
        </div>
      </section>

      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>Members</h2>
        {loading ? (
          <div className={styles.center}>
            <Spinner />
          </div>
        ) : roster.length === 0 ? (
          <Empty title={strings.emptyMembers} />
        ) : (
          roster.map((entry) => (
            <div key={entry.membership.id} className={styles.memberRow}>
              <span className={styles.memberName}>
                {entry.profile?.display_name ?? entry.membership.display_name ?? "Member"}
              </span>
              <span className={styles.memberRole}>{entry.membership.role}</span>
            </div>
          ))
        )}
      </section>

      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>Links</h2>
        <div className={styles.links}>
          <a className={styles.link} href={process.env.NEXT_PUBLIC_APP_STORE_URL ?? "https://apps.apple.com/app/id6775353963"} target="_blank" rel="noopener noreferrer">
            Download on the App Store
          </a>
          <a className={styles.link} href="https://www.wefamily.ai" target="_blank" rel="noopener noreferrer">
            www.wefamily.ai
          </a>
        </div>
      </section>

      <div className={styles.actions}>
        {!isCreator ? (
          <Button variant="destructive" fullWidth onClick={() => void onLeave()} loading={busy}>
            {strings.leaveOrg}
          </Button>
        ) : (
          <Button variant="destructive" fullWidth onClick={() => setDisbandOpen(true)} disabled={busy}>
            {strings.disbandOrg}
          </Button>
        )}
        <Button variant="secondary" fullWidth onClick={() => void onSignOut()} loading={busy}>
          {strings.signOut}
        </Button>
      </div>

      <Sheet open={addMemberOpen} onClose={() => setAddMemberOpen(false)} title="Add virtual member">
        <form className={styles.form} onSubmit={onAddVirtualMember}>
          <Input
            label="Display name"
            value={virtualName}
            onChange={(e) => setVirtualName(e.target.value)}
            required
            placeholder="Grandma, Dog walker…"
          />
          <Button fullWidth type="submit" loading={busy} disabled={!virtualName.trim()}>
            {strings.create}
          </Button>
        </form>
      </Sheet>

      <Sheet open={disbandOpen} onClose={() => setDisbandOpen(false)} title={strings.disbandOrg}>
        <form className={styles.form} onSubmit={onDisband}>
          <p className={styles.hint}>
            Type <strong>{session.householdName}</strong> to confirm disbanding this household.
          </p>
          <Input
            label={strings.orgName}
            value={disbandName}
            onChange={(e) => setDisbandName(e.target.value)}
            required
          />
          <Button
            fullWidth
            variant="destructive"
            type="submit"
            loading={busy}
            disabled={disbandName.trim() !== session.householdName}
          >
            {strings.disbandOrg}
          </Button>
        </form>
      </Sheet>
    </div>
  );
}
