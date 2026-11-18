# 拍照与语音创建任务：Apple Intelligence 方案草案

日期：2026-11-18（Asia/Shanghai）  
状态：**待用户审核，尚未批准实现**。以下产品默认值均为方案建议，不代表用户已同意。  
分支：`codex/apple-intelligence-task-plan`，基于本地 master `c8cae80`。本地记录显示 master 比 origin/master 落后 1 个提交；本次未 fetch、pull 或合并，实施前应重新核对差异。

## 1. 用户目标与范围

用户希望通过拍照和说话创建 task；手机支持苹果 AI 时优先利用苹果能力。先解释可行性、给出实现细节与计划，用户决定是否开工。

建议首期覆盖：App 内拍照/选图、App 内语音、单任务草稿预填、人工确认、现有任务保存。日程（scheduled）与待办（flexible）共用入口。保留图片作为可选任务附件。支持简体中文、繁体中文、英语的可用能力检测与验证；不承诺所有口音或语言混说都同样准确。

后续独立阶段：通过 Siri / 快捷指令打开文字任务草稿。首期不包含多任务批量保存、复杂重复任务的自动配置、Android 对等实现或后台直接创建；用户明确说多件事时提示选一件，避免静默丢失。后续重复任务由表单手动配置。

## 2. 项目现状与改动落点

| 部位 | 当前实现与影响 |
| --- | --- |
| `reminder/ViewModels/ScheduleViewModel.swift` | `presentCrop` → `confirmCrop` → `processCapturedImage`；压缩图、调用服务、匹配成员、生成预填草稿；拍照识别已有会员判断。 |
| `reminder/Services/AITaskParserService.swift` | 上传临时图片到 Supabase Storage、生成 600 秒签名 URL、调用 `parse-create-task-from-images`、解码字段、删除临时图片；本地识别不应调用上传函数。 |
| `supabase/functions/parse-create-task-from-images/index.ts` | Gemini OCR → DeepSeek 文本结构化。已有年份 2026、Asia/Hong_Kong 假设，扩展时应改成显式上下文。当前部署环境与密钥是否可用未实测。 |
| `reminder/Models/AIPrefilledTaskDraft.swift` | 强制包含 UIImage 和 JPEG，不能直接容纳纯语音草稿，需要迁移为可选附件的通用模型。 |
| `reminder/Views/Schedule/TaskListView.swift:169` | 实际使用 `EditTaskView` 展示 AI 预填草稿。 |
| `reminder/Views/Schedule/EditTaskView.swift`、`CreateTaskView.swift` | 已有时间、截止日、金额、成员、附件、保存流程；`CreateTaskView.swift:2351` 的麦克风按钮为空实现。需同时审视 `CreateTaskFlatForm.swift` 的实际展示入口。 |
| `reminder/Services/AIParsingService.swift`、`ViewModels/AssistantViewModel.swift` | 旧助手使用简单规则：截取标题、上午/下午默认时间、医院关键词；并不是完善的 AI/语音识别。它还有独立写入路径，首期不从这里另造保存通道。 |
| `reminder/Services/Offline/TaskLocalWriteSupport.swift` | task 必须联网成功写服务端后才缓存；**离线识别草稿不等于离线保存任务**。 |
| `reminder/Utilities/AppSettingsManager.swift` | `effectiveTimeZone`、`effectiveCalendar` 应成为解析与展示的时间上下文。 |
| `reminder/Utilities/PremiumLimits.swift` | 拍照 AI 受 `canUseAIPhotoTaskCreation` 与 VIP 总开关控制；新 provider 应共用同一入口判断，避免绕过。语音首期建议沿用同一 AI 权益，等审核决定。 |
| `reminder.xcodeproj/project.pbxproj` | 主 App Debug/Release 最低 iOS **18.6**；部分 project/widget 配置是 26.0，不能把 App 全部视为 26+。当前未发现测试 target 或现成 App Intents 实现。 |

项目当前还包含组织/权限、日程、待办、账本、附件、通知、小组件与 Android/Web 目录。本计划只处理 iOS 的识别到现有 task 表单的链路。

## 3. “Siri AI”具体指什么

这是几组不同职责的公开 API，应分别判断可用性：

