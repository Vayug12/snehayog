# Vayug mobile journeys

These flows exercise the shipped Android APK as a black box. Maestro reads
Flutter's accessibility/semantics tree, so selectors should use visible copy or
stable `Semantics.identifier` values. Do not use Flutter `Key` values here;
they are not exposed to Android accessibility services.

Run locally with an Android emulator or device connected:

```bash
adb install -r path/to/app-release.apk
maestro test .maestro --include-tags smoke
```

Add one flow per user outcome, not per screen. Every flow should have a stable
name, tags, explicit assertions, and no production-destructive action. Tests
that create ads, upload videos, delete content, or move money must use a
dedicated QA account and staging data before they are enabled in CI.

The workflow builds its own debug-signed APK from the ref under test, so QA
never depends on the release keystore. A manual run can select any ref, which
makes every issue reproducible against an exact binary.

Selectors must use identifiers that exist for automation (`nav_*`, `screen_*`).
Never derive them from display copy: that copy is remote-configurable, so a
wording change would break the journey silently.

`run-maestro.sh` suppresses system crash/ANR dialogs (`hide_error_dialogs`)
before installing. A cold-booted emulator keeps updating GMS packages, and a
background app that stalls under that load raises an "isn't responding" dialog
which owns the accessibility window -- Maestro then reads the dialog instead of
the app and every selector fails. A failure of that shape is emulator load, not
a product defect, so keep the suppression in place.

