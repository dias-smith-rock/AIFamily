export type AppLocale = "en" | "zh-Hans" | "zh-Hant";

export const PRODUCT_NAMES: Record<AppLocale, string> = {
  en: "WeSync",
  "zh-Hans": "记事本",
  "zh-Hant": "記事本",
};

export interface UiStrings {
  loginTitle: string;
  loginSubtitle: string;
  signInWithGoogle: string;
  signOut: string;
  orgSwitcher: string;
  createOrg: string;
  joinOrg: string;
  leaveOrg: string;
  disbandOrg: string;
  orgName: string;
  inviteCode: string;
  tabSchedule: string;
  tabTodos: string;
  tabWallet: string;
  tabLocation: string;
  tabSettings: string;
  save: string;
  cancel: string;
  delete: string;
  create: string;
  join: string;
  loading: string;
  error: string;
  retry: string;
  emptyTasks: string;
  emptyTodos: string;
  emptyWallet: string;
  emptyLocation: string;
  emptyMembers: string;
  noOrgSelected: string;
  switchOrg: string;
}

export const UI: Record<AppLocale, UiStrings> = {
  en: {
    loginTitle: "Sign in to WeSync",
    loginSubtitle: "Coordinate schedules, tasks, and family finances together.",
    signInWithGoogle: "Continue with Google",
    signOut: "Sign out",
    orgSwitcher: "Switch household",
    createOrg: "Create household",
    joinOrg: "Join with code",
    leaveOrg: "Leave household",
    disbandOrg: "Disband household",
    orgName: "Household name",
    inviteCode: "Invite code",
    tabSchedule: "Schedule",
    tabTodos: "Todos",
    tabWallet: "Wallet",
    tabLocation: "Location",
    tabSettings: "Settings",
    save: "Save",
    cancel: "Cancel",
    delete: "Delete",
    create: "Create",
    join: "Join",
    loading: "Loading…",
    error: "Something went wrong",
    retry: "Try again",
    emptyTasks: "No scheduled tasks yet",
    emptyTodos: "No flexible todos yet",
    emptyWallet: "No transactions yet",
    emptyLocation: "No location updates yet",
    emptyMembers: "No members yet",
    noOrgSelected: "Select a household to continue",
    switchOrg: "Switch",
  },
  "zh-Hans": {
    loginTitle: "登录记事本",
    loginSubtitle: "与家人一起协调日程、待办与家庭账本。",
    signInWithGoogle: "使用 Google 继续",
    signOut: "退出登录",
    orgSwitcher: "切换家庭",
    createOrg: "创建家庭",
    joinOrg: "输入邀请码加入",
    leaveOrg: "退出家庭",
    disbandOrg: "解散家庭",
    orgName: "家庭名称",
    inviteCode: "邀请码",
    tabSchedule: "日程",
    tabTodos: "待办",
    tabWallet: "账本",
    tabLocation: "位置",
    tabSettings: "设置",
    save: "保存",
    cancel: "取消",
    delete: "删除",
    create: "创建",
    join: "加入",
    loading: "加载中…",
    error: "出错了",
    retry: "重试",
    emptyTasks: "暂无日程任务",
    emptyTodos: "暂无灵活待办",
    emptyWallet: "暂无账目",
    emptyLocation: "暂无位置更新",
    emptyMembers: "暂无成员",
    noOrgSelected: "请选择一个家庭",
    switchOrg: "切换",
  },
  "zh-Hant": {
    loginTitle: "登入記事本",
    loginSubtitle: "與家人一起協調日程、待辦與家庭帳本。",
    signInWithGoogle: "使用 Google 繼續",
    signOut: "登出",
    orgSwitcher: "切換家庭",
    createOrg: "建立家庭",
    joinOrg: "輸入邀請碼加入",
    leaveOrg: "退出家庭",
    disbandOrg: "解散家庭",
    orgName: "家庭名稱",
    inviteCode: "邀請碼",
    tabSchedule: "日程",
    tabTodos: "待辦",
    tabWallet: "帳本",
    tabLocation: "位置",
    tabSettings: "設定",
    save: "儲存",
    cancel: "取消",
    delete: "刪除",
    create: "建立",
    join: "加入",
    loading: "載入中…",
    error: "出錯了",
    retry: "重試",
    emptyTasks: "暫無日程任務",
    emptyTodos: "暫無靈活待辦",
    emptyWallet: "暫無帳目",
    emptyLocation: "暫無位置更新",
    emptyMembers: "暫無成員",
    noOrgSelected: "請選擇一個家庭",
    switchOrg: "切換",
  },
};

export function t(locale: AppLocale): UiStrings {
  return UI[locale];
}

export function detectLocale(): AppLocale {
  if (typeof navigator === "undefined") return "en";
  const lang = navigator.language;
  if (lang.startsWith("zh-Hant") || lang === "zh-TW" || lang === "zh-HK") {
    return "zh-Hant";
  }
  if (lang.startsWith("zh")) return "zh-Hans";
  return "en";
}

export const LOCALE_STORAGE_KEY = "wesync.locale";
