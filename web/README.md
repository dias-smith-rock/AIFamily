# WeFamily / WeSync Web App

部署域名：**https://app.wefamily.ai/**

与 iOS App（`reminder/`）共用同一 Supabase 项目与 RLS；移动浏览器优先，桌面兼容。

## 功能对照（相对 iOS）

| 模块 | Web 已实现 | 说明 |
|------|------------|------|
| 登录 | Apple / Google OAuth | Redirect → `/auth/callback` |
| 建群 / 加群 / 选群 | ✅ | RPC `create_household_with_membership` / `join_household_by_nonce` |
| 日程 | ✅ 日视图 CRUD、状态、完成、删除 | 周/年视图、AI 识图、附件、地理围栏 → 后续 |
| 待办 | ✅ 灵活待办、逾期/完成分组 | |
| 账本 | ✅ 看板、记账、分类管理/排序、成员仅收入 | 报表 Charts 简化 |
| 位置 | ✅ 地图、分享当前位置、Ghost | 后台定位 / Live Huddle → 需 iOS 或后续 WebSocket |
| 设置 | ✅ 语言、成员、虚拟成员、邀请码、离开/解散、登出 | Face ID / IAP / 系统通知 → Web 不对等 |

## 本地开发

```bash
cd web
cp .env.local.example .env.local   # 已有则可跳过
npm install
npm run dev
```

打开 http://localhost:3000 。

### Supabase Auth 回调

在 Supabase Dashboard → Authentication → URL Configuration 增加：

- Site URL: `https://app.wefamily.ai`（本地可用 `http://localhost:3000`）
- Redirect URLs:
  - `http://localhost:3000/auth/callback`
  - `https://app.wefamily.ai/auth/callback`

并启用 Google / Apple provider（与 iOS 相同项目）。

## 部署（Vercel）

1. 新建项目，**Root Directory = `web`**
2. Framework：Next.js
3. 环境变量复制 `.env.local.example`，将 `NEXT_PUBLIC_SITE_URL` 设为 `https://app.wefamily.ai`
4. 绑定域名 `app.wefamily.ai`

```bash
cd web && npm run build
```

## 目录

```
web/src/app/login|org|pending|auth|app/{calendar,todos,wallet,location,settings}
web/src/lib/api/          # Supabase 数据层
web/src/lib/household-context.tsx
web/src/components/AppShell.tsx
```

## 身份 ID（与 iOS 一致）

- `tasks.creator_id` / `involved_member_ids` → **membership id**
- 账本人物字段 / `location_states.entity_id` → **family_profiles.id**
- 禁止把 `auth.users.id` 写入上述字段
