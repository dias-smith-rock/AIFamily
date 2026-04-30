# AIFamily MVP 验收清单

## 基础闭环
- 管理端登录（Apple / Magic Link / Phone OTP）可触发对应流程。
- AI 助手可解析输入并生成预检卡片，确认后写入 `tasks`。
- Family 可创建影子成员并生成邀请链接。
- Feedback 可接收语音反馈并展示到消息流。

## Basic / Pro 分层
- Basic: 语音卡片不展示 AI 转录文本。
- Pro: 语音卡片展示 AI 转录文本。
- Basic 历史消息显示 30 天。
- Pro 历史消息可长期保留（策略由服务端执行）。

## 关键容错
- 空状态、筛选后空、异常态分别展示正确文案。
- 网络失败后“重新加载”可恢复。
- Realtime 重复事件不应产生重复卡片。
