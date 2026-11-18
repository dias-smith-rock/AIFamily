# Apple Intelligence 拍照与语音建任务 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在支持设备上优先用苹果本地能力，把照片或语音转换成用户确认后保存的 task。

**Architecture:** 输入采集 → 能力检测 → 苹果或用户主动选择的云端 provider → 统一草稿及校验 → 现有 EditTaskView/CreateTaskView 保存链路。识别 provider 不直接写数据库；Siri 仅作为后续草稿入口。

**Tech Stack:** Swift/SwiftUI、Vision、FoundationModels（26+ 文本、27+ 图片）、Speech、AVFoundation、App Intents（可选阶段）、Supabase Edge Functions/Storage、DeepSeek/Gemini 既有云端配置。

**Spec:** `docs/superpowers/specs/2026-11-18-apple-intelligence-task-creation-design.md`

**Status:** 待用户审核的实施草案；阅读本文件不构成开工批准。规格中的 C 路线、草稿确认、会员策略和 Siri 分期均尚待审核。

## Global Constraints

- 保持 App 最低 iOS 18.6。FoundationModels 文本路径 iOS 26+；图片附件路径 iOS 27+，分别隔离 SDK/运行时检查。
- 所有 provider 只生成草稿；用户确认才走现有保存流程。task 保存继续要求联网。
- 本地失败不静默上传；云端按次选择。原始语音不上传自家服务器；旧 Speech 在线模式单独征得同意。
- 单次录音最多 60 秒；云端文本输入最多 6000 个字符，超限返回 400。
- 相对日期以 referenceInstant + 应用 effectiveTimeZone 解释；selectedCalendarDay 仅辅助月历定位/建议。
- 保留现有拍照 AI 会员控制；语音是否共用相同控制按规格审核结果实施。
- 先支持单任务草稿；无时间不伪造 09:00，不自动配置重复任务，不自动创建账本记录。
- 生产日志不包含原图、OCR/转写原文、任务正文、签名 URL；首期不依赖 PCC entitlement。
- iOS 独立实现，无数据库 schema 迁移；供应商密钥保留在 Edge Functions 环境。

## Review Focus

- 晚上、跨年和 DST 输入：按指定时区解释，缺失/歧义时间提醒确认。
- 同名家人及识别中切组织：不得自动指派错人或写入旧组织。
- Speech 临时片段反复修订及录音中断：正文不重复、麦克风释放、取消后无延迟草稿覆盖。
- 旋转照片、四边形裁切与月历多列：只识别目标区域，保留行列关系或请求缩小范围。
- AI 不可用/断网/云超时/重复操作：明确状态、不静默外传、不重复创建、不谎报保存成功。

---

## 文件与接口约定

本计划不重构整个表单。新识别逻辑放 `reminder/Services/TaskCreation/`，采集 UI 放 `reminder/Views/TaskCreation/`，共享草稿放 `reminder/Models/TaskCreationDraft.swift`。实际表单依次经过 `TaskListView` → `EditTaskView` → `CreateTaskView`，必须沿用此链路。

共享类型在任务 1 一次定义，后续任务引用：

