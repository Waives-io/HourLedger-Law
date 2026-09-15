---
name: hourledger-new-office
description: פתיחת משרד עו"ד חדש ב-HourLedger-Law — הקמת תרחיש Make משלו, גיליון Google Sheets, חשבון באפליקציה וחיבור ה-webhook. להפעיל כשגלי אומרת "משרד חדש", "לקוח חדש ל-HourLedger", "לפתוח משרד", "onboarding למשרד", או שואלת איך מחברים משרד לגיליון.
---

# פתיחת משרד חדש ב-HourLedger-Law

מדריך צעד-אחר-צעד. Claude מלווה את גלי בסדר הזה, שלב אחרי שלב, ומחכה לאישור בין שלבים.
כללי שפה: ההסבר בעברית; כשמנחים בתוך מסך שהממשק שלו באנגלית (Make, Google, Supabase) — ההוראה עצמה באנגלית, עם שמות הכפתורים המדויקים.

## עקרון

**אתר אחד = משרד אחד.** כל משרד מקבל פריסה משלו של האפליקציה (ריפו + GitHub Pages משלו), עם שם המשרד וה-webhook צרובים בקובץ `index.html` (הקבוע `FIRM` בראש הסקריפט). ההרשמה באתר של משרד לא שואלת שם משרד — כל מי שנרשם שם שייך למשרד הזה. Supabase נשאר **פרויקט אחד משותף** לכל המשרדים (ההפרדה היא לפי `org`).

| רכיב | של מי | איפה |
|---|---|---|
| ריפו + אתר (GitHub Pages) | של WAIVES, אחד למשרד | `Waives-io/HourLedger-<משרד>` |
| חשבון Make + תרחיש | של המשרד (חשבון Make משלו, Free מספיק למשרד אחד) | make.com |
| גיליון Google Sheets | של המשרד | Google Drive של המשרד |
| Webhook | נוצר אוטומטית בתרחיש | מודול ה-Webhook |
| חשבון באפליקציה | של המשרד | האתר של המשרד |

לפני שמתחילים, לאסוף: שם המשרד (בכתיב שיופיע בכל מקום), אימייל של המשרד, מי במשרד ידווח שעות.

---

## שלב 0 — ריפו ואתר למשרד

1. In GitHub, open `Waives-io/HourLedger-Law` → **Use this template** → **Create a new repository** (if the button is missing: repo **Settings → General → tick "Template repository"** first).
   - Owner: **Waives-io** · Name: `HourLedger-<office>` (e.g. `HourLedger-Cohen`) · **Public** (required for free Pages) → **Create repository**.
2. Clone it locally, open `index.html`, and edit the `FIRM` block near the top of the script:
   ```js
   const FIRM = {
     name: '<שם המשרד המדויק>',
     webhook: ""            // filled in step 2 below, after Make gives the URL
   };
   ```
   Commit + push (Hebrew message). Claude does this part when asked.
3. Repo **Settings → Pages → Source: Deploy from a branch → main / (root) → Save**. After a minute the site is live at `https://waives-io.github.io/HourLedger-<office>/`.
4. Supabase (project `HourLedger-Law`) → **Authentication → URL Configuration → Redirect URLs → Add URL** → the new site address → Save. Without this, confirmation and reset emails won't open the new site.

---

## שלב 1 — הגיליון של המשרד (Google Sheets)

1. Create a new Google Sheet in the office's Google account. Name it e.g. `שעות לחיוב — <שם המשרד>`.
2. Rename the first tab to exactly: `DB of Hours Reported`
3. In row 1 type these headers, in this exact order (A → O):

```
A תאריך לחיוב
B שם לקוח
C תעריף לשעה (לא כולל מע"מ)
D על מה לחייב
E הערות
F שעות לדיווח
G Submission ID
H סה"כ לחיוב (לא כולל מעמ)
I מטבע
J סה"כ לחיוב (כולל מעמ)
K חודש חיוב
L groupId
M משתמש
N סטטוס
O עדכון אחרון
```

הסדר קריטי: ה-blueprint כותב לפי מיקום עמודה. C, H, I, J, K נשארים לנוסחאות/מילוי ידני של המשרד — האפליקציה לא כותבת אליהם.

