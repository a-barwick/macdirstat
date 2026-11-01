# Writing {{PROJECT}} docs pages

This folder is the {{PROJECT}} docs site. Read this file before adding or changing a page. Follow these rules unless the repo owner says otherwise.

## This project

- **Default example:** {{EXAMPLE, one concrete input the pages follow, such as a specific request, command or file}}
- **Colors:** {{Which part of this system each color means. c1 blue: ... c2 green: ... c3 orange: ... gray: storage and infrastructure. wait yellow: waiting.}}
- **What decides what's built:** the code on this branch. The site ships with the code it describes, so code that's ahead of the default branch still counts as built.
- **What decides what's planned:** {{Where planned work is recorded in this repo: an issue tracker, a roadmap file, or decisions.html}}

## What a page should feel like

A reader should get the idea from the picture, understand it from a few short lines, and only open details if they want them. Write the way you'd explain it to a friend who is a good engineer.

1. **Visual first.** Open with a diagram, a state flow or a compact table. If a page has no visual, ask what it should be before writing more text.
2. **Easy to scan.** Use short lists and tables. Keep paragraphs to one or two sentences.
3. **Details stay hidden until asked for.** Put depth in a Data button or a `details.more` section.
4. **Minimal UI.** Add a control or label only if the page needs it.

## Writing rules

- Describe software as software: processes run, models return output, code saves records. Don't write that the software notices, knows, thinks, understands or decides what matters.
- Don't use praise or emphasis words such as real, actual, honest, true, trust, natural, feel, useful or meaningful unless they state a checkable fact.
- Use full, plain sentences with concrete nouns and verbs. "The server saves the record, then queues a job."
- Don't write slogans, aphorisms or punchy fragments. Avoid "X, not Y", "It isn't X, it's Y", "the real question", "load-bearing" and similar lines.
- In sentences, don't use `=`, `→`, `+` or `≠` as shorthand, and avoid em dashes. Arrows are fine in diagrams and labels.
- Use the default example above instead of abstract descriptions.
- Keep labels short. Don't add subtitles, captions or helper text that only repeat what's on screen.
- Don't narrate the page ("this section explains") or mention how it was written. Don't describe the site itself, its buttons, its markings or where setup steps are kept.
- Read each line as a skeptical reader would and cut anything vague or odd-sounding.

Use the same words everywhere. `words.html` defines them. Don't add synonyms, and add a new term there before using it.

