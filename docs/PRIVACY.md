# HarvestInn Privacy Policy (draft)

*Last updated: 6 November 2026. This is a draft for the App Store and Google
Play listings. Have it reviewed before publishing, and replace `[CONTACT EMAIL]`
and `[DEVELOPER NAME]`.*

HarvestInn ("the game") is made by [DEVELOPER NAME]. This policy explains what
data the game collects, why, and the choices you have.

## The short version
- You can play the whole farm **offline without an account**.
- If you go online, we create an anonymous **guest account** so your farm can be saved to the cloud and you can trade.
- We store your **game progress, your chosen farmer name, your friend code, and your trades**.
- We do **not** collect your real name, contacts, photos, precise location or advertising ID.
  Ads and purchases are switched off in this version.
- You can ask us to delete your account and data at any time.

## What we collect and why
| Data | When | Why | Where |
|---|---|---|---|
| Guest account ID (random) | When you first go online | Identify your save and trades | Supabase (our backend host) |
| Sign in with Apple / Google identifier and email (if you choose to link) | Only if you link an account | Restore your farm on a new device | Supabase Auth |
| Game save (farm, inventory, coins, level, settings) | Periodically while online | Cloud backup and sync between devices | Supabase database |
| Farmer name, level, friend code, a farm snapshot (plots, buildings, decorations, avatar) | While online | Shown to other players in the market, friends list and farm visits | Supabase database |
| Trades: listings, purchases, offers, deposits and collections, with time stamps | When you trade | Run the marketplace, prevent cheating and fraud, resolve disputes | Supabase database (trade log) |
| Reports you send about other players | When you report | Moderation | Supabase database |
| Technical data (IP address, request time), kept briefly in server logs | While online | Security and rate limiting | Supabase infrastructure |

The game itself keeps your farm and settings on your device
(`user://save.json` and `user://settings.cfg`).

## What other players can see
Your **farmer name, level, friend code, marketplace listings** and a
**read-only snapshot of your farm** (for friends who visit). They cannot see
your inventory, coins, account e-mail or sign-in method.

## Children
HarvestInn is a family-friendly game, but it is not directed at children under 13
(under 16 in the EEA). We don't knowingly collect personal data from children. Player
names are filtered for offensive words, and other players can be reported. If you
believe a child has given us personal data, contact us and we will delete it.

## Advertising and purchases
This version shows **no ads** and has **no purchases**. If they are added later, this
policy will be updated **before** that release to describe the ad networks
(e.g. Google AdMob) and the app stores' billing, together with any consent prompts
(App Tracking Transparency on iOS, consent forms in the EEA/UK).

## Legal bases (EEA/UK)
We process data to **provide the service you asked for** (cloud saves, trading,
friends) and for our **legitimate interest** in keeping the marketplace fair and
secure (trade logs, rate limits, moderation).

## Retention
- Account and game data: kept while your account exists.
- Trade logs: kept for up to 2 years for fraud prevention, then deleted or anonymised.
- Inactive guest accounts: deleted after 24 months without a sign-in.
- After a deletion request: removed within 30 days (backups roll off within a further 30 days).

## Your rights and choices
You can access, correct, export or delete your data, or object to its processing.
In-game you can play offline and change your name; for deletion or export, e-mail
[CONTACT EMAIL] with your friend code (Friends screen). Deleting your account
removes your profile, cloud save, listings, offers and friendships. Completed
trades stay in the other player's history without your name.

## Security
Data is sent over HTTPS. Access is restricted per player by database Row Level
Security. All trades are validated on the server, and service keys are never
shipped in the app.

## Where data is stored
Supabase stores data in the region chosen for the project. If that is outside your
country, standard contractual clauses or equivalent safeguards apply.

## Changes
We will update this page and change the date above, and show an in-game notice for
significant changes.

## Contact
[DEVELOPER NAME] · [CONTACT EMAIL]

---
### Store questionnaire hints
- **Google Play Data safety:** collects *User IDs* and *App activity: in-app actions (trades)*,
  plus *Email* only if Google/Apple linking is used. Purpose: App functionality, Fraud prevention.
  Not shared with third parties. Data is encrypted in transit, and deletion can be requested.
- **Apple App Privacy:** *Identifiers: User ID*, *Usage Data: Product Interaction (trades)*,
  *Contact Info: Email* (only with Sign in with Apple/Google). All linked to the user, none used for tracking.
