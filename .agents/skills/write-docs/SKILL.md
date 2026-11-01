---
name: write-docs
description: Add or change a page on this repo's docs site in docs/site, in the site's visual-first style. Use when asked to write, add, update, split or rework documentation, including design docs, decisions and architecture pages. If docs/site doesn't exist yet, use launch-docs instead.
---

# Write docs

Follow these steps in order, and do each one even if the request sounds small. Paths are from the repo root.

## 1. Read the rules

Read these files in full before writing:

- `docs/site/AGENTS.md`, the page rules and this project's example and colors
- `.agents/skills/plain-writing/SKILL.md`, the sentence rules
- `docs/site/words.html`, the glossary
- `.agents/skills/launch-docs/references/patterns.html`, every component with its markup
- Two existing pages from the site, one with a flow and one with tables

## 2. Find the place

List `docs/site/` and read `nav` in `docs/site/site-config.js`. Search the site for the topic.

- If a page covers the topic, change that page and link to it from anywhere else that mentions the topic.
- Create a page only for a topic that has no home. Add it to the matching `nav` group, and to a group named `Planned` if none of it is built.
- A page covers one topic. If the topic won't fit in about 800 words, plan two pages.

## 3. Get the facts from the code

Read the code on this branch before you write a claim, and don't use notes from other sessions as a source. The code decides what's built. `docs/site/AGENTS.md` says what decides what's planned.

- Keep a list of the files each fact came from, and use it for the Sources section.
- Don't guess a name, limit, endpoint, field or default. If you can't confirm one, leave it out or add it to `open-questions.html`.
- Mark anything that isn't in this branch's code as `designed`. Never describe planned work as running.
- Select the facts a reader needs. For each number, name or setting, ask what a reader would do with it, and cut it if there's no answer. Test files, queue sizes, flush timeouts and fallback orders usually go.

## 4. Choose the visual, then outline

The visual comes before any section text. Pick the one that shows the idea:

| The topic is | Use |
| --- | --- |
| A sequence of steps or a request path | `.flow` with `.node` and `.arrow` |
| One input followed through several systems | `.trace` with a step map |
| A choice | `.flow` with `.node.decide` and `.branch` |
| States of something | `.states` |
| Parts and how they connect | `.flow`, or inline SVG if position carries meaning |
| A set of options or fields | A compact table in a `.card` |
| A screen | A screenshot from the running app, with made-up data |

Where the topic allows, follow the project's default example through the visual. Each box names a system part and each arrow says what passes, as `docs/site/AGENTS.md` describes.

Outline the page as `h1`, one sentence of lede, the visual, then two to four short sections that each answer a different question. Aim for 300 to 600 words. The 800-word limit is a ceiling, so a page near it usually has too much in it.

## 5. Write the page

Copy the skeleton in `docs/site/AGENTS.md`. Use its existing classes, and don't add navigation, previous and next links, copy icons or filters, because `site.js` adds them.

- Lead each section with a table, list or diagram, and use prose only for what those can't show.
- Use the default example the reader can follow.
- Put long lists of tokens, limits and fields in one `details.more` section, and only if a reader would look them up.
- End with `details.sources`, listing repo paths in `<code>`.

When you change an existing page, rework the affected sections so the page reads as one piece. Don't stack new text on top of old text, and remove anything the change makes untrue. Keep existing headings where possible, because link IDs come from them.

## 6. Update what the change touches

- `words.html` for a term the page depends on and the reader may not know, usually one or two at most
- `decisions.html` for a new design decision, with its date and what was rejected
- `open-questions.html` for anything unresolved, and remove questions the change settles
- `code.html` when the page adds a new area of code
- Links from related pages

Keep each of these edits small, and don't touch unrelated pages. Don't restructure existing content just to clear a warning that was already there. Mention it in your report.

If a page you're changing makes a claim the code and sources don't support, remove it from that page. Add it to `open-questions.html` if it might still be true, and say so in your report.

## 7. Check it

Run the review checks on each page you changed, and fix every failure:

```bash
python3 .agents/skills/review-docs/scripts/check.py docs/site/your-page.html --render
```

`--render` saves screenshots at 1440 and 375 px and prints their paths. Open them if your tools can read images. A check that passes doesn't replace looking at the page. If a sandbox stops Chrome, ask to run the command outside the sandbox, and if you still can't render, say so.

Then follow `.agents/skills/review-docs/SKILL.md` on your own page. Fix what you find, and cut anything the checks warn about unless you have a reason to keep it.

## 8. Report

State the pages changed by repo path, the code files you checked, what you couldn't verify, and whether you viewed the rendered page. If you couldn't render it, say so. Don't link to a temporary local server.
