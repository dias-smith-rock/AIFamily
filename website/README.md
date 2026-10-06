# WeFamily / Family Sync 官网

部署到 **https://www.wefamily.ai/** 的营销站（Astro 静态站）。

Web App（**https://app.wefamily.ai/**）不在本目录，后续单独建 `web/`。

## 品牌规则

| 语言 | 产品名 |
|------|--------|
| English（默认 `/`） | Family Sync |
| 简体中文 `/zh-Hans/` | 记事本 |
| 繁體中文 `/zh-Hant/` | 記事本 |

文案集中在 `src/i18n/ui.ts`。

## 本地开发

```bash
cd website
npm install
npm run dev
```

## 构建

```bash
cd website
npm run build
# 产物在 dist/
```

## 部署（Vercel）

1. 新建 Vercel 项目，Root Directory 设为 `website`
2. Framework：Astro（或 Other + `npm run build` / `dist`）
3. 绑定域名 `www.wefamily.ai`（及 apex `wefamily.ai` 按需跳转）
4. App Store 链接已配置为 `id6775353963`（见 `src/i18n/ui.ts` 的 `site.appStoreUrl`）

也可任意静态托管：上传 `dist/` 即可。

## 链接

- Web App CTA → `https://app.wefamily.ai/`
- 联系邮箱 → `jimo.cgg@gmail.com`
- 主体 → GOODCRAFT INTERNATIONAL LIMITED / 良作國際有限公司
