---
name: launch-docs
description: Build this repo's first docs site in docs/site from its code, with visual-first pages and plain writing. Use when asked to launch, create, bootstrap or set up a docs site for a repo. If docs/site already exists, use write-docs instead.
---

# Launch docs

Build a static docs site from the code. A reader should get each idea from a picture, understand it from a few short lines, and open details only if they want them. Paths are from the repo root. `SKILL_DIR` means `.agents/skills/launch-docs`.

Stop and report if `docs/site/` already exists. Change only `docs/`, the root `AGENTS.md`, and one link in the README. Don't change code, and don't move or delete existing docs.

## 1. Read the rules

Read these in full before anything else:

- `SKILL_DIR/assets/site/AGENTS.md`, the page rules
- `.agents/skills/plain-writing/SKILL.md`, the sentence rules
- `SKILL_DIR/references/patterns.html`, every component with its markup and how to choose one

The app in `patterns.html` is made up. Copy its markup and none of its names or content.

## 2. Read the repo

Facts come from the code on this branch. Older docs tell you where to look and what people intended, and the code decides what's true. Notes or memory from other sessions aren't sources.

- Read the README, any `AGENTS.md` or `CLAUDE.md`, the manifests and the file tree, then the entry points, and follow the main path through the code by hand.
- Read the existing docs and the last 30 commit subjects. Note where they disagree with the code.
- Tests show intended behavior. Don't document test files.
- Don't open `.env` or credential files, and don't run anything that deploys, costs money or moves hardware.
- Keep a list of the files behind each fact, for the Sources sections.

## 3. Plan the site

Write these down before any page:

| Decide | How |
| --- | --- |
| **Parts** | The 3 to 8 running pieces of the system, in the code's own names. Pick colors `c1`, `c2`, `c3` for the three a reader must tell apart. Storage and infrastructure stay gray. |
| **Default example** | One concrete input to follow on every page, such as one specific request, command or file. Invent the values and keep the path true to the code. |
| **Glossary** | The project's own nouns with one meaning each. Use them on every page and add no synonyms. |
| **Pages** | One topic each, from the table below. Each has a question it answers and a visual that answers it. Drop any page that has no visual and no reader. |

Size the site to the repo, and stop at the size below. A small site with every claim checked is the goal.

| Tracked source files | Pages, including reference |
| --- | --- |
| Under 50 | 6 to 9 |
| 50 to 500 | 9 to 14 |
| Over 500 | 12 to 18 |

| Page | File | Answers | Visual |
| --- | --- | --- | --- |
| **Overview** | `index` | What is this, and what are its parts? | One connected picture with every part in color, each part shown once, and an arrow for what passes between them. The sequence of steps belongs on the example page. If the app has a screen and the repo has a screenshot, copy it to `docs/site/img/` and show it first. Then the example as a short list. If the repo records what has run for real, add a table of that |
| **Following the example** | your choice, such as `request` | What happens to one input, step by step? | `.trace`: numbered steps with a step map that follows the scroll. A Data button on each step if data crosses a boundary |
| **System** | `system` | What does each part own, and how do they connect? | Parts diagram, then one table row per part |
| **One page per subsystem** | your choice | How does this part work? | Flow, state diagram or table, whichever shows it |
| **Running it**, if it's deployed or has hardware | `deploy` | Where does it run, and what happens when it fails? | Flow or table. This describes the system, and setup steps stay in the README |
| **Decisions** | `decisions` | What was chosen, why, and what was rejected? | Table: decision, why, rejected, date. Take these only from commits and docs that state them, and skip the page if there are none |
| **Open questions** | `open-questions` | What couldn't be confirmed? | List. Include everything you found and couldn't verify |
| **Code map** | `code` | Where do I look to change something? | `.map` table: "If you're looking for", "Look in" |
| **Words we use** | `words` | What does this word mean here? | Table |
| **Sources** | `sources` | What else exists, and where does it disagree with the code? | Table of existing docs with their state, then the mismatches |

Code on this branch counts as built, even if the branch is ahead of the default branch. Work that exists only in docs or issues goes in a `nav` group named `Planned`, or is marked `designed` on the page it belongs to. Never describe it as running.

## 4. Set up the kit

```bash
mkdir -p docs
cp -R .agents/skills/launch-docs/assets/site docs/site
cp .agents/skills/launch-docs/assets/serve.sh docs/serve.sh
chmod +x docs/serve.sh
```

- Fill `site-config.js` with the project name and your `nav`.
- Fill every `{{...}}` in `docs/site/AGENTS.md`, including the example, the colors and what decides what's planned.
- Don't edit `site.js`. Add CSS to the end of `site.css` only if a page needs something the patterns can't do.

## 5. Write the pages

Write in this order, so each page can link to what exists and use the same words: Words we use, System, Following the example, subsystem pages, Running it, Decisions, Code map, Open questions, Sources, and Overview last.

For each page:

1. Read the code for the facts on that page. Don't guess a name, limit, endpoint or default. If you can't confirm one, leave it out and add it to Open questions.
2. Draw the visual first. Each box names a system part and each arrow says what passes.
3. Write the `h1`, one sentence of lede, the visual, then two to four short sections that each answer a different question. Aim for 300 to 600 words.
4. For each number, name or setting, ask what a reader would do with it, and cut it if there's no answer.
5. End with `details.sources`, listing repo paths in `<code>`.

Run the check script as you go, so a mistake doesn't repeat across pages:

```bash
python3 .agents/skills/review-docs/scripts/check.py docs/site/page.html --render
```

## 6. Point the repo at the site

Add this section to the root `AGENTS.md`, creating the file if it's missing, and add one line linking to `docs/site/` in the README:

```markdown
## Documentation

Documentation lives in `docs/site/`. Check it first when you need to understand the system, and put new or updated documentation there. Read `docs/site/AGENTS.md` before changing a page, and run the site with `docs/serve.sh`. Use the `write-docs`, `review-docs` and `plain-writing` skills in `.agents/skills/`.
```

## 7. Check the whole site

```bash
python3 .agents/skills/review-docs/scripts/check.py --all --render
```

- Fix every `FAIL`. Fix each `WARN` unless you can say why it's fine.
- Open the screenshots at both widths if your tools can read images, starting with Overview and the example page. Fix anything clipped, overlapping, crossing or stretched empty. If a sandbox stops Chrome, ask to run the command outside the sandbox. If you still can't render, say so, and don't claim you looked.
- Follow `.agents/skills/review-docs/SKILL.md` for at least the Overview, System and example pages. Check five claims on each against the code, and the direction of every arrow in the Overview and System diagrams.
- Start `docs/serve.sh` in the background, fetch the index page once to confirm it responds, and stop the server unless you were asked to leave it running.

## 8. Report

State the pages built, the command that runs the site, what you couldn't verify, and whether you viewed the rendered pages at both widths. Don't link to a temporary local server unless you left it running. Commit only if you were asked to.