## Page structure

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Page title · {{PROJECT}}</title>
<link rel="stylesheet" href="site.css">
<script src="site-config.js" defer></script>
<script src="site.js" defer></script>
</head>
<body>
<h1>Page title</h1>
<p class="lede">One sentence on what this is, in plain words.</p>
<!-- A diagram, state flow or table goes here. -->
<section><h2>A short heading</h2>
<!-- Short lists, tables and cards. -->
</section>
<details class="sources"><summary>Sources</summary><p><code>path/to/file</code> · <code>path/to/other</code></p></details>
</body>
</html>
```

Then add the page to `nav` in `site-config.js`. `site.js` adds the navigation, previous and next links, section lists, copy links and the filter. Don't copy those into a page, and don't change `site.js` for one project.

- Keep each page to one topic. Link to another page instead of repeating it.
- Split a page that passes about 800 words into pages by topic. Reference pages such as Decisions can run longer.
- Don't list every value just because the code has it. Leave out what a reader can't act on, such as queue sizes, flush timeouts and fallback chains. Put long lists of tokens, limits or fields in one `details.more` section.
- Give each question one section. Two tables that both answer "where does this go" should be one table.
- A table with three or more columns gets `class="stack"`, which stacks each row on a phone.
- In a table, each row describes one thing and each column is a property of it. Don't line up unrelated items in the same row. The first column renders bold, so keep it to a short name.
- Describe the system. Setup steps and instructions for contributors or agents belong in `AGENTS.md` or a README.
- Every heading gets a copy-link icon automatically. Only the icon is interactive, so don't make headings or subtitles clickable. Link IDs come from the heading text, so renaming a heading breaks old links to it.
- Use relative links such as `tasks.html`, because the site won't always be hosted at the root of a domain.
- List sources as repo paths in `<code>`, relative to the repo root. The check script confirms that each one exists.
- Use what's already in `site.css`: `card`, `grid2`, `grid3`, `flow`, `node`, `branch`, `states`, `seq`, `step`, `trace`, `say`, `tag`, `pts` and `map`. `.agents/skills/launch-docs/references/patterns.html` shows each one with its markup. Add new CSS at the end of `site.css` only when a page needs something those can't do.
- Don't add a framework, a build step or external scripts without asking first.

## Diagrams

- Prefer `.flow` and `.node` HTML diagrams because they adjust to the screen width. Use inline SVG when position carries meaning, and give a wide SVG `class="wide"` so it scrolls on a phone and stays readable.
- Keep the colors consistent with the list at the top of this file. Color boxes with `.c1`, `.c2`, `.c3` and `.wait` whenever those parts appear. Unmarked boxes are gray.
- In a `.trace` map, lines stay unlabeled because the caption above the map says what passes. Elsewhere, label every arrow whose meaning isn't obvious, and don't let lines cross boxes or text. An arrow's direction is a fact, so check it against the code. When things pass both ways, draw two arrows with a label on each.
- Keep box text to one short sentence, and move detail to a table or list below the diagram. Name a system part in each box, and say on each arrow what passes between them. A box such as "Filters" or "One request, one trace" is a concept, so it belongs in text.
- Keep `.branch` columns about the same depth, because a shorter column stretches into an empty box.
- Start each `.branch` box after a `.decide` node with the answer it follows, such as "Yes" or "No".

## Built and planned

Readers must always be able to tell what runs today.

- Mark anything not in this branch's code with `class="designed"`. Mark uncommitted work with `class="in-review"`. The filter finds both.
- Add `<span class="tag design">designed</span>` where the marking alone isn't clear.
- A page that is entirely planned goes in a `nav` group named `Planned`, which labels it automatically.
- If a marked sentence is hidden, the text around it must still read properly.

## Facts

When sources disagree, the code decides what's built. Built means the code exists. If the repo records what has been tested or has run in production or on hardware, state that separately.

- Check limits, names, endpoints and tools against the code before writing them down. Don't copy them from an older doc. Keep units as the code has them: bytes and characters differ.
- Use only this repo as a source. Notes or memory from other sessions aren't sources.
- If a source is out of date, follow the code and add the conflict to `sources.html`.
- Date any cost or measurement, and say that it's a planning figure if it is.
- Never include secrets, API keys, personal email addresses, serial numbers, deploy preview hostnames, account names, or real user data and IDs. The site may be public.
- Record each new design decision in `decisions.html`, with its date and what was rejected. Add unresolved questions to `open-questions.html`, and remove them once settled.

## Data buttons

A Data button shows the request, response and saved record behind a step or a table row.

- Add `data-flow="key"` to a table row, add the key to `window.FLOWS` in a data script, and load that script before `site.js`. Steps in a `.trace` read `window.TRACE.data`.
- Take endpoints and field names from the code, and set `source` to the file they came from.
- Values are invented, so use made-up examples. Mark anything shortened with `…`.
- Don't add a Data button to something that isn't built yet, because there's no code to base it on.

## Before you finish

Run the checks, then look at the pages. `--render` needs Chrome or Chromium, and saves screenshots at 1440 and 375 px.

```bash
python3 .agents/skills/review-docs/scripts/check.py --all --render
docs/serve.sh
```

- Look at the page at desktop and phone widths. It shouldn't scroll sideways.
- Try the filter and any Data buttons.
- Read the text once more against the writing rules above.

## Publishing

The site runs locally with `docs/serve.sh`, which prints its URL. Don't publish it without being asked. Don't commit unfinished pages to the default branch.