- `TaskParsingContext: Sendable`：`referenceInstant: Date`、`selectedCalendarDay: Date`、`timeZoneIdentifier: String`、`localeIdentifier: String`、`householdId: UUID`。
- `TaskRecognitionInput: Sendable`：`.text(String)` / `.photo(jpegData: Data)`；图片在进入前完成方向和裁切归一。原图附件单独持有。
- `ExtractedTaskFields: Sendable`：标题/备注、开始与截止的日期时间组件、全天、时长、金额、地点、成员名称提示、优先级、scheduled/flexible 提示、缺失/歧义标志与原文。不放 membership UUID。
- `protocol TaskDraftExtractor: Sendable { func extract(_ input: TaskRecognitionInput, context: TaskParsingContext) async throws -> ExtractedTaskFields }`。
- `TaskCreationDraft` 采用规格字段，持有 UI 图片，因此由 MainActor 管理，不强行标 Sendable。
- `TaskDraftValidator.validate(_:context:) throws -> ValidatedTaskFields` 为纯逻辑；`TaskDraftBuilder.build(fields:profiles:memberships:attachment:) -> TaskCreationDraft` 在 MainActor 映射合法成员和附件。
- `TaskRecognitionAvailability`：localReady / downloading / unavailable(reason)，文字、图片、Speech 语言分别报告；`TaskRecognitionCapabilities.snapshot(locale:) async -> TaskRecognitionCapabilitySnapshot`。
- `TaskRecognitionPolicy`：localOnly / cloudAllowed；只有本次用户选择后才能构造 cloudAllowed 请求。
- `@MainActor TaskCreationCoordinator.recognize(_:context:policy:) async`；`cancel()`；只读 `state` 为 idle/recognizing/needsCloudChoice(reason)/ready(TaskCreationDraft)/failed(message)。保存不属于此协调器。

### Task 0: 先核对基线并验证苹果能力

**Files:** 记录 `docs/apple-task-recognition-evaluation.md`；可用项目外 throwaway harness，不修改产品入口。

**Interfaces:** 消费当前 SDK、规格和测试设备；产出设备能力/质量记录及继续或调整建议。

- [ ] 核对 `git status` 与 master/origin/master 差异，保留现有用户改动；在当前功能分支处理相关新提交，不能盲目重置。记录实施基准 commit。
- [ ] 查看可用 Xcode/SDK 与 `xcodebuild -list -project reminder.xcodeproj`，确认 iOS 27 SDK、App scheme、deployment target；缺工具链先补环境或暂缓 27 适配，不提高 App 最低版本。
- [ ] 用一张中文通知、一张旋转票据、一张目标月历区域验证 Vision；可用 AI 真机验证文字结构化与 27 图片输入；Speech 分别检查当前语言 supported/installed/downloadable。
- [ ] 记录真机输出和延迟、错误码、AI 开关/语言/地区；无设备的项目标“未验证”，不得替换为模拟器成功结论。
- [ ] 决定 C 路线是否仍可行；若直接图片质量不如 OCR，则 27 同样优先 OCR，须更新设计并交用户审核显著变动。

### Task 1: 统一草稿模型和表单适配

**Files:** Create `reminder/Models/TaskCreationDraft.swift`、`reminder/Services/TaskCreation/TaskDraftExtractor.swift`、`TaskDraftValidator.swift`、`TaskDraftBuilder.swift`；Modify `ScheduleViewModel.swift`、`TaskListView.swift`、`EditTaskView.swift`、必要时 `CreateTaskView.swift`；Delete `Models/AIPrefilledTaskDraft.swift`（迁移结束后）；Create `reminderTests/TaskDraftValidatorTests.swift`、`TaskDraftBuilderTests.swift`；Modify `reminder.xcodeproj/project.pbxproj` 添加单元测试 target。

**Interfaces:** 消费现有 AIParsedTaskPayload、家人 roster、表单 initial 参数；产出上述共享契约与新的通用预填绑定。

- [ ] 建立只测试纯业务逻辑与 fake provider 的单元测试 target；保持 App/widget 构建配置，不能把 FoundationModels 27 类型泄露给 18.6 路径。
- [ ] 写失败用例：照片草稿附件成对存在、语音无附件；空标题被拒；同名成员保留候选且不自动选中；未知 UUID 不接受；无日期为待办；明确日程缺时刻产生需补充标志。
- [ ] 写时间边界用例：固定 referenceInstant，选中日不同仍按 referenceInstant 解释“明天”；跨年；America/Los_Angeles DST 不存在/重叠时间必须标记确认；end < start、负时长/金额不得静默保存。
- [ ] 实现 DTO、纯 validator、MainActor builder；给云端 DTO 添加 adapter，不在本任务改变云端请求。
- [ ] 迁移原有照片预填到 TaskCreationDraft，`TaskListView` 对无附件传空数组；有附件沿用原 JPEG；待补充项在已有表单中提示并阻止不完整日程提交。
- [ ] 运行新 target 的 validator/builder 测试及 App 构建；手工确认旧云端照片→表单和纯手工建任务均正常，再提交该任务。

