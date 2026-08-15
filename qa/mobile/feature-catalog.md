# Mobile QA coverage catalog

This is the contract between product review and automated mobile QA. “Covered”
means a real APK is driven on an Android emulator and the outcome is asserted;
it does not mean the feature has only been opened.

| Journey | Current coverage | Next requirement |
| --- | --- | --- |
| First launch and onboarding | Covered (smoke) | Add copy and video-playback assertions |
| Yug, Vayu, Upload, Subs, Account navigation | Covered (smoke) | Add loading/error-state assertions |
| Feed playback, swipe, pause and resume | Backlog | Seed stable public QA videos |
| Search and creator profile navigation | Backlog | Add a stable QA creator fixture |
| Sign-in and account switching | Backlog | Dedicated Google test account/credential strategy |
| Video upload and processing | Backlog | Staging bucket plus disposable media fixture |
| Series upload | Backlog | Staging series fixture and cleanup API |
| Delete own video | Backlog | Disposable QA-owned video fixture |
| Like, follow, save and share | Backlog | Authenticated QA account and reset endpoint |
| Subscriptions and encrypted playback | Backlog | QA subscriber/creator pair and E2EE fixture |
| Dubbing | Backlog | Stable source video and quota-safe QA endpoint |
| Ad creation and wallet | Backlog | Staging credits; never run against real money |
| Creator payout/billing setup | Backlog | Sandbox payout provider and synthetic UPI data |
| Notifications and deep links | Backlog | FCM test sender and deterministic deep-link fixture |
| Reporting and feedback | Backlog | Staging data cleanup and rate-limit allowance |
| Picture-in-picture and app lifecycle | Backlog | Physical/device matrix; emulator smoke is insufficient |

When a backlog row becomes runnable, add a tagged flow under
`.maestro/flows/` and change its status here in the same pull request.

