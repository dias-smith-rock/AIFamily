export type AppLocale = "en" | "zh-Hans" | "zh-Hant";

export const PRODUCT_NAMES: Record<AppLocale, string> = {
  en: "Family Sync",
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
  today: string;
  newEvent: string;
  whatWouldYouLikeToDo: string;
  addAttachment: string;
  timeSetting: string;
  allDay: string;
  executionTime: string;
  duration: string;
  repeat: string;
  doesNotRepeat: string;
  repeatDaily: string;
  repeatWeekly: string;
  repeatMonthly: string;
  forWhom: string;
  everyone: string;
  me: string;
  showMoreOptions: string;
  hideMoreOptions: string;
  notes: string;
  remind: string;
  remindNone: string;
  remindOnTime: string;
  remind5Min: string;
  remind15Min: string;
  remind30Min: string;
  remind1Hour: string;
  taskPriority: string;
  urgent: string;
  generally: string;
  emergencyContact: string;
  enterNumberOrLink: string;
  assignee: string;
  searchOrAddLocation: string;
  moreDetails: string;
  addNote: string;
  financeAndNotes: string;
  expenses: string;
  detailedDescription: string;
  expenseDetailsPlaceholder: string;
}

export const UI: Record<AppLocale, UiStrings> = {
  en: {
    loginTitle: "Sign in to Family Sync",
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
    today: "Today",
    newEvent: "New Event",
    whatWouldYouLikeToDo: "What would you like to do?",
    addAttachment: "Add attachment",
    timeSetting: "Time setting",
    allDay: "All day",
    executionTime: "Execution time",
    duration: "Duration",
    repeat: "Repeat",
    doesNotRepeat: "Does not repeat",
    repeatDaily: "Daily",
    repeatWeekly: "Weekly",
    repeatMonthly: "Monthly",
    forWhom: "For whom (FOR)",
    everyone: "Everyone",
    me: "Me",
    showMoreOptions: "Show more options",
    hideMoreOptions: "Collapse more options",
    notes: "Notes",
    remind: "Remind",
    remindNone: "None",
    remindOnTime: "At time of event",
    remind5Min: "5 minutes before",
    remind15Min: "15 minutes before",
    remind30Min: "30 minutes before",
    remind1Hour: "1 hour before",
    taskPriority: "Task priority",
    urgent: "Urgent",
    generally: "Generally",
    emergencyContact: "Emergency contact number/meeting link",
    enterNumberOrLink: "Enter number or link",
    assignee: "Assignee",
    searchOrAddLocation: "Search or add a location",
    moreDetails: "More details",
    addNote: "Add note...",
    financeAndNotes: "Finance and Notes",
    expenses: "Expenses",
    detailedDescription: "Detailed description",
    expenseDetailsPlaceholder: "You can fill in expense details, payment methods, etc...",
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
    today: "今天",
    newEvent: "新建日程",
    whatWouldYouLikeToDo: "你想做什么？",
    addAttachment: "添加附件",
    timeSetting: "时间设置",
    allDay: "全天",
    executionTime: "执行时间",
    duration: "时长",
    repeat: "重复",
    doesNotRepeat: "不重复",
    repeatDaily: "每天",
    repeatWeekly: "每周",
    repeatMonthly: "每月",
    forWhom: "为了谁 (FOR)",
    everyone: "所有人",
    me: "我",
    showMoreOptions: "显示更多选项",
    hideMoreOptions: "收起更多选项",
    notes: "备注",
    remind: "提醒",
    remindNone: "无",
    remindOnTime: "事件开始时",
    remind5Min: "提前 5 分钟",
    remind15Min: "提前 15 分钟",
    remind30Min: "提前 30 分钟",
    remind1Hour: "提前 1 小时",
    taskPriority: "任务优先级",
    urgent: "紧急",
    generally: "一般",
    emergencyContact: "紧急联系电话 / 会议链接",
    enterNumberOrLink: "输入号码或链接",
    assignee: "执行人",
    searchOrAddLocation: "搜索或添加地点",
    moreDetails: "更多详情",
    addNote: "添加备注…",
    financeAndNotes: "财务与备注",
    expenses: "费用",
    detailedDescription: "详细说明",
    expenseDetailsPlaceholder: "可填写费用明细、支付方式等…",
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
    today: "今天",
    newEvent: "新建日程",
    whatWouldYouLikeToDo: "你想做什麼？",
    addAttachment: "新增附件",
    timeSetting: "時間設定",
    allDay: "全天",
    executionTime: "執行時間",
    duration: "時長",
    repeat: "重複",
    doesNotRepeat: "不重複",
    repeatDaily: "每天",
    repeatWeekly: "每週",
    repeatMonthly: "每月",
    forWhom: "為了誰 (FOR)",
    everyone: "所有人",
    me: "我",
    showMoreOptions: "顯示更多選項",
    hideMoreOptions: "收起更多選項",
    notes: "備註",
    remind: "提醒",
    remindNone: "無",
    remindOnTime: "事件開始時",
    remind5Min: "提前 5 分鐘",
    remind15Min: "提前 15 分鐘",
    remind30Min: "提前 30 分鐘",
    remind1Hour: "提前 1 小時",
    taskPriority: "任務優先級",
    urgent: "緊急",
    generally: "一般",
    emergencyContact: "緊急聯絡電話 / 會議連結",
    enterNumberOrLink: "輸入號碼或連結",
    assignee: "執行人",
    searchOrAddLocation: "搜尋或新增地點",
    moreDetails: "更多詳情",
    addNote: "新增備註…",
    financeAndNotes: "財務與備註",
    expenses: "費用",
    detailedDescription: "詳細說明",
    expenseDetailsPlaceholder: "可填寫費用明細、支付方式等…",
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