### Task 2: 本地 OCR、端侧提取和可取消能力路由

**Files:** Create `Services/TaskCreation/TaskRecognitionCapabilities.swift`、`VisionTaskTextRecognizer.swift`、`AppleTaskDraftExtractor.swift`、`AppleImageTaskDraftExtractor.swift`、`TaskCreationCoordinator.swift`；Create `reminderTests/TaskRecognitionRoutingTests.swift`、`VisionTaskTextRecognizerTests.swift`。

**Interfaces:** 消费 TaskDraftExtractor/Context，产出纯 ExtractedTaskFields 与协调器 state；旧云端图片 service 以 adapter 注入。

- [ ] 写路由失败用例：18.6 不触碰新 API；26 使用 OCR+文字；27 图片可用才直传；AI 关闭/模型下载中/不支持语言进入 needsCloudChoice；localOnly 时 fake cloud 调用次数始终为 0。
- [ ] 写 OCR fixture 用例：方向旋转、四边形透视、Vision 坐标翻转、月历目标格与邻格隔离；模糊/空图返回可解释错误。图片 fixture 使用自制测试图，不含用户数据。
- [ ] 实现 VisionTaskTextRecognizer：实际裁切/透视校正后 OCR，不只把四边形转 bounding box；保留行框、按区域整理文字。输入给 provider 的 photo 数据为校正后的图，附件仍为原图。
- [ ] 实现 26 文字 @Generable schema，输出日期组件/时区线索并经 validator 校验。输入材料作为数据处理，未知值留空；不暴露写 task 工具。
- [ ] 隔离 27 图片 Attachment 适配与模型能力检查；降级为本地 OCR+文字不需要上传授权，转云端必须请求选择；处理上下文超限、拒绝及系统不可用。
- [ ] 实现请求代次和取消：新请求替换旧请求、组织上下文变化作废旧回包、注销清空，session 不并发复用；测试取消/切组织后迟到结果不进入 ready。
- [ ] 运行路由/OCR测试、18.6 最低部署 App 构建及 26/27 真机样本；记录模型识别结果后提交。

### Task 3: 拍照入口切换到苹果优先

**Files:** Modify `ViewModels/ScheduleViewModel.swift`、`Views/Schedule/TaskListView.swift`、`Utilities/AIPhotoTaskCreationLogger.swift`、`Utilities/PremiumLimits.swift`（只在审核要求调整时）；Create `Views/TaskCreation/TaskRecognitionStatusView.swift`；Update `Localization/Schedule.xcstrings` 和 `L10n+Schedule.swift`；Create `reminderTests/PhotoTaskCreationFlowTests.swift`。

**Interfaces:** 消费 TaskCreationCoordinator，产出 TaskListView 已有确认 sheet 的通用草稿；仍用原会员入口和保存路径。

- [ ] 写 fake 流程测试：有会员权限才开始；本地成功不上传临时图；本地失败先提示，未点“使用云端识别”不能调用云端；用户取消不触发保存；双击不产生两个 sheet。
- [ ] 将 `confirmCrop`/`processCapturedImage` 交给协调器，明确区分原图附件与裁切识别图。根据 appSettings 的时区和当前时刻创建 TaskParsingContext，不再以选中日代替真实当前时间。
- [ ] 增加状态与操作：本地处理中、模型下载/不可用、重试、编辑文字、使用云端、取消；错误后保留原始素材，组织切换后重新核对。
- [ ] 在通用表单显示识别原文和需确认项；用户移除附件后保存不得上传原图。只记录 provider、耗时、错误分类与字数。
- [ ] 运行照片流程 fake 测试；真机本地处理阶段观测无识别网络请求，并验证保存时才发生 task/附件同步；回归旧云端临时图清理后提交。

