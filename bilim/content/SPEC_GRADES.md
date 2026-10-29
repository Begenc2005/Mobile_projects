# Bilim lesson writing spec (v2)

Bilim is a free learning app for school students aged 6–18 (grades 1–12). Content is general world knowledge at international school level (think Cambridge/IB/Khan Academy quality), NOT tied to any ministry programme. Every text is bilingual: Turkmen (Latin script, modern orthography with ä ç ž ň ö ş ü ý) and Russian.

## Your job
For each (grade, subject) pair you are assigned, read the year plan in `/home/claude/bilim/content/plan.json` (`plan["<grade>"]["<subject>"]` = list of 6 topics, each `{tk, ru}`) and write ONE lesson per topic — 6 lessons per pair, in topic order.

Write each pair to `/home/claude/bilim/content/grades/g<grade>/<subject>.json` (create the folder; use the Write tool; one file per pair; never touch other files):

```json
{
  "grade": 3,
  "subject": "math",
  "lessons": [
    {
      "id": "math-3-multiplication-table",
      "grade": 3,
      "topic": 0,
      "title": {"tk": "…", "ru": "…"},
      "minutes": 8,
      "steps": [ … ]
    }
  ]
}
```
- `topic` = 0-based index of the topic in the plan list (0..5). Title = the topic title (you may make it slightly more specific).
- `id` = `<subject>-<grade>-<short-latin-slug>`, lowercase a–z, digits and hyphens only, unique.
- `minutes` 5–12.

## Steps (6–8 per lesson, in this order)
1. `{"type":"theory","text":{"tk":…,"ru":…}}` — the core idea, clear and correct. Short paragraphs, `\n` line breaks, `•` bullets. For grades 7–12 include the real terms, formulas, dates.
2. `{"type":"example","text":{…}}` — a worked example step by step.
3. Optionally a second `theory` step if the topic needs it.
4. 3–4 question steps, mixing types (use at least two different types):
   - `{"type":"choice","q":{…},"options":[{tk,ru} or "plain string", … exactly 3],"answer":<0-based index>,"hint":{…},"explain":{…}}`
   - `{"type":"input","q":{…},"answer":"12","hint":{…},"explain":{…}}` — short answer; numbers preferred; alternatives separated by `|` (e.g. `"doesn't|does not"`, `"0.5|1/2"`). Never require long text.
   - `{"type":"truefalse","q":{…},"answer":true|false,"hint":{…},"explain":{…}}`
   Spread correct options across positions 0/1/2. Hints guide without revealing. Explanations show the reasoning.
5. Last step: `{"type":"world","text":{…}}` — one genuine world-knowledge fact connected to the topic (a discovery, a record, a scientist, an everyday application). Must be true and widely documented; if unsure of a number, omit the number.

## Quality rules
- Correctness first: double-check every fact, formula, calculation, date and answer index.
- Age level: grades 1–2 — very short sentences, numbers ≤ 20 (grade 2 ≤ 100), friendly, emoji as pictures (🍎🍎🍎). Grades 3–4 simple. 5–6 clear basics. 7–9 standard secondary level. 10–12 upper-secondary depth.
- Language subjects: `turkmen` = Turkmen grammar/writing (examples in Turkmen; explanations in both languages). `reading`/`literature` = reading skills and world + Turkmen literature (discuss authors and works; never reproduce poems or song lyrics; at most one short quoted line, only from authors who died before 1929). `russian` = Russian as a second language for Turkmen-speaking students (grades 1–4 vocabulary/phrases, later grammar); examples in Russian. `english` = English as a foreign language; examples in English, explanations in TK/RU.
- History: neutral, factual, world perspective; no political judgements about modern governments.
- Write everything in your own words. Natural, correct Turkmen and Russian.
- Keep JSON valid: escape quotes inside strings, no trailing commas, no comments.

## Before finishing
Validate each file you wrote:
`python3 -c "import json,sys;d=json.load(open(sys.argv[1]));assert len(d['lessons'])==6;[print(l['id'],len(l['steps'])) for l in d['lessons']]" <path>`
and check every `choice` answer index is within its options. Fix and re-validate if anything fails.
Report only: files written and anything you were unsure about (one line each).
