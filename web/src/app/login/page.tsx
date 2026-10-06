"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button, Card } from "@/components/ui";
import styles from "./login.module.css";

type Provider = "google" | "apple";

export default function LoginPage() {
  const [loading, setLoading] = useState<Provider | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function signIn(provider: Provider) {
    setLoading(provider);
    setError(null);
    try {
      const supabase = createClient();
      const origin = process.env.NEXT_PUBLIC_SITE_URL || window.location.origin;
      const { error: authError } = await supabase.auth.signInWithOAuth({
        provider,
        options: {
          redirectTo: `${origin}/auth/callback`,
        },
      });
      if (authError) throw authError;
    } catch (e) {
      setError(e instanceof Error ? e.message : "Sign-in failed");
      setLoading(null);
    }
  }

  return (
    <div className={styles.page}>
      <div className={styles.hero}>
        <p className={styles.brand}>Family Sync</p>
        <h1 className={styles.title}>小圈子协作，不必全员装 App</h1>
        <p className={styles.sub}>
          日程、待办、账本、位置 — 与 iOS 同一家庭数据实时同步。
        </p>
      </div>

      <Card className={styles.card}>
        <Button
          fullWidth
          disabled={loading !== null}
          onClick={() => void signIn("apple")}
        >
          {loading === "apple" ? "…" : "Continue with Apple"}
        </Button>
        <Button
          fullWidth
          variant="secondary"
          disabled={loading !== null}
          onClick={() => void signIn("google")}
        >
          {loading === "google" ? "…" : "Continue with Google"}
        </Button>
        {error ? <p className={styles.error}>{error}</p> : null}
        <p className={styles.legal}>
          登录即表示同意{" "}
          <a href="https://www.wefamily.ai/privacy" target="_blank" rel="noreferrer">
            隐私政策
          </a>{" "}
          与{" "}
          <a href="https://www.wefamily.ai/terms" target="_blank" rel="noreferrer">
            服务条款
          </a>
        </p>
      </Card>
    </div>
  );
}
