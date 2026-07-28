import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @EnvironmentObject private var appSettings: AppSettingsManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("isUserLoggedIn") private var isUserLoggedIn = false
    @AppStorage("requireFaceID") private var requireFaceID = false
    @StateObject private var groupSwitcher = GroupSwitcherCoordinator()
    @StateObject private var biometricManager = BiometricManager()
    @State private var shouldHideAppSwitcherSnapshot = false
    /// 冷启动 Splash：完成登录态与群组路由 bootstrap 前不展示主界面。
    @State private var isLaunchBootstrapComplete = false

    var body: some View {
        Group {
            if isLaunchBootstrapComplete {
                rootContent
            } else {
                SessionRestoreView()
            }
        }
        .environmentObject(groupSwitcher)
        .environment(\.isAnonymousUser, appRouter.isAnonymousUser)
        .animation(.easeInOut, value: isUserLoggedIn)
        .animation(.easeInOut, value: appRouter.isAnonymousUser)
        .animation(.easeInOut, value: biometricManager.isUnlocked)
        .animation(.easeInOut, value: appRouter.appState)
        .animation(.easeInOut, value: appRouter.selectedHouseholdId)
        .alert(L10n.Common.permissionChangeNotification, isPresented: newCreatorAlertBinding) {
            Button(L10n.Common.viewNow) {
                appRouter.enterNewlyAssignedCreatorHousehold()
            }
            Button(L10n.Common.close, role: .cancel) {
                appRouter.dismissNewCreatorAlert()
            }
        } message: {
            if let household = appRouter.newlyAssignedHousehold {
                Text(
                    String(
                        format: L10n.Family.youHaveBecomeTheCreatorOfAndHaveTheHigh.string(),
                        household.displayHouseholdName
                    )
                )
            }
        }
        .sheet(isPresented: $groupSwitcher.showSwitchGroupDialog) {
            SwitchGroupSheetView(coordinator: groupSwitcher)
                .environmentObject(appRouter)
                .environment(\.locale, appSettings.appLocale)
                .environment(\.layoutDirection, appSettings.layoutDirection)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $groupSwitcher.isShowingCreateOrganizationSheet) {
            CreateOrganizationSheet(
                organizationName: $groupSwitcher.newOrganizationName,
                organizationDescription: $groupSwitcher.newOrganizationDescription,
                inputError: $groupSwitcher.createOrganizationError,
                isSubmitting: groupSwitcher.orgRoutingViewModel.isCreating,
                onSubmit: {
                    await groupSwitcher.submitCreateOrganization(appRouter: appRouter)
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $groupSwitcher.showJoinGroupSheet) {
            JoinExistingGroupSheet(
                inviteCode: $groupSwitcher.joinCode,
                inputError: $groupSwitcher.joinInputError,
                isSubmitting: groupSwitcher.orgRoutingViewModel.isJoining,
                parseInviteCode: groupSwitcher.firstInviteCode(from:),
                onSubmit: {
                    await groupSwitcher.submitJoinGroup(appRouter: appRouter, locale: appSettings.appLocale)
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $appRouter.isPresentingVIPUpgrade) {
            NavigationStack {
                VIPSubscriptionView()
            }
            .environmentObject(appRouter)
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
        }
        .task(id: appRouter.appState) {
            if isLaunchBootstrapComplete,
               isUserLoggedIn,
               biometricManager.isUnlocked {
                _ = await NotificationManager.shared.requestAuthorizationIfNeeded()
            }
        }
        .task {
            guard isLaunchBootstrapComplete == false else { return }
            await runLaunchBootstrap()
        }
        .task(id: postLaunchForegroundBootstrapToken) {
            guard let postLaunchForegroundBootstrapToken else { return }
            _ = postLaunchForegroundBootstrapToken
            guard isUserLoggedIn else {
                Self.hasReportedLocationOnLaunchThisSession = false
                BackgroundLocationCoordinator.shared.stop()
                ForegroundLocationPersistScheduler.shared.stop(reason: "signedOut")
                ForegroundLocationPersistEligibility.shared.canPersist = false
                return
            }
            await runPostAuthForegroundServices()
        }
        .onChange(of: isUserLoggedIn) { _, loggedIn in
            guard isLaunchBootstrapComplete, loggedIn else { return }
            LoginFlowPerformanceTracing.mark(
                "contentView.isUserLoggedIn.changed",
                note: "loggedIn=true bootstrapTrigger=login",
                appRouter: appRouter
            )
            Task {
                await runAuthAndHouseholdBootstrap(vipLogTrigger: "登录后", bootstrapTrigger: "login")
                reconcileStaleLoginSession()
            }
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, _ in
            Task {
                refreshForegroundLocationSchedulerContext()
                await syncBackgroundLocationService()
                if await NetworkMonitor.shared.isConnected {
                    await reportLocationOnAppLaunchIfNeeded()
                }
            }
        }
        .onChange(of: appRouter.selectedMembershipId) { _, _ in
            Task {
                refreshForegroundLocationSchedulerContext()
                await syncBackgroundLocationService()
                if await NetworkMonitor.shared.isConnected {
                    await reportLocationOnAppLaunchIfNeeded()
                }
            }
        }
        .onChange(of: appRouter.appState) { oldState, newState in
            guard isLaunchBootstrapComplete else { return }
            if oldState != newState {
                LoginFlowPerformanceTracing.mark(
                    "router.appState.changed",
                    note: "from=\(oldState.perfTraceName) to=\(newState.perfTraceName)",
                    appRouter: appRouter
                )
            }
            reconcileStaleLoginSession()
        }
        .onChange(of: appRouter.hasCompletedAuthBootstrap) { _, _ in
            guard isLaunchBootstrapComplete else { return }
            reconcileStaleLoginSession()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Self.logAppOpenedIfNeeded()
                shouldHideAppSwitcherSnapshot = false
                Task {
                    await NotificationManager.shared.clearBadgeCount()
                    if isUserLoggedIn == false, AuthSessionHints.showsGuestLoginEntry {
                        await GuestSessionKeepAlive.refreshOnLoginScreenIfNeeded()
                    } else if appRouter.isAnonymousUser == false {
                        await GuestSessionKeepAlive.refreshWhileFormalUserActiveIfNeeded()
                    }
                    guard isUserLoggedIn, isLaunchBootstrapComplete else { return }
                    await runForegroundLocationBootstrap(vipLogTrigger: "App回到前台")
                    _ = try? await CalendarInboundSyncCoordinator.shared.syncIfConfigured(reason: "scenePhaseActive")
                }
            } else if newPhase == .inactive {
                ForegroundLocationPersistScheduler.shared.stop(reason: "sceneInactive")
                shouldHideAppSwitcherSnapshot = isUserLoggedIn && biometricManager.isUnlocked
            } else if newPhase == .background {
                Task {
                    await flushLocationBeforeEnteringBackground()
                }
                ForegroundLocationPersistScheduler.shared.stop(reason: "sceneBackground")
                shouldHideAppSwitcherSnapshot = isUserLoggedIn && biometricManager.isUnlocked
                if requireFaceID {
                    biometricManager.lockIfNeeded()
                }
                Task {
                    await preScheduleLocalNotifications()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskReminderNotificationTapped)) { notification in
            guard let tap = notification.object as? TaskReminderNotificationUserInfo.Tap else { return }
            Task { @MainActor in
                appRouter.preferHouseholdOnNextRefresh(tap.householdId)
                appRouter.pendingTaskReminderTap = tap
                await appRouter.refreshStateFromBackend()
                await fetchHouseholdsAndCheckCreatorRole()
                if appRouter.selectedHouseholdId != tap.householdId {
                    appRouter.consumePendingTaskReminderTap()
                    appRouter.goToHouseholdSelection()
                }
            }
        }
    }

    /// 冷启动完成后、登录态变化时触发位置/VIP 等前台服务（不再重复跑路由 bootstrap）。
    private var postLaunchForegroundBootstrapToken: String? {
        guard isLaunchBootstrapComplete else { return nil }
        guard isUserLoggedIn else { return "signedOut" }
        return "signedIn"
    }

    @ViewBuilder
    private var rootContent: some View {
        if isUserLoggedIn == false {
            LoginView()
        } else if requireFaceID && biometricManager.isUnlocked == false {
            LockScreenView(
                isAuthenticating: biometricManager.isAuthenticating,
                onUnlock: { biometricManager.authenticate() }
            )
            .onAppear {
                biometricManager.authenticate()
            }
        } else {
            authenticatedRoot
                .blur(radius: shouldHideAppSwitcherSnapshot ? 20 : 0)
        }
    }

    @ViewBuilder
    private var authenticatedRoot: some View {
        switch appRouter.appState {
        case .activeMember where appRouter.selectedHouseholdId != nil:
            AppTabRootView()
                .id(appBootstrap.sessionRevision)
                .onAppear {
                    LoginFlowPerformanceTracing.mark(
                        "rootContent.appTabRootView.attached",
                        appRouter: appRouter
                    )
                }
        case .householdSelection:
            HouseholdSelectionView()
        case .orgRouting:
            OrgRoutingView()
        case .pendingApproval:
            PendingView()
        case .activeMember:
            householdRoutingFallback
        case .unauthenticated:
            authenticatedSessionBootstrapPlaceholder
        }
    }

    /// 已登录但尚未选出当前群组：优先组织选择页，无可用群组时回到创建/加入入口。
    private var householdRoutingFallback: some View {
        Group {
            if appRouter.selectableHouseholds.isEmpty {
                OrgRoutingView()
            } else {
                HouseholdSelectionView()
            }
        }
    }

    @ViewBuilder
    private var authenticatedSessionBootstrapPlaceholder: some View {
        #if canImport(Supabase)
        if appRouter.isResolvingHouseholdRouting {
            routingBootstrapPlaceholder
        } else if appRouter.hasPersistedSupabaseSession {
            OrgRoutingView()
        } else {
            routingBootstrapPlaceholder
        }
        #else
        routingBootstrapPlaceholder
        #endif
    }

    private var routingBootstrapPlaceholder: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
    }

    private static var hasLoggedAppOpenThisSession = false
    private static var hasReportedLocationOnLaunchThisSession = false
    private static var launchBootstrapFinishedAt: CFAbsoluteTime?

    private static func logAppOpenedIfNeeded() {
        guard hasLoggedAppOpenThisSession == false else { return }
        hasLoggedAppOpenThisSession = true
        AnalyticsManager.log(event: .appOpened)
    }

    private var newCreatorAlertBinding: Binding<Bool> {
        Binding(
            get: { appRouter.showNewCreatorAlert },
            set: { isPresented in
                if isPresented == false {
                    appRouter.dismissNewCreatorAlert()
                }
            }
        )
    }

    @MainActor
    private func runLaunchBootstrap() async {
        _ = await NetworkMonitor.shared.ensureInitialPathReady()
        let networkConnectedAtStart = await NetworkMonitor.shared.isConnected

        LaunchBootstrapPerformanceTracing.beginColdStartTraceIfNeeded(isUserLoggedIn: isUserLoggedIn)
        LaunchBootstrapPerformanceTracing.mark(
            "launchBootstrap.begin",
            note: "networkConnectedAtStart=\(networkConnectedAtStart)",
            appRouter: appRouter
        )

        if isUserLoggedIn, networkConnectedAtStart == false {
            OfflineColdStartPerformanceTracer.beginTrace(networkConnectedAtStart: networkConnectedAtStart)
        }

        let isFreshInstall = AuthSessionHints.prepareForFreshInstallIfNeeded()
        AnonymousBindPromptStore.clearStaleGroupActionPendingIfNeeded()
        LaunchBootstrapPerformanceTracing.mark("launchBootstrap.prepareFreshInstall.done", appRouter: appRouter)

        LegacyGuestDataCleaner.removeLegacyLocalTrialKeysIfNeeded()
        RevenueCatSubscriptionService.shared.configure(appRouter: appRouter)
        LaunchBootstrapPerformanceTracing.mark("launchBootstrap.revenueCat.configure.done", appRouter: appRouter)

        if isFreshInstall {
            await SupabaseAuthManager.clearSupabaseSessionForFreshInstallIfNeeded()
            LaunchBootstrapPerformanceTracing.mark(
                "launchBootstrap.clearSupabaseSessionForFreshInstall.done",
                appRouter: appRouter
            )
        }

        DualSessionTokenSync.registerIfNeeded()
        LaunchBootstrapPerformanceTracing.mark("launchBootstrap.dualSessionTokenSync.registered", appRouter: appRouter)

        if networkConnectedAtStart {
            await LaunchBootstrapPerformanceTracing.measure(
                "launchBootstrap.bootstrapRevenueCatIfNeeded",
                appRouter: appRouter
            ) {
                await SupabaseAuthManager.bootstrapRevenueCatIfNeeded(appRouter: appRouter)
            }
        } else {
            LaunchBootstrapPerformanceTracing.mark(
                "launchBootstrap.bootstrapRevenueCatIfNeeded.skipped",
                note: "offline",
                appRouter: appRouter
            )
        }

        var revealedMainUI = false

        let isAnonymousUser = networkConnectedAtStart
            ? await SupabaseAuthManager.isAnonymousUser()
            : SupabaseAuthManager.isAnonymousUserFromPersistedSession()

        let shouldAutoEnterAsGuest =
            isAnonymousUser
            || (isUserLoggedIn == false && AuthSessionHints.showsGuestLoginEntry)

        if isAnonymousUser, isUserLoggedIn == false, networkConnectedAtStart == false {
            OfflineColdStartPerformanceTracer.beginTrace(networkConnectedAtStart: networkConnectedAtStart)
        }

        if shouldAutoEnterAsGuest {
            LaunchBootstrapPerformanceTracing.mark(
                "launchBootstrap.branch.guestAutoLogin",
                note: "networkConnectedAtStart=\(networkConnectedAtStart) hadAnonymousSession=\(isAnonymousUser)",
                appRouter: appRouter
            )
            GuestLoginPerformanceTracer.beginTrace(
                entryPath: isAnonymousUser ? "guestColdStart" : "guestColdStartDefault"
            )
            // 新游客首次进入：清掉残留 pending，避免未做实质操作就弹绑定引导。
            if isAnonymousUser == false {
                AnonymousBindPromptStore.clearPending()
            }

            appRouter.beginHouseholdRoutingResolve()
            defer { appRouter.finishHouseholdRoutingResolveAfterRefresh() }
            let dismissedSplashEarly = dismissLaunchSplashEarlyIfOfflineLoggedIn(
                networkConnectedAtStart: networkConnectedAtStart
            )
            if dismissedSplashEarly == false {
                appRouter.goToOrgRouting()
                LaunchBootstrapPerformanceTracing.mark("launchBootstrap.goToOrgRouting", appRouter: appRouter)
            }

            do {
                let result = try await LaunchBootstrapPerformanceTracing.measure(
                    "launchBootstrap.guestResumeOrSignIn",
                    appRouter: appRouter
                ) {
                    try await SupabaseAuthManager.resumeOrSignInAsGuest(appRouter: appRouter)
                }
                await LaunchBootstrapPerformanceTracing.measure(
                    "launchBootstrap.guestFinishSignInBootstrap",
                    note: "userId=\(result.userId.uuidString.lowercased()) resumed=\(result.resumed)",
                    appRouter: appRouter
                ) {
                    await SupabaseAuthManager.finishGuestSignInBootstrap(
                        appRouter: appRouter,
                        userId: result.userId
                    )
                }
                isUserLoggedIn = true
                revealedMainUI = true
                reconcileStaleLoginSession()
                LaunchBootstrapPerformanceTracing.mark("launchBootstrap.reconcileStaleLoginSession.done", appRouter: appRouter)
            } catch {
                GuestLoginPerformanceTracer.cancelTrace(reason: "coldStartFailed \(error.localizedDescription)")
                LaunchBootstrapPerformanceTracing.cancelTrace(reason: "guestColdStartFailed")
                SupabaseAuthManager.softExitToLogin(appRouter: appRouter)
                isUserLoggedIn = false
            }

            if isLaunchBootstrapComplete == false {
                withAnimation(.easeInOut) {
                    isLaunchBootstrapComplete = true
                }
            }
            LaunchBootstrapPerformanceTracing.mark("launchBootstrap.splashDismissed", appRouter: appRouter)
        } else if isUserLoggedIn {
            LaunchBootstrapPerformanceTracing.mark(
                "launchBootstrap.branch.formalAutoLogin",
                note: "isUserLoggedIn=true networkConnectedAtStart=\(networkConnectedAtStart)",
                appRouter: appRouter
            )
            appRouter.beginHouseholdRoutingResolve()
            defer { appRouter.finishHouseholdRoutingResolveAfterRefresh() }
            let dismissedSplashEarly = dismissLaunchSplashEarlyIfOfflineLoggedIn(
                networkConnectedAtStart: networkConnectedAtStart
            )
            if dismissedSplashEarly == false {
                appRouter.goToOrgRouting()
                LaunchBootstrapPerformanceTracing.mark("launchBootstrap.goToOrgRouting", appRouter: appRouter)
            }
            revealedMainUI = true
            await LaunchBootstrapPerformanceTracing.measure(
                "launchBootstrap.runAuthAndHouseholdBootstrap",
                note: "vipLogTrigger=冷启动 bootstrapTrigger=coldStart",
                appRouter: appRouter
            ) {
                await runAuthAndHouseholdBootstrap(vipLogTrigger: "冷启动", bootstrapTrigger: "coldStart")
            }
            reconcileStaleLoginSession()
            LaunchBootstrapPerformanceTracing.mark("launchBootstrap.reconcileStaleLoginSession.done", appRouter: appRouter)
            if isLaunchBootstrapComplete == false {
                withAnimation(.easeInOut) {
                    isLaunchBootstrapComplete = true
                }
            }
            LaunchBootstrapPerformanceTracing.mark("launchBootstrap.splashDismissed", appRouter: appRouter)
        } else {
            LaunchBootstrapPerformanceTracing.mark(
                "launchBootstrap.branch.loginScreen",
                note: "isUserLoggedIn=false showsGuestLoginEntry=\(AuthSessionHints.showsGuestLoginEntry)",
                appRouter: appRouter
            )
            LaunchBootstrapPerformanceTracing.cancelTrace(reason: "notLoggedIn")
        }

        if revealedMainUI == false {
            withAnimation(.easeInOut) {
                isLaunchBootstrapComplete = true
            }
            LaunchBootstrapPerformanceTracing.mark("launchBootstrap.splashDismissed.loginOrAnonymous", appRouter: appRouter)
        }
        LaunchBootstrapPerformanceTracing.mark("launchBootstrap.end", appRouter: appRouter)
        if revealedMainUI {
            Self.launchBootstrapFinishedAt = CFAbsoluteTimeGetCurrent()
        }
    }

    @MainActor
    private func runAuthAndHouseholdBootstrap(
        vipLogTrigger: String?,
        bootstrapTrigger: String = "foreground"
    ) async {
        LoginFlowPerformanceTracing.mark(
            "authBootstrap.begin",
            note: [vipLogTrigger.map { "trigger=\($0)" }, "bootstrapTrigger=\(bootstrapTrigger)"]
                .compactMap { $0 }
                .joined(separator: " "),
            appRouter: appRouter
        )
        appRouter.syncSessionIdentityFromPersistedSessionIfAvailable()
        LoginFlowPerformanceTracing.mark("authBootstrap.syncSessionIdentity.done", appRouter: appRouter)

        let usedOfflineSnapshotFastPath = appRouter.tryFastEnterFromPersistedHouseholdSnapshot()
        if usedOfflineSnapshotFastPath {
            LoginFlowPerformanceTracing.mark("authBootstrap.offlineSnapshotFastPath", appRouter: appRouter)
        }
        refreshForegroundLocationSchedulerContext()

        let skippedPostOAuthBootstrap = appRouter.consumeSkipNextLoginBootstrapRefresh()
        if skippedPostOAuthBootstrap == false {
            await LoginFlowPerformanceTracing.measure(
                "authBootstrap.authSessionRefresher",
                appRouter: appRouter
            ) {
                await AuthSessionRefresher.refreshOnForegroundIfNeeded()
            }
        } else {
            LoginFlowPerformanceTracing.mark(
                "authBootstrap.authSessionRefresher.skipped",
                note: "postOAuthBootstrap",
                appRouter: appRouter
            )
        }

        if skippedPostOAuthBootstrap == false {
            let skipRefreshForOfflineActiveMember =
                await NetworkMonitor.shared.isConnected == false
                && appRouter.appState == .activeMember
                && appRouter.selectedHouseholdId != nil
            if skipRefreshForOfflineActiveMember {
                LoginFlowPerformanceTracing.mark(
                    "authBootstrap.refreshStateFromBackend.skipped",
                    note: "offlineActiveMember",
                    appRouter: appRouter
                )
            } else {
                await LoginFlowPerformanceTracing.measure(
                    "authBootstrap.refreshStateFromBackend",
                    appRouter: appRouter
                ) {
                    await appRouter.refreshStateFromBackend()
                }
            }
        } else {
            LoginFlowPerformanceTracing.mark(
                "authBootstrap.refreshStateFromBackend.skipped",
                appRouter: appRouter
            )
        }

        if skippedPostOAuthBootstrap == false || appRouter.appState == .orgRouting {
            await LoginFlowPerformanceTracing.measure(
                "authBootstrap.fetchHouseholdsAndCheckCreatorRole",
                appRouter: appRouter
            ) {
                await fetchHouseholdsAndCheckCreatorRole()
            }
        } else {
            LoginFlowPerformanceTracing.mark(
                "authBootstrap.fetchHouseholdsAndCheckCreatorRole.skipped",
                note: "postOAuthActiveMember",
                appRouter: appRouter
            )
        }
        if let vipLogTrigger {
            appRouter.logVIPAccessState(trigger: vipLogTrigger)
            LoginFlowPerformanceTracing.mark(
                "authBootstrap.logVIPAccessState",
                note: "trigger=\(vipLogTrigger)",
                appRouter: appRouter
            )
        }
        reloadTasksIfActiveMember()
        LoginFlowPerformanceTracing.mark("authBootstrap.end", appRouter: appRouter)
    }

    @MainActor
    private func runPostAuthForegroundServices() async {
        refreshForegroundLocationSchedulerContext()
        reloadTasksIfActiveMember()
        guard await NetworkMonitor.shared.isConnected else { return }
        await reportLocationWhenEnteringForeground()
        await syncBackgroundLocationService()
        startForegroundLocationPeriodicRefreshIfNeeded()
    }

    @MainActor
    private func runForegroundLocationBootstrap(vipLogTrigger: String? = nil) async {
        if shouldSkipForegroundBootstrapAfterColdLaunch() {
            LaunchBootstrapPerformanceTracing.mark(
                "authBootstrap.skipped",
                note: "recentColdLaunch bootstrapTrigger=foreground",
                appRouter: appRouter
            )
            await runPostAuthForegroundServices()
            return
        }
        await runAuthAndHouseholdBootstrap(
            vipLogTrigger: vipLogTrigger,
            bootstrapTrigger: "foreground"
        )
        await runPostAuthForegroundServices()
    }

    @MainActor
    private func shouldSkipForegroundBootstrapAfterColdLaunch() -> Bool {
        guard let finishedAt = Self.launchBootstrapFinishedAt else { return false }
        return CFAbsoluteTimeGetCurrent() - finishedAt < 1.0
    }

    @MainActor
    private func reconcileStaleLoginSession() {
        guard isUserLoggedIn,
              appRouter.hasCompletedAuthBootstrap,
              appRouter.appState == .unauthenticated else {
            return
        }

        #if canImport(Supabase)
        if appRouter.hasPersistedSupabaseSession {
            appRouter.goToOrgRouting()
            return
        }
        #endif

        isUserLoggedIn = false
        appRouter.clearOfflineHouseholdSnapshot()
    }

    /// 离线已登录：尽快收起 Splash，后台继续 bootstrap（有快照进主 Tab，否则先进组织路由页）。
    @MainActor
    private func dismissLaunchSplashEarlyIfOfflineLoggedIn(networkConnectedAtStart: Bool) -> Bool {
        guard networkConnectedAtStart == false, appRouter.hasPersistedSupabaseSession else { return false }
        appRouter.syncSessionIdentityFromPersistedSessionIfAvailable()
        let enteredMainTab = appRouter.tryFastEnterFromPersistedHouseholdSnapshot()
        if enteredMainTab == false {
            appRouter.goToOrgRouting()
        }
        withAnimation(.easeInOut) {
            isLaunchBootstrapComplete = true
        }
        LaunchBootstrapPerformanceTracing.mark(
            "launchBootstrap.splashDismissedEarly",
            note: enteredMainTab ? "offlineSnapshotFastPath" : "offlineOrgRouting",
            appRouter: appRouter
        )
        return true
    }

    @MainActor
    private func fetchHouseholdsAndCheckCreatorRole() async {
        guard await NetworkMonitor.shared.isConnected else {
            LoginFlowPerformanceTracing.mark(
                "fetchHouseholds.skipped",
                note: "offline",
                appRouter: appRouter
            )
            return
        }
        guard appRouter.appState != .unauthenticated else {
            LoginFlowPerformanceTracing.mark(
                "fetchHouseholds.skipped",
                note: "unauthenticated",
                appRouter: appRouter
            )
            return
        }
        if appRouter.appState == .orgRouting, appRouter.isResolvingHouseholdRouting {
            LoginFlowPerformanceTracing.mark(
                "fetchHouseholds.skipped",
                note: "orgRoutingAlreadyLoading",
                appRouter: appRouter
            )
            return
        }
        let orgViewModel = AppViewModels.makeOrgRoutingViewModel()
        await orgViewModel.fetchMyHouseholds(appRouter: appRouter)
        LoginFlowPerformanceTracing.mark(
            "fetchHouseholds.done",
            note: "joinedCount=\(orgViewModel.joinedHouseholds.count)",
            appRouter: appRouter
        )
    }

    @MainActor
    private var canPersistForegroundLocation: Bool {
        guard isUserLoggedIn else { return false }
        let unlocked = requireFaceID == false || biometricManager.isUnlocked
        guard unlocked else { return false }
        guard appRouter.appState == .activeMember else { return false }
        return true
    }

    @MainActor
    private func locationPersistContext() -> LocationPersistSession.Context {
        LocationPersistSession.Context(
            isUserLoggedIn: isUserLoggedIn,
            isUnlockedForLocation: requireFaceID == false || biometricManager.isUnlocked,
            appState: appRouter.appState,
            householdId: appRouter.selectedHouseholdId,
            profileId: appRouter.selectedProfileId,
            backgroundLocationEnabled: BackgroundLocationPreferences.isEnabled
        )
    }

    @MainActor
    private func reloadTasksIfActiveMember() {
        guard appRouter.appState == .activeMember,
              appRouter.selectedHouseholdId != nil else {
            return
        }
        #if DEBUG
        print("[ContentView] bootstrap complete → reload tasks household=\(appRouter.selectedHouseholdId?.uuidString ?? "nil")")
        #endif
        LoginFlowPerformanceTracing.mark(
            "authBootstrap.reloadTasksIfActiveMember",
            note: "householdId=\(appRouter.selectedHouseholdId?.uuidString.lowercased() ?? "nil")",
            appRouter: appRouter
        )
        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
    }

    /// 本会话首次进入前台：启动上报；之后回前台仍走 `appEnteredForeground`（后台定位开启时不重复上报）。
    @MainActor
    private func reportLocationWhenEnteringForeground() async {
        if Self.hasReportedLocationOnLaunchThisSession {
            await persistForegroundLocation(trigger: .appEnteredForeground)
        } else {
            await reportLocationOnAppLaunchIfNeeded()
        }
    }

    /// App 启动后首次具备入库上下文时上报一次；不受「后台定位」开关限制。
    @MainActor
    private func reportLocationOnAppLaunchIfNeeded() async {
        guard Self.hasReportedLocationOnLaunchThisSession == false else { return }
        let context = locationPersistContext()
        guard context.isUserLoggedIn,
              context.isUnlockedForLocation,
              context.appState == .activeMember,
              context.householdId != nil,
              context.profileId != nil else {
            return
        }

        Self.hasReportedLocationOnLaunchThisSession = true
        await LocationPersistSession.perform(
            trigger: .appLaunched,
            context: context,
            locationStateService: appBootstrap.services.locationStateService,
            allowWhenBackgroundLocationEnabled: true
        )
    }

    @MainActor
    private func persistForegroundLocation(trigger: LocationPersistTrigger) async {
        await LocationPersistSession.perform(
            trigger: trigger,
            context: locationPersistContext(),
            locationStateService: appBootstrap.services.locationStateService,
            allowWhenBackgroundLocationEnabled: false
        )
    }

    /// 退后台前最后一次入库：不受「后台定位」开关限制（与 BackgroundLocationCoordinator 双轨互补）。
    @MainActor
    private func flushLocationBeforeEnteringBackground() async {
        await LocationPersistSession.perform(
            trigger: .appEnteringBackground,
            context: locationPersistContext(),
            locationStateService: appBootstrap.services.locationStateService,
            allowWhenBackgroundLocationEnabled: true
        )
    }

    @MainActor
    private func refreshForegroundLocationSchedulerContext() {
        ForegroundLocationPersistEligibility.shared.canPersist =
            BackgroundLocationPreferences.isEnabled == false && canPersistForegroundLocation
        ForegroundLocationPersistScheduler.shared.updateContext(
            householdId: appRouter.selectedHouseholdId,
            profileId: appRouter.selectedProfileId,
            locationStateService: appBootstrap.services.locationStateService
        )
    }

    @MainActor
    private func startForegroundLocationPeriodicRefreshIfNeeded() {
        guard BackgroundLocationPreferences.isEnabled == false else {
            ForegroundLocationPersistScheduler.shared.stop(reason: "backgroundLocationEnabled")
            return
        }
        refreshForegroundLocationSchedulerContext()
        ForegroundLocationPersistScheduler.shared.startIfNeeded()
    }

    @MainActor
    private func syncBackgroundLocationService() async {
        guard isUserLoggedIn else {
            BackgroundLocationCoordinator.shared.stop()
            return
        }
        guard appRouter.appState == .activeMember else { return }
        let unlocked = requireFaceID == false || biometricManager.isUnlocked
        guard unlocked else { return }

        BackgroundLocationCoordinator.shared.configure(
            locationStateService: appBootstrap.services.locationStateService
        )
        BackgroundLocationCoordinator.shared.updateContext(
            householdId: appRouter.selectedHouseholdId,
            profileId: appRouter.selectedProfileId
        )
        await BackgroundLocationCoordinator.shared.applyStoredPreference()
    }

    @MainActor
    private func preScheduleLocalNotifications() async {
        guard appRouter.appState == .activeMember else { return }
        guard let householdId = appRouter.selectedHouseholdId else { return }
        do {
            let tasks = try await appBootstrap.services.taskService.fetchTasks(in: householdId)
            #if canImport(Supabase)
            var profiles: [FamilyProfile] = []
            do {
                let roster = try await SupabaseHouseholdRosterLoader.fetch(
                    in: householdId,
                    client: SupabaseManager.shared.client,
                    activeOnly: true
                )
                profiles = FamilyProfile.mergingMembershipRows(
                    roster.profiles,
                    memberships: roster.memberships
                )
            } catch {
                #if DEBUG
                print("[ContentView] preScheduleLocalNotifications roster failed: \(error.localizedDescription)")
                #endif
            }
            #else
            let profiles: [FamilyProfile] = []
            #endif
            let now = Date()
            var upcoming: [TaskAlarmPayload] = []
            var staleTaskIds: [UUID] = []

            for task in tasks {
                let payload = TaskAlarmPayload(
                    schedulingFrom: task,
                    profiles: profiles,
                    locale: appSettings.appLocale
                )
                let isUpcoming: Bool = {
                    guard let due = task.alarmAnchorDate else { return false }
                    guard due > now else { return false }
                    switch task.status {
                    case .completed, .cancelled, .failed, .expired:
                        return false
                    default:
                        return true
                    }
                }()

                if isUpcoming {
                    upcoming.append(payload)
                } else {
                    staleTaskIds.append(task.id)
                }
            }

            upcoming.sort { lhs, rhs in
                (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }

            for payload in upcoming.dropFirst(10) {
                staleTaskIds.append(payload.id)
            }

            await NotificationManager.shared.syncLocalNotifications(
                upcomingTasks: upcoming,
                cancelForTaskIds: staleTaskIds
            )
        } catch {
            #if DEBUG
            print("[ContentView] preScheduleLocalNotifications failed: \(error.localizedDescription)")
            #endif
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environmentObject(AppBootstrap())
}
