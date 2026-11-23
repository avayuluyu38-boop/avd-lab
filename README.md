# avd-lab

Throwaway lab for checking how Android and Play Protect treat side-loaded and
updated APKs. Everything runs in GitHub Actions on the stock emulator images, so
results are reproducible and nothing touches a real device.

`workflow_dispatch` inputs pick the install mode (`dropper`, `shell_pm`,
`shell_vending`), the system image (`playstore`, `apis`) and the API level.
`scripts/matrix.sh` drives the run, the artifacts keep the screenshots and the
`pm`/`appops` dumps.

Layout:

- `apk/` — signed test builds (a dropper and its payload);
- `scripts/tap.py` — taps a UI element by its visible text;
- `scripts/matrix.sh` — the matrix that `lab.yml` executes.

The emulator has no Play Protect service of its own, so the Play Store images are
used when the app-verification path matters.
