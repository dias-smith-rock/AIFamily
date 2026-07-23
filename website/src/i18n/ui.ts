export type Locale = "en" | "zh-Hans" | "zh-Hant";

export const locales: Locale[] = ["en", "zh-Hans", "zh-Hant"];

export const localeLabels: Record<Locale, string> = {
  en: "English",
  "zh-Hans": "简体中文",
  "zh-Hant": "繁體中文",
};

/** Product display name by locale — locked brand rule. */
export function productName(locale: Locale): string {
  switch (locale) {
    case "zh-Hans":
      return "记事本";
    case "zh-Hant":
      return "記事本";
    default:
      return "WeSync";
  }
}

export const site = {
  /** 本地联调先指向 Web App dev server；上线前改回 https://app.wefamily.ai/ */
  appUrl: "http://localhost:3000/",
  appStoreUrl: "https://apps.apple.com/app/id6775353963",
  contactEmail: "jimo.cgg@gmail.com",
  companyEn: "GOODCRAFT INTERNATIONAL LIMITED",
  companyZh: "良作國際有限公司",
  year: 2026,
};

export type Messages = {
  metaTitle: string;
  metaDescription: string;
  navWeb: string;
  navGetApp: string;
  heroHeadline: string;
  heroSub: string;
  ctaAppStore: string;
  ctaWeb: string;
  screensHint: string;
  scenariosTitle: string;
  scenariosIntro: string;
  scenarios: { title: string; problem: string; solution: string; icon: string }[];
  featuresTitle: string;
  featuresIntro: string;
  features: { title: string; body: string; icon: string }[];
  footerRights: string;
  privacy: string;
  terms: string;
  contact: string;
  privacyTitle: string;
  termsTitle: string;
  legalBack: string;
  privacyBody: string[];
  termsBody: string[];
};

const en: Messages = {
  metaTitle: "WeSync — Lightweight coordination for small circles",
  metaDescription:
    "Calendar, to-dos, shared wallet, and member profiles for trusted groups of 3–20. Sync on iPhone or the web—without forcing everyone to install the app.",
  navWeb: "Web app",
  navGetApp: "Get the app",
  heroHeadline: "Small-circle coordination\nwithout living in the group chat",
  heroSub:
    "Schedules, tasks, who-does-what, and member profiles—for families, trips, clubs, and roommates. Light, clear, and usable even when not everyone downloads the app.",
  ctaAppStore: "Download on the App Store",
  ctaWeb: "Open web app",
  screensHint: "Swipe or use arrows to browse screens",
  scenariosTitle: "Built for tight circles",
  scenariosIntro:
    "Wherever 3–20 people need to divide work and stay on a shared timeline, WeSync keeps the noise out of the chat.",
  scenarios: [
    {
      icon: "👥",
      title: "Families",
      problem: "Pickups, errands, and meds get buried in chat threads.",
      solution: "Owners can keep profiles for anyone, assign owners, and see the whole group calendar at a glance.",
    },
    {
      icon: "✈️",
      title: "Trips",
      problem: "Tickets, meetup times, and packing lists scroll away in the group.",
      solution: "Put the itinerary on the calendar and make “who handles it” obvious—companions don’t all need the app.",
    },
    {
      icon: "🎓",
      title: "Clubs & class committees",
      problem: "Event prep has too many open loops and uneven follow-through.",
      solution: "Separate shared to-dos from personal tasks so prep ownership stays visible.",
    },
    {
      icon: "🏡",
      title: "Roommates",
      problem: "Bills, cleaning rotation, and shared shopping rely on verbal promises.",
      solution: "Recurring tasks with reminders keep chores recorded and owned.",
    },
    {
      icon: "🚀",
      title: "Small founding teams",
      problem: "You don’t want enterprise chat suites—just light task and schedule sync.",
      solution: "Use the web console to plan; check progress on mobile. Enough structure, not too much.",
    },
  ],
  featuresTitle: "Designed around uneven participation",
  featuresIntro: "Not everyone will install an app. We started from that constraint.",
  features: [
    {
      icon: "👤",
      title: "Virtual member profiles",
      body: "Create profiles for people who won’t use the app—elders, kids, temporary travelers, or external helpers—so one organizer can run the whole circle’s schedule and to-dos.",
    },
    {
      icon: "🎯",
      title: "Clear task ownership",
      body: "Split shared to-dos from personal tasks. Hotels, documents, supplies, duty rotations—assigned, trackable, done.",
    },
    {
      icon: "📒",
      title: "Shared wallet & calendar",
      body: "Family spending categories, income logging, and a group calendar sit in one place—mobile-first, synced to the cloud.",
    },
    {
      icon: "💻",
      title: "App + web, same household",
      body: "Plan on the phone or in the browser at app.wefamily.ai. One Supabase-backed household, same roles and data.",
    },
  ],
  footerRights: "All rights reserved.",
  privacy: "Privacy Policy",
  terms: "Terms of Service",
  contact: "Contact",
  privacyTitle: "Privacy Policy",
  termsTitle: "Terms of Service",
  legalBack: "Back to home",
  privacyBody: [
    "WeSync (“we”, “us”) provides family and small-group scheduling, to-dos, wallet, and related features via our iOS app and web app at wefamily.ai.",
    "Account data is handled through our authentication providers (such as Sign in with Apple and Google) and our cloud backend. Household content you create is stored to operate the service and sync across your devices.",
    "We do not sell your personal information. We use data to provide the product, secure accounts, prevent abuse, and improve reliability.",
    "You may request account deletion from in-app settings or by emailing us. Some records may be retained where required for security, legal, or billing obligations.",
    "For privacy questions, contact us at the email listed in the site footer.",
    "Last updated: July 2026.",
  ],
  termsBody: [
    "By using WeSync (the iOS app or web app), you agree to these Terms of Service.",
    "You must be able to form a binding contract in your jurisdiction. You are responsible for activity under your account and for content you post within a household.",
    "The service is provided “as is.” We may modify or discontinue features with reasonable notice when practical. Paid subscriptions, if any, are governed by Apple’s App Store terms when purchased on iOS.",
    "You may not misuse the service, attempt unauthorized access, or use it to harass others.",
    "These terms are governed by the laws applicable to GOODCRAFT INTERNATIONAL LIMITED, without regard to conflict-of-law rules.",
    "Contact us via the email in the site footer for questions about these terms.",
    "Last updated: July 2026.",
  ],
};

