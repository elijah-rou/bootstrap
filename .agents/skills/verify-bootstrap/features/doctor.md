# Health diagnosis

Users run the installer’s doctor command to see available or missing binaries and distinguish linked configuration from a usable installation.

## Sub-features

- `doctor-installed` reports installed core and selected tool commands.
- `doctor-missing` returns failure and names missing tools after configuration-only linking.
- `doctor-agent-version` additionally checks the pinned Pi version when selected; outside this smoke.

## How to get to it (user POV)

- Run `./install.sh doctor` from the checkout after installation or offline linking.
- The same command diagnoses an uninstalled account with a not-installed error; that state is mapped but not driven here.

## Driving it with Docker

Preconditions:

- `verify.sh doctor RUN_ID` has passed. It checks harness readiness, not product installation health.

- **Missing tools.** In an offline run, `verify.sh drive RUN_ID doctor` invokes `./install.sh doctor` after an offline link, then uninstalls. Require `PASS doctor:`, `artifacts/doctor/product-doctor.exit` to contain `1`, and `product-doctor.stdout` to include `missing` rows.
- **Installed tools.** In a bridge run, `verify.sh drive RUN_ID install` invokes product doctor after install/rerun/relink. Require zero overall exit, `ok` rows for core tools and `just`, and subsequent actual executable/version checks in the harness.
- **Proof.** Keep `artifacts/doctor/` and `drive-install.stdout`/`.stderr`. These are distinct entry states, not interchangeable evidence.
- **Skipped states.** Report doctor before any state exists and Pi-specific version diagnosis as not exercised.

## Gotchas

- Most doctor rows check command availability, not pinned binary versions; do not overclaim version validation.
- Baseline Node may exist while Bun and other core tools are missing. A negative offline doctor is expected.
- The read-only harness Doctor and product `install.sh doctor` serve different purposes.