## שלב 2 — תרחיש Make למשרד

1. Sign in to make.com with the **office's** Make account (create one if needed — Free plan is enough for one office: 2 scenarios, 1,000 operations/month).
2. **Scenarios → Create a new scenario**.
3. Top-right **⋮** (next to Help) → **Import Blueprint** → choose `make/HourLedger-Sheets.blueprint.json` from the repo.
4. You should see 9 modules (Webhook → Router with 3 branches). If you see only 2 modules, the wrong file was picked — reload and import again.
5. Click the **Webhook** module → **Add** → name it `HourLedger <שם המשרד>` → Save. This creates a new webhook URL for the office. **Copy the URL** (`https://hook.eu1.make.com/…`) and paste it into `FIRM.webhook` in the office's `index.html` (commit + push). It can also be changed later from the app's Settings.
6. Open **each** Google Sheets module (there are 6: 2× Add a Row, 2× Search Rows, 2× Update a Row):
   - **Connection**: Add → sign in with the office's Google account.
   - **Spreadsheet**: pick the sheet from step 1. **Sheet Name**: `DB of Hours Reported`.
   - Leave the column mapping as is.
7. Bottom toolbar: if the schedule shows **Every 15 minutes**, click it and choose **Immediately as data arrives**.
8. **Save** (disk icon) → switch the toggle to **ON**.

## שלב 3 — חשבון באפליקציה

עדיף שגלי תפתח את החשבון מהמחשב שלה ותשלח למשרד מייל + סיסמה זמנית; המשרד רק נכנס.

1. Open the office's site (from step 0) → **פתיחת חשבון**: email, password (6+ chars), quick access code (4 digits). The office name is already fixed — no field for it.
2. A confirmation email arrives — click the link, then sign in. (Supabase's built-in mailer allows ~2 emails/hour; if it fails, wait an hour or connect custom SMTP.)
3. On the office's phone open the site → **Share → Add to Home Screen** (iPhone) or **⋮ → Add to Home screen** (Android) → sign in with email + password → set a 4-digit code for that phone.
4. **הגדרות → רשימת לקוחות**: paste the office's client list (one per line or comma-separated).

## שלב 4 — לוודא את ה-webhook

1. In the app: **הגדרות → חשבון וסנכרון** — "סנכרון לגוגל שיטס" should read **פעיל** and the webhook field should show the office's URL (it was set from `FIRM.webhook` at signup).
2. If it's empty (account created before the webhook existed): paste the URL → **שמירה**. The address is saved on the office record in Supabase, so every device picks it up.

## שלב 5 — בדיקה (חובה)

From the app, in this order, and check the sheet after each step:

1. **דיווח** with two categories → 2 new rows, each with its own `Submission ID` (G) and the same `groupId` (L).
2. **עריכה** of one row (change hours) → the same row updates in place, `סטטוס` (N) = `עודכן`.
3. **מחיקה** of one row → the row stays, `שעות` (F) = 0, `סטטוס` (N) = `בוטל`, original hours appear in `הערות` (E).

If nothing arrives: Make → the scenario → **History** shows whether the webhook was hit and which module failed. Most common causes: toggle OFF, wrong sheet/tab name, Google connection not selected on one of the 6 modules.

## שלב 6 — תיעוד

Add the office to the table in `HANDOFF.md` (section "משרדים פעילים", create it if missing): office name, Make account email, sheet link, date connected. Commit with a short Hebrew message and push.

---

## תקלות נפוצות

- **"Every 15 minutes" after import** — Make resets the schedule on import. Set back to *Immediately as data arrives*.
- **Rows land in the wrong office's sheet** — the webhook URL in the app points at another office's scenario. Fix in הגדרות.
- **Search Rows finds nothing on update/delete** — column G header must be exactly `Submission ID`, and the row must have been created by the app (old form rows have no id). The update branch falls back to adding a new row.
- **Make "operations limit reached"** — Free plan cap (1,000/month). Each entry costs 2–4 operations. Upgrade that office's Make to Core, or wait for the monthly reset.
