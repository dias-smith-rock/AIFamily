"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { HouseholdProvider, useHousehold } from "@/lib/household-context";
import { t } from "@/lib/i18n";
import { Sheet, Spinner } from "@/components/ui";
import styles from "./AppShell.module.css";

const TABS = [
  { href: "/app/calendar", key: "tabSchedule" as const, icon: "📅" },
  { href: "/app/todos", key: "tabTodos" as const, icon: "✓" },
  { href: "/app/wallet", key: "tabWallet" as const, icon: "💰" },
  { href: "/app/location", key: "tabLocation" as const, icon: "📍" },
  { href: "/app/settings", key: "tabSettings" as const, icon: "⚙️" },
];

interface ShellChromeValue {
  openOrgSwitcher: () => void;
}

const ShellChromeContext = createContext<ShellChromeValue>({
  openOrgSwitcher: () => undefined,
});

export function useShellChrome(): ShellChromeValue {
  return useContext(ShellChromeContext);
}

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

  const isSchedule = pathname === "/app/calendar" || pathname.startsWith("/app/calendar/");
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

  const chromeValue = useMemo(
    () => ({
      openOrgSwitcher: () => setSwitcherOpen(true),
    }),
    []
  );

  return (
    <ShellChromeContext.Provider value={chromeValue}>
      <div className={[styles.shell, isSchedule ? styles.shellDark : ""].filter(Boolean).join(" ")}>
        {!isSchedule ? (
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
        ) : null}

        <main className={[styles.main, isSchedule ? styles.mainSchedule : ""].filter(Boolean).join(" ")}>
          {children}
        </main>

        <nav
          className={[styles.tabBar, isSchedule ? styles.tabBarDark : ""].filter(Boolean).join(" ")}
          aria-label="Primary"
        >
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
          variant="dark"
        >
          <div className={styles.switcherList}>
            {households.length === 0 ? (
              <p className={styles.switcherEmpty}>{strings.noOrgSelected}</p>
            ) : (
              households.map((household) => {
                const selected = session?.householdId === household.id;
                return (
                  <div key={household.membershipId} className={styles.switcherItem}>
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
                  </div>
                );
              })
            )}
          </div>
          <button
            type="button"
            className={styles.switcherCancel}
            onClick={() => setSwitcherOpen(false)}
          >
            {strings.cancel}
          </button>
        </Sheet>
      </div>
    </ShellChromeContext.Provider>
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
