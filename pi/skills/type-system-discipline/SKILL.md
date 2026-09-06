---
name: type-system-discipline
description: Strengthen domain or public types when invalid state combinations, semantically distinct primitives, unsafe casts, non-exhaustive variants, partial operations, or duplicated schemas create correctness risk. Use while designing or revising those contracts in a statically typed language. Do not use for mechanical typed edits, local inference that is already sound, or extra type precision without a concrete unsafe operation.
---

# Type system discipline

Use the type checker to exclude meaningful invalid states while retaining clear, usable interfaces. This skill is self-contained and does not invoke another skill.

## 1. Name the unsafe state or operation

Identify the concrete problem the current type permits:

- contradictory fields or coupled optionals;
- interchangeable primitives with different meanings or units;
- unchecked external data;
- an unsafe cast or forced non-null assertion;
- a closed variant that callers can fail to handle;
- a partial operation whose precondition is not represented;
- a hand-maintained type that can drift from its authoritative schema.

Do not strengthen a type merely because a more precise representation is possible. State which runtime failure, invalid transition, or maintenance hazard the change prevents.

Completion criterion: one concrete unsafe operation or invalid representable state justifies the type change.

## 2. Construct valid states

Prefer representations whose constructors produce valid values:

- sum types or discriminated unions for lifecycle variants;
- a single source of truth instead of a boolean coupled to optional metadata;
- non-empty or ordered structures only for operations that require those properties;
- opaque types, newtypes, or lightweight wrappers for primitives that are easy to interchange incorrectly;
- explicit units for quantities that share a machine representation.

Keep related state and transitions together. Avoid a bag of flags whose combinations require prose to explain. Use the language's simplest idiomatic representation; do not build a framework around one invariant.

Completion criterion: callers cannot construct the targeted invalid state through the normal public API.

## 3. Parse at trust boundaries

Treat CLI arguments, environment variables, configuration, JSON, RPC or IPC payloads, database rows, and other external representations as untrusted until parsed.

At the boundary:

1. validate shape, range, units, and relationships;
2. convert into the domain type;
3. report a structured validation error through the language's idiomatic error mechanism;
4. pass only the validated representation inward.

Runtime validation remains necessary at trust boundaries and for invariants the type system cannot express economically. Assertions remain appropriate for programmer errors and impossible internal states; they are not automatically evidence of a weak type.

Completion criterion: untrusted representations cannot enter domain code while masquerading as validated values.

## 4. Preserve compiler proofs

Avoid casts and coercions that assert an unproven fact. When interop requires one, isolate it at the boundary, validate its preconditions, and expose a safe typed interface.

Match closed variants exhaustively using the language's compiler-checked mechanism. If the language requires a default branch, make it an explicit unreachable or `never` assertion so adding a variant fails compilation or a strict check.

Completion criterion: adding a new closed variant identifies every required handling site, and unsafe interop is isolated behind a checked boundary.

## 5. Derive from authoritative schemas

When a protocol, API schema, database schema, generated interface, or design token source owns a shape, derive or generate dependent types when the toolchain is stable and the generated output is reviewable. Otherwise, add a focused compatibility check at the boundary rather than silently maintaining parallel definitions.

Do not introduce a generator whose maintenance cost exceeds the demonstrated drift risk.

Completion criterion: the type has one authoritative source or a deterministic check that detects divergence.

## 6. Validate utility and migration

Before changing a public or widely used type:

- inspect all construction and match sites;
- confirm inference and error messages remain usable;
- migrate callers in a coherent order;
- run the strictest practical typecheck and focused behavioral tests;
- verify serialization and compatibility when representation crosses a boundary.

Stop strengthening once the targeted partiality or invalid state is removed. Extra precision that adds ceremony without preventing failure is a regression.

Completion criterion: callers compile without unproven casts, behavior checks pass, and the new type prevents the original hazard.