1. **Foundation Models**：调用 Apple Intelligence 的端侧模型，理解文字并输出结构化 Swift 类型。iOS 26+ 可使用文本解析；用 `SystemLanguageModel.default.availability` 检测设备资格、AI 开关及模型就绪状态，并单独检测语言支持。[生成与可用性说明](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
2. **图片直接理解（iOS 27+）**：最新公开 API 通过 `Attachment` / `ImageAttachmentContent` 将图片和提示一起输入模型，适合有版式的通知、票据和月历。`ImageAttachmentContent` 的平台起点为 iOS 27。实现仍需检查具体模型的能力并处理拒绝、不可用等错误；不能只看系统版本。[图片输入](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting) · [版本说明](https://developer.apple.com/documentation/foundationmodels/imageattachmentcontent)
3. **Vision**：本地 OCR，把图片中的文字和位置读出来，可覆盖不支持 Apple Intelligence 的手机；本身不负责理解任务。iOS 26 的推荐图片路径是 Vision OCR → Foundation Models。[Vision OCR](https://developer.apple.com/documentation/vision/recognizing-text-in-images)
4. **Speech**：语音转文字，不是直接把音频塞进文字模型。iOS 26+ 优先 `SpeechAnalyzer` / `SpeechTranscriber`，用 `AssetInventory` 管理语言模型；设备或语言不支持时可考虑 `DictationTranscriber`。低版本用 `SFSpeechRecognizer` 并判断本地识别支持。Speech 的设备/语言资格与 Apple Intelligence 不相同。[SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) · [旧接口本地支持](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
5. **App Intents / App Shortcuts**：让 Siri、快捷指令发现应用动作并传入参数。首期之后可以添加“用本 App 创建任务草稿”；它不自动赋予 App 读取系统相机、任意截图、其他 App 屏幕或 Siri 全部上下文的权限。[AppIntent](https://developer.apple.com/documentation/appintents/appintent)

不能仅凭手机有 Siri 的新界面就判定这些 API 都能用。设备、系统、语言、地区、AI 设置及资源下载均可能影响可用性；中国大陆等地区按苹果实时支持说明和运行时检测处理，不在代码里猜测开放日期。[Apple Intelligence 获取条件](https://support.apple.com/en-us/121115)

苹果还提供 iOS 27+ Private Cloud Compute 路径，但涉及 managed entitlement、网络与用户配额；**建议首期不依赖它**，保留项目现有云端备选，未来单独评估。[PCC 接入条件](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)

## 4. 可选方案与推荐

| 方案 | 收益 | 代价 |
| --- | --- | --- |
| A. 仅苹果本地 | 识别不上传、没有第三方模型调用费用 | 覆盖受设备/地区/语言限制，复杂图片质量需要实测；无 AI 手机只能手动整理。 |
| B. 云端为主 | 最接近现有实现，识图 provider 兼容范围较广 | 依赖网络、上传素材和模型费用；没有实现支持设备优先使用苹果的目标。 |
| **C. 苹果优先 + 用户选择云端备选（推荐，待选择）** | 支持设备本地处理，兼顾现有手机与复杂素材 | 需要能力路由、统一草稿与两条识别路径的验收。 |

建议路线 C。用户尚未选定；计划按 C 写成可供批准的草案。识别失败时保留原素材和文字，让用户重试、编辑或主动使用云端；**不因本地失败静默上传**。

## 5. 能力与版本路由

| 条件 | 拍照/选图 | 语音 | 理解任务 |
| --- | --- | --- | --- |
| iOS 27+，模型及图片输入可用 | 裁切/方向归一后直接图片输入；需要时 OCR 辅助核对 | 新 Speech 本地转写，按语言资源支持路由 | 端侧结构化生成 |
| iOS 26，端侧文字模型可用 | Vision OCR；保留区域位置信息、按阅读顺序整理 | 新 Speech；不支持时退到本地兼容转写器 | 端侧结构化生成 |
| iOS 18.6+，或 AI 关闭/未就绪/不支持语言 | 可本地 OCR，或用户选择已有云端图片识别 | 有本地支持则转写；否则提示选择系统在线识别（另行同意）或打字 | 用户选择云端文本解析，或手动填表 |

新 API 全部做 `#available` 和对应编译 SDK 保护，保持 App 最低 iOS 18.6。iOS 27 路径需要含相关接口的 iOS SDK；本机命令行 SDK 有新 FoundationModels 定义，但本次没有验证完整 iOS 构建环境。

## 6. 用户流程（建议默认值）

### 拍照

已有相机/相册 → 裁切识别区域 → 本地能力检测 → 本地识别或提示云端选项 → 任务草稿表单 → 用户核对 → 现有保存路径。保留原图与识别裁切图的区别：识别只看裁切区域，附件默认原图，可在表单移除；本地识别不上传图，**确认保存且保留附件时才上传附件**。云端识别的临时图生命周期继续由已有服务管理。

图片没有可执行事项时提示用户补充，不把任意照片编成任务。月历/表格需保留位置或使用直接图像理解，不能把所有单元格文本无条件串起来。空白、模糊、复杂手写的识别效果通过真机样本确认，不承诺等同云端。

### 语音

任务创建入口提供“说话创建”；表单已有麦克风共用同一录音组件。点击开始/停止，实时展示文字，结束后可编辑文字并点“生成草稿”。建议单次上限 **60 秒**；只提交最终转写片段，临时结果用于 UI 更新，不能重复拼接。取消、切后台、音频中断时停止采集并释放麦克风；保留已完成转写供用户编辑，不自动继续录音。

只对当前选定语言申请和下载模型，展示下载/不可用状态。麦克风权限拒绝不影响文字建任务。旧版在线 Speech 必须先说明音频会提交苹果，获得该识别模式的用户同意；不偷偷切成在线。

### 草稿确认和保存

例如“明天下午三点带小明去打疫苗，提醒爸爸一起去”，生成标题、开始时间、地点文字与成员候选；同名成员或关系不确定则留待选择。展示识别原文/转写文本便于对照，用户修改后点击保存。识别本身无数据库副作用。

保存沿用表单现有权限、成员检查、附件、通知、小组件刷新与联网要求。生成完成前切换组织则丢弃旧组织绑定并重新核对；注销清理待处理内容。不要将模型生成的任何 UUID、权限或组织 ID 用作写入依据。

## 7. 数据契约与职责

新增 `reminder/Models/TaskCreationDraft.swift`，将图片、语音、文字统一到 `TaskCreationDraft`，包含：

- id、source（photo/voice/text/siri）、provider、sourceText、warnings。
- title、description、dueDate?、endDatetime?、isAllDay、durationMinutes?、costDisplay?、locationName?。
- assigneeMembershipIds、targetProfileIds、isPriorityUrgent、prefersFlexibleTask。
- attachmentImage? 与 attachmentJPEGData?（必须成对存在或成对为空）。

将现有 `AIPrefilledTaskDraft` 的消费者迁移至此模型后删除旧模型，避免图片专用与通用草稿两套状态。现有 `AIParsedTaskPayload` 保留为云端响应 DTO，不直接加 `@Generable`。

新增 `Services/TaskCreation/`：

- `TaskRecognitionCapabilities.swift`：统一枚举系统版本、可用性、语言、下载状态；每次开始前重新检测。
- `TaskDraftExtractor.swift`：输入文字/图片与 `TaskParsingContext`，输出可验证的 `ExtractedTaskFields`；协议暴露可替换实现，避免测试依赖真模型。
- `AppleTaskDraftExtractor.swift`：iOS 26+ `@Generable` DTO；iOS 27+ 隔离图像适配。只提取字段，不允许模型调用保存 task 的工具。
- `VisionTaskTextRecognizer.swift`：方向归一、按有效四边形透视校正后 OCR，读取 supported languages，输出文字/置信度/位置。
- `TaskDraftValidator.swift`：结构化字段归一化、日期校验、空标题、金额与成员歧义检查；低置信度是识别质量信号，不能当成概率准确度承诺。
- `TaskCreationCoordinator.swift`：路由、取消、请求代次校验、防止过期回包覆盖新草稿；提供需要用户授权云端的状态。
- `CloudTaskDraftExtractor.swift`：适配已有图片服务；文字走新文本 Edge Function。
- `SpeechTaskTranscriber.swift`：新旧 Speech 的统一流式协议，内部实现分别隔离版本。

`TaskParsingContext` 精确区分 `referenceInstant`（开始识别的真实当前时刻）、`selectedCalendarDay`（界面所选日期）、`timeZoneIdentifier`、`localeIdentifier`、`householdId`。

日期规则（推荐）：相对日期“明天”基于 referenceInstant 所在应用时区；selectedCalendarDay 只帮助选月历格或缺失日期时显示建议，不能偷偷改变“明天”的含义。与旧助手按选中日解析的行为有差异，实施时须在所有新入口统一并明确提示。缺时间不自动填 09:00：明确全天事件保留全天；无时间事项为待办；明确日程但要素不足标为待补充，用户确认时间前不保存为伪精确日程。跨年、夏令时不存在/重叠时刻需校验，歧义提示确认。

文字模型输入将通知/转写视为待提取数据，忽略其中的指令，字段未知留空；使用 `@Generable` 约束类型仍需业务校验。金额只作表单候选，首期不自动创建收入/支出记录。重复表达保留到备注并提示手动设置。

## 8. 云端兼容与隐私

- 新增 `supabase/functions/parse-create-task-from-text/index.ts`，鉴权与配置风格复用现有函数，DeepSeek 只做文本结构化。
- 抽取 `_shared/task-parsing.ts`，统一图片与文字 schema、显式时间/语言上下文。旧请求字段保持兼容；旧客户端不再强制锁定 2026，缺上下文用服务端实际当前时间/明确默认时区，返回/日志标记使用的上下文，不悄悄改变旧响应 key。
- 输入限制：文本最多 **6000 个字符**，函数返回 400 拒绝超限；端侧超上下文不静默截掉包含日期的尾部，提示缩小图片区域/编辑原文/选择云端。
- 不在 App 中放供应商 API key；服务端需要新增函数部署，但首期不要求 task 表迁移。
- 上传授权按次选择：图片云识别上传临时图；语音云备选默认仅上传用户确认的转写文字。原始录音不上传自家服务器，停止/取消后释放临时音频。旧 Speech 在线模式另走苹果并单独说明。
- 本地推理阶段不发网络请求；登录/组织读取与用户确认后的 task/附件同步仍可能联网。产品文案须说清“本地识别”，不能宣称整个 App 全程离线。
- 现有 `AIPhotoTaskCreationLogger` 和后端 OCR debug 会输出部分任务/文字内容；新链路只记录 provider、错误分类、耗时与字数。实施时关闭生产 OCR 原文、签名 URL、任务内容日志及 debug 响应。

## 9. Siri 阶段的边界

新增 `Intents/PrepareTaskDraftIntent.swift` 与 `TaskAppShortcuts.swift`，接收一个自然语言 `String` 参数。`perform()` 只把输入交给 App 内待处理请求并打开 App；通过登录、Face ID、组织选择后调用同一识别协调器与确认表单。多组织不凭 Siri 猜测，用户在表单确认所属组织。用户取消不创建任务。Siri 对话是否能一次完整传入内容由真机短语/参数测试确定，不保证任意自然语言都能匹配。

通过进程内路由或不包含敏感原文的请求 ID 传递输入；不把完整家庭信息放 URL 或日志。`AppRouter` 维护 pending request，`ContentView` 在 bootstrap 完成后消费一次，防止冷启动重复打开/创建。Siri 第一版完成的是“打开并准备草稿”，不能播报“任务已创建”。

## 10. 工作分期、验收与评估

建议 P0 真机技术验证 → P1 通用草稿与照片苹果优先 → P2 语音与云端文字备选 → P3 Siri。P0 必须记录设备型号、系统、语言/地区、AI 状态、识别质量与耗时；有可用的 AI 真机和无 AI/关闭 AI 设备才有资格判断覆盖表现。预计工作量只能在 P0 后估算，本次不承诺准确率或性能实测结果。

发布前候选验收集至少 30 份图片（通知/票据/月历各 10）与 30 段短语音（普通话/英语/繁体中文使用场景各 10；语言支持以真机为准）。按字段核对标题、日期、开始/截止、金额和成员，不用“JSON 解析成功”代替识别正确。建议目标：明确表达的日期/时间正确率 ≥95%，有效单任务形成可编辑草稿 ≥90%；**这是发布建议门槛，尚无实测依据**。达不到则收紧本地适用范围或延后发布。记录中位/p95 延迟后再制定性能门槛。

必须验证：iOS 18.6、26、27 路由；AI 关闭/下载中；语言未安装/不支持；麦克风拒绝；来电/蓝牙/后台取消；无文字图片；旋转/四边形裁切/月历串行错配；跨年/时区/无具体时间；同名成员；切换组织；重复点击；云端超时/鉴权/上传失败及临时文件清理；离线能本地生成但不能谎报保存成功；原有拍照云识别和普通建任务不回归。

## 11. 审核时请决定的产品项

1. 是否采用 C：苹果优先，用户主动选择云端备选？
2. 是否接受所有识别先生成草稿，点保存后才创建 task？
3. 是否首期先做 App 内拍照和语音，Siri 唤起放在后续独立阶段？
4. AI 语音是否沿用现有拍照 AI 的会员规则？

其余细节按本文建议可调整。批准前只产生文档，不修改产品代码、部署服务或调用付费识别。
