# Feedback-loop options

Choose the first option that reaches the real symptom with adequate fidelity. Do not build a larger harness when a smaller one is sufficient.

1. **Focused failing test** at the public seam that exposes the bug.
2. **CLI command with a fixture** and an assertion on exit status, stdout, stderr, or output files.
3. **HTTP request script** against a bounded local service, asserting the relevant response or side effect.
4. **Browser automation** that checks the DOM, console, request, or navigation state tied to the symptom.
5. **Captured-event replay** using a redacted request, payload, trace, or event sequence.
6. **Throwaway local harness** around the smallest real subsystem and controlled dependencies.
7. **Differential loop** comparing known-good and current versions, configurations, datasets, or implementations.
8. **Version bisection** with an automated pass/fail command and a clean worktree.
9. **Property or fuzz loop** with fixed seeds, explicit case/time limits, and minimized failing input.
10. **User-assisted procedure** with numbered steps and a precise observation to return when automation cannot reach the environment.

## Tightening

After the first reproduction:

- cache or remove unrelated setup;
- assert the exact symptom rather than general failure;
- freeze time, random seeds, locale, and network dependencies where relevant;
- cap retries, parallelism, trace size, and elapsed time;
- print one verdict and only the evidence needed to explain it.

## Intermittent bugs

Measure a reproduction rate over a bounded sample. In a disposable local or test environment, increase signal through controlled stress, repeated runs, scheduling perturbations, or narrowed timing windows. Never stress shared or production systems without explicit approval. Record the sample size and rate before and after each probe.

## Performance regressions

Use repeatable inputs and warmup policy. Capture distributions rather than one timing. Prefer profilers, query plans, allocation data, and version/configuration comparisons. Establish the baseline before changing code.
