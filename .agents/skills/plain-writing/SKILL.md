---
name: plain-writing
description: Write and edit documentation, UI copy, slides and design notes in plain, concrete language with no LLM-style phrasing. Use when writing or rewriting text someone will read, or when asked to remove slop, cringe or AI-sounding language.
---

# Plain writing

Write the way you'd explain something to a friend who is a good engineer. Every sentence should say which part of the system did what.

## Rules

1. **Name the actor and the action.** Prefer "The server saves the message, then queues a job."
2. **Describe software as software.** Processes run, models return output, code saves records. Software doesn't notice, know, think, understand, care or decide what matters.
3. **State checkable facts.** Cut praise and emphasis such as real, actual, honest, true, trust, natural, feel, useful, meaningful, seamless, robust and powerful unless the word states something a reader could check.
4. **Use one noun for one thing.** Use the project's glossary and don't vary terms to sound interesting. Don't invent labels or analogies.
5. **No slogans.** Avoid "X, not Y", "It isn't X, it's Y", "the real question", "load-bearing", rhetorical questions, aphorisms and punchy fragments.
6. **Write full sentences.** Don't use `=`, `→`, `+` or `≠` as shorthand in a sentence, and avoid em dashes and semicolons. Arrows are fine in diagrams and labels.
7. **Use concrete examples.** Show a specific message, task or value in place of an abstract description.
8. **Keep it short.** Use lists and tables where they scan better. Keep paragraphs to one or two sentences.
9. **Don't narrate.** Remove "this section explains", "it's worth noting", "in short" and any mention of how the text was written.
10. **Stay neutral about people.** Write "the user". Don't name the project's owner or address the reader with praise.

## Corrections from past reviews

These are the kinds of lines reviewers rejected, and what replaced them.

| Rejected | Problem | Replacement |
| --- | --- | --- |
| It does real work in the background while you keep talking. | "Real work" says nothing. | One conversation stays open while background tasks run. |
| The runtime keeps it honest. | Gives software a character. | The runtime checks and records. |
| It stays quick because it never does the work itself. | Vague, and it reads like a slogan. | It only has task tools, so replies don't wait on task work. |
| Did the right thing happen? | "The right thing" can't be checked. | Did the requested answer, artifact, action or schedule result? |
| Are its claims backed by something real? | Emphasis word and vague object. | Are claims backed by available evidence? |
| Did it feel natural? | A feeling, with no test. | Did the reply fit the requested voice, format and level of detail? |
| Notice something useful and explain why it's interrupting. | Gives software intent. | Start from a trigger, and state the reason for any interruption. |
| Stay quiet unless it matters. | "Matters" has no test. | No alert unless the condition is met. |
| Logged every promise. | Sounds meaningful and says little. | Saved each scheduled delivery as a record. |
| The orchestrator, the brain, the engine | New names for existing things. | The name the code uses, such as `TaskRunner`. |
| Spend alerts sit on Deployment. | Figure of speech. | Deployment lists the spend alerts. |
| Export failures produce local diagnostics. | Doesn't say what happens. | A failed export writes one line to stderr. |
| Confidence never gates action. | Jargon verb. | No code compares confidence to a threshold. |
| The fallback stores no invented confidence. | Code doesn't invent things. | The fallback stores no confidence. |

## Final read

Read each line as a skeptical reader would. For each one, ask:

- Which component does this, and could a reader check it?
- Is there a word that could be deleted with no change in meaning?
- Could a pronoun and verb pair be read in an odd way? "Took her also mid-task" failed this check.
- Does it repeat what's already on screen or in the sentence before it?

Rewrite or cut any line that fails.
