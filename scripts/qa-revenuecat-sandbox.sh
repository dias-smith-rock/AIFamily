#!/usr/bin/env bash
# RevenueCat 沙盒 / 部署验收辅助脚本（需先配置 secrets 并 deploy Edge Functions）
set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-}"
WEBHOOK_AUTH="${REVENUECAT_WEBHOOK_AUTHORIZATION:-}"
TEST_USER_ID="${TEST_USER_ID:-}"

usage() {
  cat <<'EOF'
用法:
  SUPABASE_PROJECT_REF=xxx REVENUECAT_WEBHOOK_AUTHORIZATION='Bearer secret' \
    TEST_USER_ID=<supabase-auth-uuid> ./scripts/qa-revenuecat-sandbox.sh webhook
  SUPABASE_PROJECT_REF=xxx TEST_USER_ID=<uuid> USER_JWT=<access_token> \
    ./scripts/qa-revenuecat-sandbox.sh sync

子命令:
  webhook  向 revenuecat-webhook 发送模拟 INITIAL_PURCHASE（需 TEST_USER_ID 为合法 UUID）
  sync     调用 sync-revenuecat-entitlement（需 USER_JWT）
EOF
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  usage
  exit 1
fi

if [[ -z "$PROJECT_REF" ]]; then
  echo "请设置 SUPABASE_PROJECT_REF"
  exit 1
fi

BASE="https://${PROJECT_REF}.supabase.co/functions/v1"

case "$cmd" in
  webhook)
    if [[ -z "$WEBHOOK_AUTH" || -z "$TEST_USER_ID" ]]; then
      echo "webhook 需要 REVENUECAT_WEBHOOK_AUTHORIZATION 与 TEST_USER_ID"
      exit 1
    fi
    EXPIRES_MS=$(( $(date +%s) * 1000 + 30 * 24 * 60 * 60 * 1000 ))
    curl -sS -X POST "${BASE}/revenuecat-webhook" \
      -H "Authorization: ${WEBHOOK_AUTH}" \
      -H "Content-Type: application/json" \
      -d "{
        \"api_version\": \"1.0\",
        \"event\": {
          \"type\": \"INITIAL_PURCHASE\",
          \"app_user_id\": \"${TEST_USER_ID}\",
          \"product_id\": \"wesync.vip.yearly\",
          \"expiration_at_ms\": ${EXPIRES_MS}
        }
      }" | python3 -m json.tool
    ;;
  sync)
    JWT="${USER_JWT:-}"
    if [[ -z "$JWT" ]]; then
      echo "sync 需要 USER_JWT（Supabase access token）"
      exit 1
    fi
    curl -sS -X POST "${BASE}/sync-revenuecat-entitlement" \
      -H "Authorization: Bearer ${JWT}" \
      -H "Content-Type: application/json" \
      -d '{}' | python3 -m json.tool
    ;;
  *)
    usage
    exit 1
    ;;
esac
