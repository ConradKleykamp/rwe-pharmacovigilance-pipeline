# Analysis Summary

Findings from the three Phase 2 queries in `sql/queries/`. All three define a proxy for a concept Synthea does not label directly (adherence, adverse events, drug interactions). See README's "A note on framing" for why, and `data-dictionary.md` for the underlying schema.

## Query 1: Medication history & adherence

Scope: oral tablets with 5+ fills, assessed per patient-drug pair. A gap of more than 30 days between one fill's stop and the next fill's start counts as non-adherent.

| Metric | Value |
|---|---|
| Patient-drug pairs evaluated | 4,696 |
| Distinct patients | 2,241 |
| Adherent pairs | 4,400 |
| Non-adherent pairs | 296 |
| Patients with at least one non-adherent pair | 188 |

The largest gaps involve pain medications: a 1,335-day gap on prednisone, and several gaps over 1,100 days on an acetaminophen/oxycodone combination product. This fits a pattern of episodic, as-needed use rather than a true lapse in a maintenance therapy, which is a limitation of the 30-day-gap definition worth noting rather than a data problem.

The drug with the most non-adherent patients is lisinopril (61 patients), followed by hydrochlorothiazide (46) and amlodipine (40). These are all long-term blood pressure medications, where a real-world adherence problem is plausible and worth flagging.

## Query 2: Adverse event identification

Scope: inpatient or emergency encounters that overlap a patient's active medication window, excluding the encounter that prescribed the medication. Not restricted to oral tablets.

| Metric | Value |
|---|---|
| Flagged encounters | 12,311 |
| Emergency | 8,480 |
| Inpatient | 3,831 |
| Total (patient, medication, encounter) rows | 56,643 |
| Low severity | 6,905 encounters |
| Polypharmacy (5+ concurrent meds) | 4,418 encounters |
| Excessive polypharmacy (10+ concurrent meds) | 988 encounters |
| Highest concurrent medication count on a single encounter | 19 |

The most frequently implicated drugs are nitroglycerin, metoprolol, and insulin, all common cardiac and metabolic maintenance medications. This is expected: patients on these drugs tend to have more chronic conditions overall, so they show up more often near a hospitalization, not necessarily because the drug itself caused the visit.

## Query 3: Drug interaction flags

Scope: medication pairs from a curated set of 5 known-interacting drug classes, active at the same time for the same patient.

| Interaction | Pairs flagged | Patients affected |
|---|---|---|
| ACE inhibitor + NSAID (reduced antihypertensive/renal effect) | 8,981 | 442 |
| Anticoagulant/antiplatelet + NSAID (bleeding risk) | 2,735 | 405 |
| Calcium channel blocker + statin (myopathy/rhabdomyolysis risk) | 1,972 | 40 |
| Benzodiazepine + opioid (respiratory depression risk) | 51 | 8 |

The ACE inhibitor + NSAID pair is by far the most common, which lines up with how frequently both drug classes are prescribed in this dataset. The benzodiazepine + opioid pair is rarest, but is also the most clinically dangerous of the four, since this combination carries an FDA boxed warning for respiratory depression. Low volume does not mean low priority here.

## Limitations

All three queries are modeled proxies over synthetic data, not clinical findings. Adherence, adverse events, and drug interactions are inferred from encounter and medication timing, not from a labeled outcome in the source data. The drug interaction reference table only covers 5 class pairs, chosen because both classes are well represented in this dataset, not because they are the only interactions that matter clinically.

## Recommendations

- Treat the adherence gap threshold (30 days) as tunable. Pain medications show gaps this definition was not designed for, and a shorter threshold or a drug-class-specific threshold would reduce that kind of false positive.
- Query 2's severity tiers reflect medication burden, not confirmed harm. Any downstream use should treat "excessive polypharmacy" as a flag for review, not a diagnosis.
- The drug interaction reference table (query 3) is a good candidate for expansion if the project scope grows again. The current 5 pairs were chosen for data coverage, not clinical completeness.
