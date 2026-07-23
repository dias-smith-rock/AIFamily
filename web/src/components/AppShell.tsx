"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { HouseholdProvider, useHousehold } from "@/lib/household-context";
import { t } from "@/lib/i18n";
import { Button, Card, Sheet, Spinner } from "@/components/ui";
import styles from "./AppShell.module.css";

const TABS = [
  { href: "/app/calendar", key: "tabSchedule" as const, icon: "📅" },
  { href: "/app/todos", key: "tabTodos" as const, icon: "✓" },
  { href: "/app/wallet", key: "tabWallet" as const, icon: "💰" },
  { href: "/app/location", key: "tabLocation" as const, icon: "📍" },
  { href: "/app/settings", key: "tabSettings" as const, icon: "⚙️" },
];

function AppShellInner({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { session, households, locale, productName, loading, chooseHousehold } =
    useHousehold();

  useEffect(() => {
    if (loading) return;
    if (households.length === 0) {
      router.replace("/org");
    }
  }, [loading, households.length, router]);
  const strings = t(locale);
  const [switcherOpen, setSwitcherOpen] = useState(false);

  const householdLabel = session?.householdName ?? strings.noOrgSelected;

  const tabItems = useMemo(
    () =>
      TABS.map((tab) => ({
        ...tab,
        label: strings[tab.key],
        active: pathname === tab.href || pathname.startsWith(`${tab.href}/`),
      })),
    [pathname, strings]
  );

  return (
    <div className={styles.shell}>
      <header className={styles.topBar}>
        <div className={styles.topBarInner}>
          <button
            type="button"
            className={styles.householdButton}
            onClick={() => setSwitcherOpen(true)}
            aria-haspopup="dialog"
          >
            <span className={styles.productName}>{productName}</span>
            <span className={styles.householdName}>{householdLabel}</span>
          </button>
          {loading ? <Spinner size="sm" /> : null}
        </div>
      </header>

      <main className={styles.main}>{children}</main>

      <nav className={styles.tabBar} aria-label="Primary">
        {tabItems.map((tab) => (
          <Link
            key={tab.href}
            href={tab.href}
            className={[styles.tab, tab.active ? styles.tabActive : ""]
              .filter(Boolean)
              .join(" ")}
          >
            <span className={styles.tabIcon} aria-hidden>
              {tab.icon}
            </span>
            <span className={styles.tabLabel}>{tab.label}</span>
          </Link>
        ))}
      </nav>

      <Sheet
        open={switcherOpen}
        onClose={() => setSwitcherOpen(false)}
        title={strings.orgSwitcher}
      >
        <div className={styles.switcherList}>
          {households.length === 0 ? (
            <p className={styles.switcherEmpty}>{strings.noOrgSelected}</p>
          ) : (
            households.map((household) => {
              const selected = session?.householdId === household.id;
              return (
                <Card key={household.id} padding="sm" className={styles.switcherItem}>
                  <button
                    type="button"
                    className={[
                      styles.switcherButton,
                      selected ? styles.switcherButtonActive : "",
                    ]
                      .filter(Boolean)
                      .join(" ")}
                    onClick={async () => {
                      await chooseHousehold(household.id);
                      setSwitcherOpen(false);
                    }}
                  >
                    <span className={styles.switcherName}>{household.name}</span>
                    <span className={styles.switcherRole}>{household.role}</span>
                  </button>
                </Card>
              );
            })
          )}
        </div>
        <Button variant="secondary" fullWidth onClick={() => setSwitcherOpen(false)}>
          {strings.cancel}
        </Button>
      </Sheet>
    </div>
  );
}

export function AppShell({ children }: { children: ReactNode }) {
  return (
    <HouseholdProvider>
      <AppShellInner>{children}</AppShellInner>
    </HouseholdProvider>
  );
}

export { HouseholdProvider, useHousehold };
