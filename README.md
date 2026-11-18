# LanguageLearner3000

An iPhone/iPad app for learning **Russian** and **Ukrainian**, levels **A1 → C2**.
Built with SwiftUI. It needs iOS 17 or later.

---

## Step-by-step: run it on your Mac (Simulator)

1. **Open the project.** In Finder, go to `Documents › RU/UKR ios app › LanguageLearner3000` and double-click
   **`LanguageLearner3000.xcodeproj`**. Xcode opens.
2. **Pick a device.** At the top of the Xcode window, click the device menu next to "LanguageLearner3000"
   and choose an iPhone simulator, such as **iPhone 17**.
3. **Run.** Press **⌘R** (or the ▶︎ Play button). The Simulator starts and the app opens.
   The first build takes about a minute.

> In the Simulator, the very first word you tap can take a few seconds to play while the
> audio system starts up. After that it plays straight away, and on a real iPhone it's fast.

## Step-by-step: install it on your own iPhone (free)

1. Plug your iPhone into the Mac with a cable and tap **Trust** on the phone.
2. In Xcode, click the blue **LanguageLearner3000** project icon at the top of the left sidebar,
   then select the **LanguageLearner3000** target and open the **Signing & Capabilities** tab.
3. Under **Team**, choose **Add an Account…**, sign in with your Apple ID, and select your
   *(Personal Team)*.
4. Change **Bundle Identifier** to something unique, e.g. `com.yourname.LanguageLearner3000`.
5. In the device menu at the top, pick **your iPhone**, then press **⌘R**.
6. The first time only:
   - On the iPhone, open **Settings › Privacy & Security › Developer Mode**, turn it on, and restart.
   - Open **Settings › General › VPN & Device Management**, tap your Apple ID, and tap **Trust**.
7. Press **⌘R** again. The app installs and opens.

> With a free Apple ID the app stops opening after **7 days**. Plug the phone in and press ⌘R again to renew it.
> A paid Apple Developer account ($99/yr) extends this to a year.

### Get better (or any) Ukrainian/Russian voices
Pronunciation uses Apple's built-in voices. For the most natural sound, on the iPhone go to
**Settings › Accessibility › Read & Speak (Spoken Content) › Voices**, then download an **Enhanced** or
**Premium** voice for **Russian** and **Ukrainian**. **Settings** in the app shows whether each voice is installed.

---

## What's in the app

| Feature | Details |
|---|---|
| **Two language tabs** | 🇷🇺 Russian and 🇺🇦 Ukrainian, each with its own level and progress |
| **Levels A1–C2** | Tap a level chip at the top of each tab |
| **8 lessons per month** | Vocabulary, Listening, Reading, Grammar in context, Sentence building, and a Monthly challenge |
| **Exercise types** | Multiple choice, reverse translation, listening (audio only), reading comprehension, matching pairs, true/false, fill-the-gap (pick a word), sentence builder (tap word tiles) |
| **No Cyrillic typing** | You answer every exercise by tapping |
| **Tap any word** | Plays the pronunciation and shows its definition, the Latin spelling, an example, and a Wiktionary link |
| **Audio** | Normal 🔊 and slow 🐢 playback, with adjustable speed in Settings |
| **Transliteration** | Latin spelling under Cyrillic words (you can turn it off in Settings) |
| **Reading room / Word bank** | Every story and word for your level, with audio |
| **Quick practice** | A new random mix every time |
| **Progress** | XP, a daily streak, and your best score for each lesson |

## How the exercises stay fresh

1. **Automatic monthly rotation (always on, offline).** On the 1st of every month the lessons are
   reshuffled from everything the app knows: a new mix of lesson types, words, wrong answers and stories.
2. **Brand-new material written every month (automatic, once set up).**
   - On the **25th of each month** a GitHub Action (`.github/workflows/monthly-content.yml`) runs
     `content-pipeline/generate_pack.py`. It runs again on the **1st** to finish anything the spending cap
     cut short. It asks Claude to write a new set for **every language and level**:
     25 words, 10 sentences, 10 grammar gap-fills and 2 stories with questions. Each month has its own
     theme (food, travel, history…), and the pack never repeats words or stories from earlier months.
   - A second Claude pass proofreads the material as a native-speaker teacher, as far as the budget allows.
   - **Spending is capped at $5 per calendar month** for both languages together (`content-pipeline/budget.py`).
     Each call is priced from the usage the API reports, and the running total is kept in `packs/spend.json`.
     A call only starts if its *worst-case* cost still fits, so the month can't go over $5. All levels are
     written first, and proofreading uses what's left. To change the cap, edit `MONTHLY_BUDGET_USD` in the
     workflow file.
   - `validate_pack.py` checks every item automatically and drops anything broken. It catches wrong
     alphabets (e.g. Russian letters in Ukrainian), gaps with more than one right answer among the options,
     bad answer numbers and repeats.
   - The pack is saved to `packs/ru/YYYY-MM.json` and `packs/uk/YYYY-MM.json` on GitHub.
   - **The app downloads it by itself** whenever you open it with internet: next month's pack early, and any
     month you missed. A banner says *"New lessons for … are ready!"* That month's lessons are then
     built mostly from the new words and stories, and new stories are marked **NEW** in the Reading room.
     Everything keeps working offline.

