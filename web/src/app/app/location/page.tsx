"use client";

import dynamic from "next/dynamic";
import { useCallback, useEffect, useMemo, useState } from "react";
import { fetchLocationStates, pushLocation, setGhostMode } from "@/lib/api/location";
import { fetchRoster } from "@/lib/api/members";
import { formatDateTime } from "@/lib/date-utils";
import { useHousehold } from "@/lib/household-context";
import { t } from "@/lib/i18n";
import type { LocationState } from "@/lib/types";
import { Button, Empty, Spinner } from "@/components/ui";
import type { MapMember } from "./LocationMap";
import styles from "./location.module.css";

const LocationMap = dynamic(
  () => import("./LocationMap").then((mod) => mod.LocationMap),
  {
    ssr: false,
    loading: () => (
      <div className={styles.center}>
        <Spinner />
      </div>
    ),
  }
);

function latestPoint(state: LocationState) {
  return state.locations.length > 0 ? state.locations[state.locations.length - 1] : null;
}

function mapsUrl(lat: number, lng: number): string {
  return `https://maps.google.com/?q=${lat},${lng}`;
}

export default function LocationPage() {
  const { session, locale, loading: sessionLoading } = useHousehold();
  const strings = t(locale);

  const [states, setStates] = useState<LocationState[]>([]);
  const [names, setNames] = useState<Map<string, string>>(new Map());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [ghostMode, setGhostModeState] = useState(false);

  const loadData = useCallback(async () => {
    if (!session?.householdId) {
      setStates([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const [locationRows, roster] = await Promise.all([
        fetchLocationStates(session.householdId),
        fetchRoster(session.householdId),
      ]);

      const nameMap = new Map<string, string>();
      for (const entry of roster) {
        const profileId = entry.profile?.id ?? entry.membership.profile_id;
        const name =
          entry.profile?.display_name ??
          entry.membership.display_name ??
          "Member";
        if (profileId) nameMap.set(profileId, name);
      }

      setNames(nameMap);
      setStates(locationRows);

      if (session.profileId) {
        const mine = locationRows.find((s) => s.entity_id === session.profileId);
        setGhostModeState(Boolean(mine?.is_ghost));
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : strings.error);
    } finally {
      setLoading(false);
    }
  }, [session?.householdId, session?.profileId, strings.error]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  const members = useMemo((): MapMember[] => {
    const rows: MapMember[] = [];
    for (const state of states) {
      const point = latestPoint(state);
      if (!point) continue;
      rows.push({
        id: state.entity_id,
        name: names.get(state.entity_id) ?? "Member",
        lat: point.lat,
        lng: point.lng,
        updatedAt: state.updated_at,
        isGhost: state.is_ghost,
      });
    }
    return rows;
  }, [states, names]);

  async function onShareLocation() {
    if (!session?.householdId || !session.profileId) {
      setError("Link your profile in Settings before sharing location.");
      return;
    }

    if (!navigator.geolocation) {
      setError("Geolocation is not supported in this browser.");
      return;
    }

    setBusy(true);
    setError(null);

    navigator.geolocation.getCurrentPosition(
      async (position) => {
        try {
          await pushLocation({
            entityId: session.profileId!,
            householdId: session.householdId,
            lat: position.coords.latitude,
            lng: position.coords.longitude,
            accuracy: position.coords.accuracy,
          });
          await loadData();
        } catch (err) {
          setError(err instanceof Error ? err.message : strings.error);
        } finally {
          setBusy(false);
        }
      },
      (geoError) => {
        setError(geoError.message);
        setBusy(false);
      },
      { enableHighAccuracy: true, timeout: 15000 }
    );
  }

  async function onToggleGhost(next: boolean) {
    if (!session?.profileId) return;

    setBusy(true);
    setError(null);
    try {
      await setGhostMode(session.profileId, next);
      setGhostModeState(next);
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

  return (
    <div className={styles.page}>
      <h1 className={styles.title}>{strings.tabLocation}</h1>

      <p className={styles.notice}>
        Background location tracking requires the iOS app. The web can share your current position on demand.
      </p>

      <div className={styles.actions}>
        <Button fullWidth onClick={() => void onShareLocation()} loading={busy}>
          Share my location
        </Button>

        {session.profileId ? (
          <div className={styles.ghostRow}>
            <span className={styles.ghostLabel}>Ghost mode</span>
            <input
              type="checkbox"
              checked={ghostMode}
              disabled={busy}
              onChange={(e) => void onToggleGhost(e.target.checked)}
              aria-label="Ghost mode"
            />
          </div>
        ) : null}
      </div>

      {error ? <p className={styles.error}>{error}</p> : null}

      {loading ? (
        <div className={styles.center}>
          <Spinner />
        </div>
      ) : members.length === 0 ? (
        <Empty title={strings.emptyLocation} />
      ) : (
        <>
          <div className={styles.mapWrap}>
            <LocationMap members={members} />
          </div>

          <div className={styles.memberList}>
            {members.map((member) => (
              <div key={member.id} className={styles.memberCard}>
                <div className={styles.memberHeader}>
                  <span className={styles.memberName}>{member.name}</span>
                  {member.isGhost ? <span className={styles.ghostBadge}>Ghost</span> : null}
                </div>
                <p className={styles.memberMeta}>
                  {member.lat.toFixed(5)}, {member.lng.toFixed(5)} · Updated{" "}
                  {formatDateTime(member.updatedAt, locale)}
                </p>
                <a
                  className={styles.mapsLink}
                  href={mapsUrl(member.lat, member.lng)}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Open in Maps
                </a>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
