#!/usr/bin/env bash
# 验证 RevenueCat + Supabase VIP 云端链路是否就绪（只读检查清单 + 可选 API 探测）
set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-}"
USER_ID="${TEST_USER_ID:-}"
JWT="${USER_JWT:-}"
WEBHOOK_AUTH="${REVENUECAT_WEBHOOK_AUTHORIZATION:-}"

cat <<'EOF'
=== RevenueCat Dashboard（手动）===
[ ] Entitlement 标识符 = premium
[ ] Products: wesync.vip.monthly / wesync.vip.yearly 已绑定 premium
[ ] Offering 标识符 = current（全小写），已勾选 Current，含月付/年付 Package
[ ] Webhook URL → https://<PROJECT_REF>.supabase.co/functions/v1/revenuecat-webhook
[ ] Customers：登录用户 app_user_id = Supabase auth UUID（小写）

=== Supabase SQL（在 SQL Editor 执行）===
select proname from pg_proc where proname = 'sync_user_entitlement_from_revenuecat';
select polname from pg_policies where tablename = 'user_entitlements';
select user_id, is_pro, pro_expires_at, updated_at from user_entitlements where user_id = '<UUID>';

=== Supabase Secrets（CLI）===
supabase secrets list | rg REVENUECAT || true

=== Edge Functions 已部署 ===
supabase functions list | rg revenuecat || true
EOF

if [[ -n "$PROJECT_REF" && -n "$WEBHOOK_AUTH" && -n "$USER_ID" ]]; then
  echo ""
  echo ">>> 探测 revenuecat-webhook（模拟 INITIAL_PURCHASE）"
  "$(dirname "$0")/qa-revenuecat-sandbox.sh" webhook
fi

if [[ -n "$PROJECT_REF" && -n "$JWT" ]]; then
  echo ""
  echo ">>> 探测 sync-revenuecat-entitlement"
  "$(dirname "$0")/qa-revenuecat-sandbox.sh" sync
fi
