# Android setup (Family Link monorepo)

## Requirements

- JDK 17+
- Android SDK (API 35+), Build-Tools 35/36
- Android Studio Ladybug+ recommended
- Network for first Gradle sync

## Bootstrap

```bash
cd android
cp local.properties.example local.properties
# Edit sdk.dir and Supabase keys
./gradlew :app:assembleDebug
```

`local.properties` is **gitignored**. Never commit signing keys or service-role secrets.

## Supabase

Use the same project as iOS. Inject via `local.properties`:

```
SUPABASE_URL=https://….supabase.co
SUPABASE_ANON_KEY=sb_publishable_…
```

Keys are exposed to the app as `BuildConfig.SUPABASE_URL` / `SUPABASE_ANON_KEY` (anon/publishable only).

## Firebase / FCM

1. Add an Android app in the existing Firebase project (`applicationId` `com.aifamilygroup.reminder`).
2. Download `google-services.json` → `android/app/google-services.json`.
3. Uncomment `id("com.google.gms.google-services")` in `android/app/build.gradle.kts`.

Until then, `PushRegistrar` no-ops safely if Firebase is unavailable.

## Play Billing

- Product id placeholder: `family_link_pro_monthly` (`BillingRepository.PRO_MONTHLY_PRODUCT_ID`).
- Create the subscription in Play Console, then sync entitlements to Supabase (mirror iOS RevenueCat → `user_entitlements` flow documented in `docs/subscription-iap-deployment.md`).

## Localization

```bash
python3 scripts/export_android_strings.py
```

Reads `localization/keys.json` + `reminder/Localization/{Table}.xcstrings` and writes `android/app/src/main/res/values*/strings.xml`.

## Architecture pointers

- Contracts: `shared/architecture.md`
- Schema skill: `.cursor/skills/supabase-schema/SKILL.md`
- Package: `com.aifamilygroup.reminder`