const zhHans: Messages = {
  metaTitle: "记事本 — 小圈子轻量协作中枢",
  metaDescription:
    "日程、待办、家庭账本与成员档案，适合 3–20 人的信任小圈子。iPhone 与网页同步，不必全员下载 App。",
  navWeb: "Web 应用",
  navGetApp: "获取 App",
  heroHeadline: "让小圈子协作，\n不再靠群聊硬撑",
  heroSub:
    "任务、日程、分工、成员档案——家庭、旅行团、社团小组都能用。轻量清晰，不需要全员下载 App。",
  ctaAppStore: "在 App Store 下载",
  ctaWeb: "打开网页版",
  screensHint: "左右滑动或点击箭头查看更多界面",
  scenariosTitle: "适用场景",
  scenariosIntro:
    "凡是有协作需求的紧密小圈子——3 到 20 人、彼此信任、需要分事排期——都能用记事本理清琐事。",
  scenarios: [
    {
      icon: "👥",
      title: "家庭 / 群组",
      problem: "接送、采购、用药提醒散在群聊里，容易遗漏。",
      solution: "主理人可建档代管，任务责任到人，全群日程一眼可见。",
    },
    {
      icon: "✈️",
      title: "旅行团",
      problem: "订票订房、集合时间、证件行李，信息总在群里刷过。",
      solution: "行程排进日历，「谁去办」分工清楚，同行不必人人装 App。",
    },
    {
      icon: "🎓",
      title: "社团 / 班委",
      problem: "活动筹备事项多，成员参与不均，进度难追踪。",
      solution: "公共待办与个人任务分开管理，筹备分工一目了然。",
    },
    {
      icon: "🏡",
      title: "合租 / 室友",
      problem: "水电缴费、清洁轮换、共同采购，口头约定容易忘。",
      solution: "周期性任务加提醒，分工有记录、有责任人。",
    },
    {
      icon: "🚀",
      title: "创业小组",
      problem: "不想上沉重协同套件，又需要轻量的任务与日程。",
      solution: "网页端统筹进度，手机随时查看，体量刚好够用。",
    },
  ],
  featuresTitle: "化繁为简，为小圈子而生",
  featuresIntro: "成员参与门槛不一？我们以此为起点设计产品。",
  features: [
    {
      icon: "👤",
      title: "「免下载」成员档案",
      body: "主理人可为不使用 App 的人建立档案——长辈、儿童、临时同行或外部协作者均可纳入，一人即可统筹全圈子的日程与待办。",
    },
    {
      icon: "🎯",
      title: "专属任务流转",
      body: "清晰区分公共待办与个人任务。订酒店、带证件、准备物料、值班轮换——责任到人，进度可查。",
    },
    {
      icon: "📒",
      title: "账本与日历一体",
      body: "分类记账、收入登记与群组日历在同一产品中，手机优先，云端同步。",
    },
    {
      icon: "💻",
      title: "App + 网页同一家庭",
      body: "在手机或 app.wefamily.ai 网页端规划，同一套家庭数据与角色权限实时互通。",
    },
  ],
  footerRights: "保留所有权利。",
  privacy: "隐私政策",
  terms: "服务条款",
  contact: "联系我们",
  privacyTitle: "隐私政策",
  termsTitle: "服务条款",
  legalBack: "返回首页",
  privacyBody: [
    "记事本（WeSync，「我们」）通过 iOS 应用与 wefamily.ai 网页应用，提供家庭与小圈子的日程、待办、账本等相关功能。",
    "账号数据经由认证服务商（如通过 Apple、Google 登录）及云端后端处理。你在家庭组织中创建的内容用于提供服务并在多端同步。",
    "我们不会出售你的个人信息。数据用于提供产品、保障账号安全、防止滥用并提升稳定性。",
    "你可在应用内设置中申请注销账号，或通过页脚邮箱联系我们。出于安全、法律或计费等义务，部分记录可能依法保留。",
    "隐私相关问题请通过页脚邮箱联系我们。",
    "最近更新：2026 年 7 月。",
  ],
  termsBody: [
    "使用记事本（WeSync）的 iOS 应用或网页应用，即表示你同意本服务条款。",
    "你须具备所在司法辖区订立约束性合同的能力。你须对账号下的行为及在家庭组织中发布的内容负责。",
    "服务按「现状」提供。我们可能在合理可行时调整或下线功能。若存在付费订阅且通过 iOS 购买，则同时适用 Apple App Store 相关条款。",
    "不得滥用服务、尝试未授权访问，或利用服务骚扰他人。",
    "本条款适用 GOODCRAFT INTERNATIONAL LIMITED 相关法律，不考虑法律冲突规则。",
    "条款相关问题请通过页脚邮箱联系我们。",
    "最近更新：2026 年 7 月。",
  ],
};