### Task 4: 云端文本备选与共享解析上下文

**Files:** Create `supabase/functions/_shared/task-parsing.ts`、`parse-create-task-from-text/index.ts`、该目录 `deno.json`、`Services/TaskCreation/CloudTaskDraftExtractor.swift`、`supabase/functions/tests/task-parsing_test.ts`；Modify `parse-create-task-from-images/index.ts`、`Services/AITaskParserService.swift`、`supabase/functions/README.md`。

**Interfaces:** `POST parse-create-task-from-text` body 为 `{text, reference_instant, selected_calendar_day, time_zone, locale}`；有效响应保持 `{success, task}` 与图片任务字段兼容。图片接口添加同样的可选 context 字段并保留 image_url/target_date/recognition_region。

- [ ] 写函数测试：空文本、6001 字符输入返回 400；无有效 JWT 返回 401；供应商失败返回受控错误；返回 task 符合既有 DTO；旧图片请求仍可解析；新请求按客户端时区、reference_instant 解释，移除固定年份。
- [ ] 抽取公共 prompt、输入校验与日期上下文，定义旧客户端缺上下文的明确默认行为；对未知/缺时刻保留 null，不再强制 09:00。供应商输出必须 schema/业务校验，避免直接透传错误 HTML 或敏感响应。
- [ ] 新函数复用服务端 DeepSeek 配置，设置有限网络超时；与图片接口同样执行真实用户鉴权，不只接受任意 Bearer 值。增加基本请求长度/频率防护并记录部署配置。
- [ ] App adapter 的 cloudAllowed 文字请求只上传确认后的转写，不上传音频；图片 adapter 延用现有 upload/delete 生命周期，覆盖上传后签名 URL 生成失败、超时和取消的清理。
- [ ] 生产关闭 OCR 原文 debug 日志/响应和图片签名 URL 日志；本地诊断也不打印原始正文。
- [ ] 用 Deno 本地测试验证 handler 与供应商 stub；更新部署命令、JWT 设置及 secrets 名称说明。本任务实施获批后才部署到对应测试环境；不触碰生产默认配置。

### Task 5: App 内语音采集到任务草稿

**Files:** Create `Services/TaskCreation/SpeechTaskTranscriber.swift`、`ModernSpeechTaskTranscriber.swift`、`LegacySpeechTaskTranscriber.swift`、`ViewModels/VoiceTaskCreationViewModel.swift`、`Views/TaskCreation/VoiceTaskCreationSheet.swift`；Modify `Views/Schedule/CreateTaskView.swift`、`CreateTaskFlatForm.swift`、`TaskListView.swift`、`reminder.xcodeproj/project.pbxproj`、`Localization/Schedule.xcstrings` 和对应 L10n；Create `reminderTests/VoiceTaskCreationTests.swift`。

**Interfaces:** `SpeechTaskTranscriber` 暴露 `start(locale: Locale) async throws -> AsyncThrowingStream<SpeechTranscriptUpdate, Error>`、`stop() async`、`cancel() async`；update 含 segmentID/text/isFinal，用 segmentID 替换临时内容，最终片段只提交一次。Voice VM 把最终文字交给同一 coordinator，不直接 save。

