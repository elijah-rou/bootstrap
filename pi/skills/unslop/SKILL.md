---
name: unslop
description: Polish substantial human-facing prose or perform a requested prose cleanup, preserving meaning and voice. Use after the artifact's primary writing task. Routine replies and small copy edits need no separate pass. Do not rewrite code, commands, structured data, quotations, or raw technical notes.
---

# Unslop

Produce prose that sounds specific to its author, audience, and subject. This skill is self-contained and does not invoke another skill.

## 1. Preserve the contract

When another skill owns the artifact's structure or technical content, run this skill after that work and revise only the human-facing prose.

Before rewriting, identify:

- the intended audience and action;
- the writer's existing tone and level of formality;
- facts, claims, names, numbers, URLs, and qualifications that must not change;
- quoted text, code, commands, and structured data that must remain exact.

Do not invent opinions, evidence, confidence, familiarity, or personal voice. Ask only when ambiguity would change the meaning or authority of the text.

Completion criterion: the rewrite boundary is clear and protected spans remain unchanged.

## 2. Remove formulaic patterns

Look for these patterns in context rather than applying mechanical word bans:

- stock transitions such as “additionally,” “moreover,” and “in conclusion” where the structure already carries the transition;
- inflated vocabulary such as “delve,” “pivotal,” “robust,” “seamless,” “landscape,” “tapestry,” “testament,” and “leverage” when a plain, precise word exists;
- filler such as “it is important to note,” “in order to,” and repeated previews or conclusions;
- forced contrasts such as “not just X, but Y” when a direct statement is stronger;
- artificial groups of three, false ranges, synonym cycling, and repeated sentence shapes;
- superficial participial clauses that append vague significance, such as “highlighting,” “showcasing,” or “underscoring” without evidence;
- vague attribution such as “experts say” or “industry reports suggest” without a named source;
- promotional claims, generic optimism, excessive hedging, and conclusions that only restate the introduction;
- excessive headings, bold lead-ins, decorative punctuation, or list structure that makes ordinary prose look templated;
- chatbot framing, praise, performative agreement, and closing invitations that the recipient did not need.

Retain a flagged word or construction when it is the most accurate or natural choice. The goal is credible prose, not compliance with a forbidden-word list.

Completion criterion: each retained sentence contributes a concrete fact, instruction, judgment, transition, or necessary qualification.

## 3. Make the prose specific

Prefer:

- named actors and active verbs;
- concrete nouns, real examples, measured values, and cited sources;
- one stable term for each concept;
- direct judgments supported by reasons;
- sentence lengths and paragraph shapes that follow the material rather than a template.

Apply the portability test to subject-specific claims: if one could appear unchanged in an unrelated document, make it specific or cut it. Preserve intentionally conventional language such as required notices, standard calls to action, and ordinary courtesy when it serves the audience.

Completion criterion: subject-specific claims are concrete, while intentional standard language remains intact.

## 4. Preserve human rhythm

Mix short and longer sentences where the ideas warrant it. Keep useful asides, contractions, first person, technical vocabulary, and mild irregularity when they match the writer. Do not manufacture informality or “personality.”

Use punctuation for clarity. Parentheses, colons, passive voice, adverbs, and three-item lists are valid when they are the clearest construction.

Completion criterion: the prose reads naturally aloud and still sounds like the intended writer.

## 5. Final audit

Check that the rewrite:

- preserves every factual claim and qualification;
- contains no invented source, number, experience, or certainty;
- leaves code, links, quotations, and structured content intact;
- removes repeated ideas and stock openings or closings;
- matches the requested format and can be pasted without cleanup.

When the user asked only for polished copy, return the copy without an editing preamble or postscript.