const zhHant: Messages = {
  metaTitle: "記事本 — 小圈子輕量協作中樞",
  metaDescription:
    "日程、待辦、家庭帳簿與成員檔案，適合 3–20 人的信任小圈子。iPhone 與網頁同步，不必全員下載 App。",
  navWeb: "Web 應用",
  navGetApp: "取得 App",
  heroHeadline: "讓小圈子協作，\n不再靠群聊硬撐",
  heroSub:
    "任務、日程、分工、成員檔案——家庭、旅行團、社團小組都能用。輕量清晰，不需要全員下載 App。",
  ctaAppStore: "在 App Store 下載",
  ctaWeb: "打開網頁版",
  screensHint: "左右滑動或點擊箭頭查看更多界面",
  scenariosTitle: "適用場景",
  scenariosIntro:
    "凡是有協作需求的緊密小圈子——3 到 20 人、彼此信任、需要分事排期——都能用記事本理清瑣事。",
  scenarios: [
    {
      icon: "👥",
      title: "家庭 / 群組",
      problem: "接送、採購、用藥提醒散在群聊裡，容易遺漏。",
      solution: "主理人可建檔代管，任務責任到人，全群日程一眼可見。",
    },
    {
      icon: "✈️",
      title: "旅行團",
      problem: "訂票訂房、集合時間、證件行李，資訊總在群裡刷過。",
      solution: "行程排進日曆，「誰去辦」分工清楚，同行不必人人裝 App。",
    },
    {
      icon: "🎓",
      title: "社團 / 班委",
      problem: "活動籌備事項多，成員參與不均，進度難追蹤。",
      solution: "公共待辦與個人任務分開管理，籌備分工一目瞭然。",
    },
    {
      icon: "🏡",
      title: "合租 / 室友",
      problem: "水電繳費、清潔輪換、共同採購，口頭約定容易忘。",
      solution: "週期性任務加提醒，分工有記錄、有責任人。",
    },
    {
      icon: "🚀",
      title: "創業小組",
      problem: "不想上沉重協同套件，又需要輕量的任務與日程。",
      solution: "網頁端統籌進度，手機隨時查看，體量剛好夠用。",
    },
  ],
  featuresTitle: "化繁為簡，為小圈子而生",
  featuresIntro: "成員參與門檻不一？我們以此為起點設計產品。",
  features: [
    {
      icon: "👤",
      title: "「免下載」成員檔案",
      body: "主理人可為不使用 App 的人建立檔案——長輩、兒童、臨時同行或外部協作者均可納入，一人即可統籌全圈子的日程與待辦。",
    },
    {
      icon: "🎯",
      title: "專屬任務流轉",
      body: "清晰區分公共待辦與個人任務。訂酒店、帶證件、準備物料、值班輪換——責任到人，進度可查。",
    },
    {
      icon: "📒",
      title: "帳簿與日曆一體",
      body: "分類記帳、收入登記與群組日曆在同一產品中，手機優先，雲端同步。",
    },
    {
      icon: "💻",
      title: "App + 網頁同一家庭",
      body: "在手機或 app.wefamily.ai 網頁端規劃，同一套家庭資料與角色權限即時互通。",
    },
  ],
  footerRights: "保留所有權利。",
  privacy: "隱私政策",
  terms: "服務條款",
  contact: "聯絡我們",
  privacyTitle: "隱私政策",
  termsTitle: "服務條款",
  legalBack: "返回首頁",
  privacyBody: [
    "記事本（WeSync，「我們」）透過 iOS 應用與 wefamily.ai 網頁應用，提供家庭與小圈子的日程、待辦、帳簿等相關功能。",
    "帳號資料經由認證服務商（如透過 Apple、Google 登入）及雲端後端處理。你在家庭組織中建立的內容用於提供服務並在多端同步。",
    "我們不會出售你的個人資訊。資料用於提供產品、保障帳號安全、防止濫用並提升穩定性。",
    "你可在應用內設定中申請註銷帳號，或透過頁腳郵箱聯絡我們。出於安全、法律或計費等義務，部分記錄可能依法保留。",
    "隱私相關問題請透過頁腳郵箱聯絡我們。",
    "最近更新：2026 年 7 月。",
  ],
  termsBody: [
    "使用記事本（WeSync）的 iOS 應用或網頁應用，即表示你同意本服務條款。",
    "你須具備所在司法轄區訂立約束性合約的能力。你須對帳號下的行為及在家庭組織中發佈的內容負責。",
    "服務按「現狀」提供。我們可能在合理可行時調整或下線功能。若存在付費訂閱且透過 iOS 購買，則同時適用 Apple App Store 相關條款。",
    "不得濫用服務、嘗試未授權存取，或利用服務騷擾他人。",
    "本條款適用 GOODCRAFT INTERNATIONAL LIMITED 相關法律，不考慮法律衝突規則。",
    "條款相關問題請透過頁腳郵箱聯絡我們。",
    "最近更新：2026 年 7 月。",
  ],
};

const catalog: Record<Locale, Messages> = {
  en,
  "zh-Hans": zhHans,
  "zh-Hant": zhHant,
};

export function getMessages(locale: string): Messages {
  if (locale === "zh-Hans" || locale === "zh-Hant" || locale === "en") {
    return catalog[locale];
  }
  return catalog.en;
}

export function localePath(locale: Locale, path = ""): string {
  const clean = path.replace(/^\//, "");
  if (locale === "en") {
    return clean ? `/${clean}` : "/";
  }
  return clean ? `/${locale}/${clean}` : `/${locale}/`;
}
