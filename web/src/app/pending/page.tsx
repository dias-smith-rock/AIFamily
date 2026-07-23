"use client";

import Link from "next/link";
import { Button } from "@/components/ui";
import styles from "./pending.module.css";

export default function PendingPage() {
  return (
    <div className={styles.page}>
      <div className={styles.card}>
        <p className={styles.icon} aria-hidden>
          ⏳
        </p>
        <h1 className={styles.title}>Pending approval</h1>
        <p className={styles.description}>
          Your request to join this household is waiting for an admin to approve it. You will get
          access once approved on iOS or web.
        </p>
      </div>
      <Link href="/org">
        <Button variant="secondary">Back to households</Button>
      </Link>
    </div>
  );
}