- [ ] 写失败用例：麦克风拒绝、无声结果、临时片段替换不重复、60 秒停止、stop 等待最后片段、cancel 丢弃迟到回包、音频中断和进入后台释放资源。
- [ ] 实现 AVAudioSession/AVAudioEngine 录音及格式转换；新 Speech 用可支持的 locale 和 AssetInventory 下载，SpeechTranscriber 不可用时评估 DictationTranscriber；18.6 走 SFSpeechRecognizer 的 supportsOnDeviceRecognition 检查。
- [ ] 旧识别器先强制本地；不支持时停止并说明在线模式。只有用户明确选择后才允许 Apple 网络识别，不能因联网可用自动上传。
- [ ] 为 App Debug/Release 添加麦克风、Speech 权限说明，按 API 需要申请授权；下载状态、拒绝、失败允许改为文字。录音结束后释放临时音频，不持久化原音频。
- [ ] 接通日程任务入口与表单麦克风，两处共享同一个组件；停止后允许编辑文字并生成草稿，再由表单确认。会员判断按规格审批结果与拍照一致执行。
- [ ] 运行 fake transcription/VM 测试；真机测试普通话/英语、蓝牙/来电、后台/取消；在 AI 可用与不可用机型分别验证本地与用户选择云端路径后提交。

### Task 6: 发布前质量与兼容验收

**Files:** Update `docs/apple-task-recognition-evaluation.md`；必要时补充以上有具体回归价值的测试。

**Interfaces:** 消费完整 App 内识别流程；产出样本逐字段评分、设备矩阵与发布建议。

- [ ] 执行规格的 30 图+30 段语音样本；标注内容正确性、需修正字段、provider、耗时、错误；明确日期/时间正确率 ≥95%、有效草稿 ≥90% 为建议门槛，未达标需评估改进/收紧范围。
- [ ] 覆盖跨年/DST、未知成员/同名、长输入、月历多列、无文字图、无声、网络断开、AI 开关变化、云端鉴权/超时/清理、取消/重复点击及切组织的行为。
- [ ] 回归普通建任务、既有图片云识别、附件上传/移除、任务权限、通知及小组件刷新；验证离线仅能生成本地草稿，保存失败文案真实。
- [ ] 运行相关测试 target、Deno tests 和 App/widget 构建；只在有目标 iOS 设备/模拟器时宣称对应版本验证通过，记录任何未覆盖设备。
- [ ] 汇总实际结果与生产部署所需步骤供审核；实施授权不自动代替用户尚未给出的生产发布指令。

### Task 7: Siri / 快捷指令入口（后续独立批准）

**Files:** Create `reminder/Intents/PrepareTaskDraftIntent.swift`、`TaskAppShortcuts.swift`、`Models/PendingTaskCreationRequest.swift`；Modify `Utilities/AppRouter.swift`、`ContentView.swift`、`Views/Schedule/TaskListView.swift`、相关本地化；Create `reminderTests/TaskCreationIntentRoutingTests.swift`。

**Interfaces:** AppIntent 接收 `text: String`，`perform() async throws -> some IntentResult` 只准备待处理草稿请求并打开 App。路由请求含 UUID、文本、createdAt，不包含已信任组织/成员授权。

- [ ] 写失败用例：冷启动、未登录、Face ID 未解锁、多组织、重复消费、过期请求与用户取消；必须在 bootstrap/身份确认后只消费一次，不调用任务写服务。
- [ ] 实现 AppShortcut 注册与 App 内待处理请求路由；首版只处理系统提供的文字参数，缺内容时由 Siri 参数解析或 App 补充，不依赖系统任意屏幕/相机访问。
- [ ] 在 App 中复用当前 coordinator 和确认表单；多组织让用户确认目的组织；取消/注销清理 pending request，不将内容编码进 URL。
- [ ] 真机测试可用语言短语、Siri 传参及冷启动；返回“请在 App 中确认”而非“已创建”。完成后回归 App 内照片和语音入口并提交。

## 自检与交付说明

本计划逐项覆盖规格的本地/云端路由、版本保护、权限、草稿确认、联网保存、日期和成员校验、素材生命周期、会员控制与 Siri 分期。类型及文件名是提议接口，不是已存在的实现。测试需在实施阶段建立；本次只写文档，未运行识别样本、产品构建或测试。

建议先批准任务 0 至 6，完成拍照与语音，再单独决定是否做任务 7。P0 质量/覆盖不达预期时先修订方案，不直接扩大实现。