### One-time setup for the monthly material (about 15 minutes)

You need a free **GitHub** account and an **Anthropic API key** (console.anthropic.com, pay-as-you-go).
Cost: **at most $5 per month** (enforced by the generator). As a second safety net, also set a monthly
spend limit in the Anthropic Console (**Settings › Limits**).

1. **Create the repository.** On github.com, click **New repository**, name it `LanguageLearner3000`, and
   choose **Public**. The app reads the packs without a password, so the repository must be public. Don't add a
   README. Click **Create repository**.
2. **Keep your email private.** On GitHub, open **Settings › Emails** and tick **Keep my email addresses private**.
   This project's commits already use `OmegaCluster556@users.noreply.github.com`.
3. **Upload this project.** In Terminal:
   ```bash
   cd ~/Documents/"RU:UKR ios app"/LanguageLearner3000
   git remote add origin https://github.com/OmegaCluster556/LanguageLearner3000.git
   git push -u origin main
   ```
   When it asks for a password, paste a GitHub *personal access token*, not your account password
   (GitHub › Settings › Developer settings › Personal access tokens › Fine-grained, with access to this
   repository and **Contents: Read and write**). You can also use the GitHub Desktop app instead.
4. **Add your API key.** On GitHub, open the repo, then **Settings › Secrets and variables › Actions ›
   New repository secret**. Name it `ANTHROPIC_API_KEY` and paste your key. Never put the key in any file.
5. **Let it publish.** In the repo, open **Settings › Actions › General › Workflow permissions**, choose
   **Read and write permissions**, and save.
6. **Create the first pack now** (instead of waiting for the 25th): go to **Actions › Monthly content ›
   Run workflow**, type the current month (e.g. `2026-11`), and run it. It takes about 30–60 minutes.
   This month's $5 budget is shared with the run on the 25th, so December's pack may be finished
   by the run on December 1st.
7. **Reinstall the app** (⌘R in Xcode). It's already set to download from
   `github.com/OmegaCluster556/LanguageLearner3000`.

From then on it's fully automatic: GitHub writes a new pack every month, and the app fetches it.

### Running the generator on your Mac (optional)
```bash
cd content-pipeline
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
export ANTHROPIC_API_KEY=...            # your key
.venv/bin/python generate_pack.py --month 2026-12 --languages ru --levels A1   # small, cheap test
.venv/bin/python validate_pack.py ../packs/ru/2026-12.json
```

### Content format (`Resources/russian.json`, `Resources/ukrainian.json`, and packs)

```json
{
  "version": "2026-12",
  "levels": {
    "A1": {
      "vocab":     [{"w": "кошка", "m": "cat", "f": ["кошку", "кошки"], "e": "У меня есть кошка.", "et": "I have a cat."}],
      "sentences": [{"s": "Я живу в Москве.", "t": "I live in Moscow."}],
      "gaps":      [{"s": "Я ___ в Москве.", "a": "живу", "o": ["живёт", "живут"], "t": "I live in Moscow."}],
      "readings":  [{"id": "ru-a1-99", "title": "…", "text": "…", "translation": "…",
                     "glossary": {"word-form": "meaning"},
                     "questions": [{"q": "…?", "o": ["A", "B", "C"], "a": 1}]}]
    }
  }
}
```
`w` word · `m` meaning · `f` other forms (so tapped inflected words are recognised) · `e`/`et` example + translation ·
`a` correct answer · `o` wrong options · in questions, `a` is the index of the correct option (starting at 0).
Every section and field is optional, so a pack can add a single story to a single level.

## Project layout

```
LanguageLearner3000/
├─ App/LanguageLearner3000App.swift      app entry + tab bar
├─ Models/                               Language, Level, content + exercise types
├─ Services/
│  ├─ ContentStore.swift                 loads/merges course + packs, word lookup
│  ├─ ExerciseGenerator.swift            builds the monthly lessons
│  ├─ SpeechService.swift                text-to-speech (ru-RU / uk-UA)
│  ├─ ProgressStore.swift                XP, streak, scores
│  └─ Transliterator.swift               Cyrillic → Latin
├─ Views/                                home, lesson player, exercises, library, settings
└─ Resources/russian.json, ukrainian.json  the course content
content-pipeline/
├─ generate_pack.py                      writes a new monthly pack with Claude
├─ validate_pack.py                      checks and cleans packs
└─ requirements.txt
packs/ru, packs/uk                       published monthly packs (the app downloads these)
.github/workflows/monthly-content.yml    runs the generator on the 25th of each month
```
