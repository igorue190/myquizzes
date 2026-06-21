# Markwise Tutorial — Your First Quiz

A friendly, 5-minute walkthrough. By the end you'll have written a quiz in plain
Markdown, run it, and know where the extra features live. For the big picture,
see the [Overview](Overview.md).

---

## 1. The idea in one sentence

A Markwise quiz is just a **Markdown text file** (`.md`): each **question is a
heading**, each **answer is a checkbox**, and `- [x]` marks the correct one.

That's it. No special editor — any text app works.

---

## 2. Write a question

Copy this into a new file called `my-first-quiz.md`:

```markdown
## Which cloud service model gives the most control over the OS?

- [ ] SaaS
- [ ] PaaS
- [x] IaaS

> **Explanation:** IaaS exposes the virtual machine and OS to the customer,
> so you control the operating system.
```

What each part does:

| Markdown | Meaning |
|---|---|
| `## …` (a heading) | The **question prompt** |
| `- [ ] SaaS` | A **wrong** answer (empty box) |
| `- [x] IaaS` | The **correct** answer (checked box) |
| `> **Explanation:** …` | An optional note shown after you answer |

---

## 3. Add more question types

Markwise figures out the type automatically, but you can be explicit with a
comment **on its own line, right under the heading**.

**Multiple correct answers** (you must pick *all* of them):

```markdown
## Which of these are Azure compute services?
<!-- type: multiple -->

- [x] Virtual Machines
- [x] App Service
- [ ] Blob Storage
- [x] Functions
```

**True / False:**

```markdown
## Azure Functions is a serverless compute service.
<!-- type: truefalse -->

- [x] True
- [ ] False
```

**Tag a question** so you can filter/organize later:

```markdown
## What does SLA stand for?
<!-- tags: fundamentals, pricing -->

- [x] Service Level Agreement
- [ ] Software License Application
```

> 💡 Scoring is **all-or-nothing**: for a multiple-answer question you only get
> the point if you select exactly the right set.

---

## 4. (Optional) Add file-level info

At the very top of the file you can add a small **front matter** block between
`---` lines to title the whole quiz:

```markdown
---
title: AZ-900 Fundamentals
---

## First question goes here…
```

Want a full, real example? Open [../Samples/AZ-900.md](../Samples/AZ-900.md).

---

## 5. Run it

1. Open Markwise and go to the **Library** tab.
2. **Import** your `.md` file (or pick one already there).
3. Go to **Practice** and choose a mode:
   - **Training** — get feedback after every question while you learn.
   - **Exam** — a timed run; see your score at the end.
4. Finish, then check the **Stats** tab to see your result and what's **due for
   review** next.

---

## 6. Learn vocabulary with flashcards

Vocabulary works the same Markdown-first way, but for **bilingual word pairs**.
A vocabulary set becomes:

- a **swipeable flashcard deck** with **spaced repetition** — tap **Known** to
  see a card less often, **Again** to see it sooner, and
- **translation quizzes** generated automatically from the same set.

You manage vocabulary sets from the **Library**, right alongside your quizzes.

---

## 7. (Optional) Turn on the AI helpers

Markwise is **100% usable offline** — this step is entirely optional.

If you'd like a few smart extras, go to **Profile**, enable **AI features**, and
paste your own **Claude API key** (it's stored securely in your device's
Keychain). Then you can:

- 💡 Tap **Explain** on a question you missed for a plain-language explanation.
- ✨ **Generate a quiz** from notes you paste in.
- 🗂️ **Structure** a messy bilingual list into a clean vocabulary set.

Everything the AI produces is shown to you in a **review screen** before it's
saved — you're always in control, and nothing is sent anywhere unless you turn
this on and trigger it.

---

## Cheat sheet

```markdown
---
title: Optional quiz title
---

## Question prompt?
<!-- type: single|multiple|truefalse -->
<!-- tags: a, b -->

- [x] correct answer
- [ ] wrong answer

> **Explanation:** optional, shown after answering.
> **Reference:** https://optional-link
```

| I want to… | Where |
|---|---|
| Add / organize files | **Library** tab |
| Take a quiz | **Practice** tab |
| See progress & reviews | **Stats** tab |
| Set my name / backup / AI key | **Profile** tab |

Happy studying! For how it all fits together (and how it's built), read the
[Overview](Overview.md).
