# Hintsiders — setup guide

A daily one-word-hint guessing game for friend groups. *You know you know.*

Total deploy time: ~30 minutes if everything goes smoothly.

---

## What you have

```
hintsiders/
├── public/
│   └── index.html              # the entire frontend, single file
├── supabase/
│   └── migrations/
│       └── 001_schema.sql      # database schema
├── netlify.toml                # Netlify config
├── inject-env.js               # build-time env var injection
└── README.md                   # this file
```

No backend code beyond the database schema. No API keys to manage.

---

## Step 1 — Create a Supabase project

1. Go to https://supabase.com and sign up (free tier is fine).
2. Click **New project**. Name it `hintsiders`. Set a strong database password and save it somewhere. Pick the region closest to you.
3. Wait ~2 minutes for the project to provision.

---

## Step 2 — Run the database migration

1. In your Supabase project, go to **Database → Extensions** and enable `pg_cron` (search for it, toggle on).
2. Go to **SQL Editor → New Query**.
3. Open `supabase/migrations/001_schema.sql`, copy the entire contents, paste into the SQL editor.
4. **Before running**, find this line near the bottom:
   ```
   -- select cron.schedule('inside-unlock-hints', '* * * * *', $$select unlock_due_hints()$$);
   ```
   Uncomment it (remove the `--` at the start). The cron name is fine to leave as `inside-unlock-hints` — it's just an identifier.
5. Click **Run**. You should see `Success. No rows returned`.
6. Verify: go to **Database → Tables**. You should see `profiles`, `groups`, `group_members`, `setter_queue`, `rounds`, `hints`, `guesses`.

---

## Step 3 — Get your Supabase keys

1. In your Supabase project, go to **Settings → API**.
2. Copy the **Project URL** (looks like `https://abcdefgh.supabase.co`).
3. Copy the **anon public** key (a long string starting with `eyJ...`).
4. Save these for the next step.

---

## Step 4 — Push the code to GitHub

1. Create a new repo on github.com called `hintsiders`.
2. From the project directory:
   ```bash
   git init
   git add .
   git commit -m "initial hintsiders"
   git remote add origin git@github.com:YOUR_USERNAME/hintsiders.git
   git push -u origin main
   ```

---

## Step 5 — Deploy to Netlify

1. Go to https://app.netlify.com.
2. Click **Add new site → Import an existing project → GitHub**. Authorize and pick your `hintsiders` repo.
3. Build settings:
   - **Build command:** `node inject-env.js`
   - **Publish directory:** `public`
4. Before clicking Deploy, click **Add environment variables** and add:
   - `SUPABASE_URL` = (your Project URL from Step 3)
   - `SUPABASE_ANON_KEY` = (your anon public key from Step 3)
5. Click **Deploy site**.
6. Once deployed, Netlify will give you a URL. Click **Domain settings** to rename it to something memorable, like `hintsiders.netlify.app` if it's available.

---

## Step 6 — Configure Supabase auth

1. In Supabase, go to **Authentication → URL Configuration**.
2. Set **Site URL** to your Netlify URL (e.g., `https://hintsiders.netlify.app`).
3. Add the same URL to **Redirect URLs**.
4. Save.

---

## Step 7 — Test it

1. Open your Netlify URL in a browser.
2. Enter your email. Check inbox for the magic link. Click it — it should redirect you back to the app.
3. Set your display name.
4. Create a group. Pick a hint drop time (e.g., 9 for 9am).
5. From the menu (⋯), copy the invite code. Send it to a friend.
6. Friend opens the URL, signs in with their email, joins via "join with code", and they're in.
7. Whoever wants to set first hits "start next round", picks a category, types the answer, writes the five hints, and submits.
8. Hint 1 drops immediately. Hint 2 drops at the configured hour tomorrow.

---

## How the game works once live

- Five rounds, five hints, one guess per day per player
- Setter sees all 5 hints from the start; everyone else sees only what's been unlocked
- Setter override: if a friend guesses a nickname or typo, setter taps "count it" to mark correct
- Whoever solves first sets the next round
- After reveal, the setter can tap any hint to add an annotation that lives in the archive forever
- Group invite codes never expire

---

## Troubleshooting

**Magic link doesn't work / wrong redirect** — Check Step 6. The Site URL and Redirect URLs in Supabase auth must match your Netlify URL exactly.

**Hints aren't unlocking on schedule** — Verify the `cron.schedule` line in Step 2 was uncommented. Check by running `select * from cron.job;` in the SQL editor.

**Realtime guesses not appearing for other players** — The migration includes `alter publication supabase_realtime add table guesses`. If it didn't run, re-run the last few lines of the schema.

**Build fails on Netlify** — Check that the env vars in Step 5 are set on the right scope (production, not just preview).

**Burgundy i-tittle is in the wrong place** — The dot is positioned at runtime by JavaScript and tuned for Caveat at the current font sizes. If you change the wordmark size or font, the offsets in the `placeBurgundyDot` function may need adjustment. The current values (`fontSize * 0.12` right shift, `fontSize * 0.30` down shift) are calibrated for Caveat at sizes between 22–88px.

---

## Not in v1

- Push notifications (just check the app, or message the group when hints drop)
- Scoring / leaderboards
- Hint editing after submission
- Image hints
- Member removal / group admin tools
- Mobile native app

These are v2 territory. Play a few rounds first.
