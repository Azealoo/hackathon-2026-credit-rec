# DubHacks '26 rules and Visa track: what is published

Checked **2026-10-14** in the built-in browser, public pages only (no sign-in, no account). Anything not confirmed is marked **(u)**.

**Pages read:**
- [Devpost overview](https://dubhacks-2026.devpost.com/): requirements, prizes, judges, judging criteria
- [Devpost rules](https://dubhacks-2026.devpost.com/rules)
- [Devpost schedule](https://dubhacks-2026.devpost.com/details/dates)
- [Devpost updates](https://dubhacks-2026.devpost.com/updates): empty, "Stay tuned"
- [dubhacks.co](https://dubhacks.co/): no rules or guide
- [dh26.dubhacks.co](https://dh26.dubhacks.co/): Tracks section (click a dish to open its text), Schedule, FAQs

**Not readable:** the '26 Hacker Guide. The Devpost overview says "check your hacker guide", but its "hacker guide" link is a broken relative URL (`.../hacker%20guide` returns "Sorry, that page does not exist"). No guide link appears on dubhacks.co or dh26.dubhacks.co. Web search found nothing **(u)**. It may be sent to registered participants by email or Discord.

## 1. Code written before the event

**The rules page says (verbatim):** "Any projects submitted must be started and completed during the duration of DubHacks '26." ([rules](https://dubhacks-2026.devpost.com/rules), 2026-10-14)

- This is the same sentence as the '24 Hacker Guide. The rules page has **no 70-30 / 30% carve-out**. The '24 carve-out may be in the '26 Hacker Guide, which we couldn't read **(u)**.
- Read literally, the published '26 rule is stricter than "up to 30% pre-written": it says started and completed during the event. The repo's pre-event commits would contradict "started".
- Not stated anywhere we could read: whether boilerplate, libraries, or planning/spec work count, or how it is enforced **(u)**.

## 2. Maximum team size

**Four.** Rules page: "Teams may have up to four members." Overview: "Participants form teams of up to four." ([rules](https://dubhacks-2026.devpost.com/rules), [overview](https://dubhacks-2026.devpost.com/), 2026-10-14). Our roster of A/B/C/D fits.

## 3. Visa track

**Name and prize:** "Visa: Reimagine Shopping", $5,000 in cash, 1 winner ([overview, Prizes](https://dubhacks-2026.devpost.com/#prizes), 2026-10-14). The track art file is named `dish-visa-reimagine-shopping`.

**Prompt (verbatim, [dh26.dubhacks.co Tracks](https://dh26.dubhacks.co/#tracks), 2026-10-14):**

> Use generative AI to craft smarter, effortless commerce experiences. Design and build a commerce experience that makes shopping more intuitive and personalized, transforming one or more stages of the journey: discovery, decision-making, personalization, checkout, payments, loyalty and rewards, or post-purchase.

Note it asks for **generative AI**. Paywise's LLM cart parsing and cause classification (§7.3) are the answer to that. The rules-only fallback modes alone would not be.

**Judging rubric (verbatim headings, [overview, Judging Criteria](https://dubhacks-2026.devpost.com/), 2026-10-14).** This is the event-wide rubric. No Visa-specific rubric is published.

| Criterion | Weight | Published description |
|---|---|---|
| Functionality | 30% | "Code Functionality and Quality of Execution" |
| Track Applicability | 30% | "How related projects are to their chosen track" |
| Design | 20% | "User Interface/Aesthetics" |
| Creativity | 20% | "Unique/New Solution to a Problem with Little Weaknesses" |

Each criterion says: "Refer to rubric on the Hacker Guide for further clarification on point breakdowns." The point breakdowns are unread **(u)**.

**Judge listed:** Lisa Kapil, Visa (overview, JUDGES).

**Title track or sponsor prize?** Visa is a **sponsored side track**, not a title track. This is read from the overview, not stated outright: it says each team submits to "exactly one title track" and "can additionally participate in up to three sponsored side tracks". The title-track prizes (1st and 2nd) are listed as Chef's Kitchen, Community Kitchen and Cook Smarter. Visa has one cash prize, the same shape as the other sponsor prizes. So we need one title track plus Visa. Cook Smarter ("AI agents, automation, productivity tools... workflows that reduce friction") is the closest fit on its text (dh26 Tracks), but which title track to pick is the team's call.

Naming mismatch: Devpost lists "Chef's Kitchen"; dh26.dubhacks.co lists "Chef's Choice". Same track or not **(u)**.

**Do sponsor judges visit tables?** Not published **(u)**. The overview says only "Some side tracks will use a video submission in place of an in-person judging round." Which tracks, and whether Visa is one of them, is not stated **(u)**. If Visa is a video track, the video becomes the primary judged artifact.

## 4. Deadlines, video, judging

| Item | Published | Source (checked 2026-10-14) |
|---|---|---|
| Draft on Devpost | **Sat Oct 17 before 10:30 PM.** Add all teammates (with Discords) and declare tracks. "If you do not submit a draft on Saturday night, you will not be able to participate in judging on Sunday!" | [overview](https://dubhacks-2026.devpost.com/) |
| Final Devpost submission | **Sun Oct 18 before 10:00 AM** per the overview. The Devpost schedule page says submissions end **Oct 18, 10:30 AM PDT**. dh26 Schedule says "10:30AM Submissions Due!". **Conflict, so treat 10:00 AM as the deadline.** | [overview](https://dubhacks-2026.devpost.com/), [schedule](https://dubhacks-2026.devpost.com/details/dates), [dh26](https://dh26.dubhacks.co/#schedule) |
| Submission window opens | Oct 17, 8:00 AM PDT | [schedule](https://dubhacks-2026.devpost.com/details/dates) |
| Judging | Sun Oct 18, **11:30 AM – 2:00 PM** | [dh26 Schedule](https://dh26.dubhacks.co/#schedule). The Devpost Judging row is blank. |
| Winners announced | Oct 18, 3:00 PM PDT (Devpost); Closing Ceremony 2:15–3:05 PM (dh26) | both |
| Other Saturday times | Check-in 9:30–11:00 AM; Opening Ceremony 11:00 AM–12:30 PM; Workshops 1:30–4:30 PM; Career Fair 2:30–4:00 PM; Dinner 6–7 PM | [dh26](https://dh26.dubhacks.co/#schedule) |
| Video length limit | **Not published (u)**. Not on the overview, rules or schedule pages. | all Devpost pages above |
| Judging format (in person, expo, rounds) | **Not published (u)**, beyond "some side tracks use video in place of an in-person round". | overview |
| Venue | UW Seattle, Husky Union Building (Devpost); dh26 says "36 hours" and "2-day". | overview, dh26 FAQs |

Our internal Sunday 10:00 AM hard deadline matches the earliest published final deadline. Our Saturday 12:30 PM start matches the page's Opening Ceremony end. The Saturday 10:30 PM **draft** is a new hard gate that SPEC §14.3 may not carry **(u)**: check.

## Proposed SPEC edits

SPEC.md is not edited here. Another session applies these.

**§11.0 Published criteria**
- Replace the placeholder bullet with the Visa prompt above (verbatim), source `dh26.dubhacks.co/#tracks`, checked 2026-10-14. Name: "Visa: Reimagine Shopping", $5,000, 1 winner.
- Replace the "'25 rubric weights" bullet with the published '26 weights: Functionality 30, Track Applicability 30, Design 20, Creativity 20 (source: Devpost overview). Drop the "~20% unseen" and the '25 numbers. Note the point breakdowns are in the unread Hacker Guide **(u)**.
- Add: the prompt asks for generative AI; keep the LLM path in the demo, not only `PARSER_MODE=rules`.
- Add: Visa is a sponsored side track; the team also needs one title track (suggest Cook Smarter, team to confirm).
- Change the header line 3 "track name and prompt (u)" to the track name and a pointer to §11.0.

**§14.2 roster note**
- Add under the roster: "Max team size is 4 (Devpost rules); the roster of 4 is the maximum, so no extra member." Change D's Friday 6:00 PM gate-review item from "reads the '26 rules" to "reads the Hacker Guide and Discord", since the Devpost rules and tracks are now read. Add the **Saturday 10:30 PM draft submission** (declare tracks, add all four members and their Discords) to §14.3 as a gate.

**§16 risks**
- Rewrite the "Pre-event code vs the rules" row. The '26 rules page says "started and completed during the duration of DubHacks '26", with **no 30% allowance** on the rules page (the Hacker Guide may still have one **(u)**). The earlier row "team decided pre-event code is allowed, with no disclosure" now conflicts with the published text. The repo's pre-event commits (public repo) are visible. Mitigation: ask on Discord before Thursday build starts; until answered, keep pre-event work to what the Hacker Guide allows (spec, design, fixtures, research) **(team decision)**.
- Update "Track structure and judging mode in '26 (u)": Visa is a sponsor side track; judging is Sun 11:30 AM–2:00 PM; whether Visa judging is in person or by video is still **(u)**.
- Add a row: final-deadline conflict (10:00 vs 10:30 AM) and the mandatory Saturday 10:30 PM draft.
- In the Unverified list, remove "the '26 rules, Visa prompt and rubric" and replace with "the '26 Hacker Guide (point breakdowns, 70-30 text, video limit)".
- In the §16 Rules source line, the "DubHacks '26 Devpost rules" entry is no longer "(u): not reachable"; it is read and confirmed on 2026-10-14.

## Still ask on Discord

1. Does the '26 Hacker Guide keep the 70-30 rule? May we submit a repo with commits made before Oct 17 12:30 PM (specs, scaffolding, fixtures)? Do we need to disclose it?
2. Where is the '26 Hacker Guide? The Devpost link is broken.
3. Final submission deadline: 10:00 AM (Devpost overview) or 10:30 AM (schedule pages)?
4. Is Visa judged in person or by video? Do Visa judges visit tables, and how long is a slot? If video, what is the length limit?
5. Video length limit and format for the main Devpost submission.
6. Point breakdowns for each rubric criterion, and does Visa score with the same four criteria?
7. Does "Chef's Kitchen" (Devpost) equal "Chef's Choice" (dh26)? Is Visa a fourth track on the dh26 page alongside the three title tracks, or a side track only?
8. Are external APIs and sandboxes (Visa Acceptance sandbox, paid LLM APIs) allowed, and are Visa API credits or mentors available?
9. Is a physical iPhone and a Mac setup allowed on the table, and is power and Wi-Fi guaranteed at tables (demo needs a phone with iOS 27)?
