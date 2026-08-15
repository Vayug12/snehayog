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

The scheduled workflow uses the latest GitHub Release APK. A manual run can
select a specific release tag, which makes every issue reproducible against an
exact binary.

