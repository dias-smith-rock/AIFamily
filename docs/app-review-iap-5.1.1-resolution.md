# App Review Resolution — Guideline 5.1.1(v)

Use the text below in App Store Connect **Resolution Center** when resubmitting after the IAP compliance update.

## Resolution Center message (English)

We revised the subscription flow per Guideline 5.1.1(v). Users can complete In-App Purchase and Restore Purchases **without registering** for an app account. Pro features unlock immediately on device via StoreKit. **Sign-in is optional** and only needed to sync Pro to our cloud account and use multi-device group features. Account registration is not required to purchase or restore the non-account-based Pro subscription.

## Sandbox test steps (for App Review)

1. Sign in with a Sandbox Apple ID (or use an existing test account in the app).
2. Open **Me → Upgrade to Pro**, or trigger **Upgrade** from a free-tier limit (e.g. extra task attachment).
3. Complete the subscription purchase. The app must **not** show “Please sign in before subscribing.”
4. Confirm Pro features unlock immediately (e.g. more attachments, location ghost mode options).
5. Optional: sign out of the **app account** (not the device Apple ID) → tap **Restore Purchases** on the Pro screen → subscription remains active on device.

## Notes for reviewers

- The VIP subscription screen includes footnote copy: *Sign in is optional. Subscribe without an account; sign in later to sync Pro across devices.*
- Cloud group sync and multi-household features still require an app account; that is separate from purchasing Pro.
- **Restore Purchases** works without an app account; entitlement is validated through StoreKit on the device Apple ID.
