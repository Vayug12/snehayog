# GitHub Actions Workflows

This directory contains GitHub Actions workflows for automating the build, test, and release process of the Vayug Flutter app.

## 📋 Available Workflows

### 1. **CI** (`ci.yml`)
Runs on every pull request and push to main branches.

**What it does:**
- ✅ Runs Flutter tests
- ✅ Analyzes code quality
- ✅ Builds APK (debug) to verify compilation
- ✅ Uploads test coverage

**Triggers:**
- Pull requests to `main`, `master`, or `develop`
- Pushes to `main`, `master`, or `develop`

---

### 2. **Build Android** (`build-android.yml`)
Builds Android APK or App Bundle on demand or when tags are pushed.

**What it does:**
- ✅ Builds signed APK (for releases)
- ✅ Builds signed App Bundle (for Play Store)
- ✅ Uploads artifacts for download

**Triggers:**
- **Manual:** Go to Actions → Build Android → Run workflow
- **Automatic:** When you push a tag starting with `v` (e.g., `v1.4.1`)

**Manual Options:**
- Build Type: `apk` or `appbundle`
- Build Mode: `release` or `debug`

---

### 3. **Release** (`release.yml`)
Automatically creates a GitHub Release with built artifacts.

**What it does:**
- ✅ Builds signed APK and App Bundle
- ✅ Creates GitHub Release
- ✅ Uploads APK and AAB to release assets
- ✅ Generates release notes from commits

**Triggers:**
- When you push a tag like `v1.4.1` or `v1.5.0-beta` 

**How to use:**
```bash
# Create and push a tag
git tag v1.4.2
git push origin v1.4.2
```

---

### 4. **Code Quality** (`code-quality.yml`)
Checks code quality, formatting, and dependencies.

**What it does:**
- ✅ Runs Flutter analyze
- ✅ Checks code formatting
- ✅ Checks for outdated dependencies
- ✅ Generates analysis reports

**Triggers:**
- Pull requests
- Weekly schedule (Mondays at 9 AM UTC)

---

## 🔐 Setting Up Secrets (For Signed Builds)

To build signed APKs/App Bundles, you need to add these secrets in GitHub:

1. Go to **Repository Settings** → **Secrets and variables** → **Actions**
2. Add these secrets:

### Required Secrets:
- `ANDROID_KEYSTORE_FILE` - Base64 encoded keystore file
- `ANDROID_KEYSTORE_PASSWORD` - Keystore password
- `ANDROID_KEY_ALIAS` - Key alias
- `ANDROID_KEY_PASSWORD` - Key password

### How to create base64 keystore:
```bash
# On your local machine
base64 -i path/to/your/keystore.jks | pbcopy  # Mac
base64 -i path/to/your/keystore.jks           # Linux
certutil -encode keystore.jks keystore.b64    # Windows
```

---

## 🚀 Quick Start Guide

### 1. Run CI checks on PR:
Just create a pull request - CI will run automatically!

### 2. Build APK manually:
1. Go to **Actions** tab
2. Select **Build Android**
3. Click **Run workflow**
4. Choose `apk` and `release`
5. Click **Run workflow**

### 3. Create a release:
```bash
# Update version in pubspec.yaml
version: 1.4.2+25

# Commit and push
git add pubspec.yaml
git commit -m "Bump version to 1.4.2"
git push

# Create and push tag
git tag v1.4.2
git push origin v1.4.2
```

The workflow will:
- ✅ Build signed APK and AAB
- ✅ Create GitHub Release
- ✅ Upload artifacts

---

## 📦 Downloading Build Artifacts

### From Actions:
1. Go to **Actions** tab
2. Click on the completed workflow run
3. Scroll to **Artifacts** section
4. Download the artifact

### From Releases:
1. Go to **Releases** page
2. Click on the release version
3. Download APK or AAB from assets

---

## ⚙️ Workflow Configuration

### Flutter Version
All workflows use Flutter `3.24.0` (stable channel). To update:
```yaml
flutter-version: '3.24.0'  # Change this in workflow files
```

### Java Version
Android builds use Java 17. This matches your `build.gradle.kts` configuration.

---

## 🔧 Troubleshooting

### Build fails with keystore error:
- ✅ Check if secrets are properly set in GitHub
- ✅ Verify keystore file is base64 encoded correctly
- ✅ Ensure key.properties format is correct

### Tests failing:
- ✅ Run `flutter test` locally first
- ✅ Check if all dependencies are in `pubspec.yaml`
- ✅ Ensure test files are in correct location

### Analysis errors:
- ✅ Run `flutter analyze` locally
- ✅ Fix warnings/errors before pushing
- ✅ Check `analysis_options.yaml` configuration

---

## 📝 Notes

- **Unsigned builds:** Workflows can build unsigned APKs if keystore secrets are not set
- **Artifact retention:** Artifacts are kept for 90 days (configurable)
- **Coverage:** Test coverage is uploaded to Codecov (if configured)
- **Cache:** Flutter dependencies are cached for faster builds

---

## 🎯 Best Practices

1. **Always test locally** before pushing
2. **Update version** in `pubspec.yaml` before creating releases
3. **Use semantic versioning** for tags (e.g., `v1.4.2`)
4. **Review CI results** before merging PRs
5. **Keep secrets secure** - never commit keystore files

---

## 📚 Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Flutter CI/CD Guide](https://docs.flutter.dev/deployment/cd)
- [Android App Signing](https://developer.android.com/studio/publish/app-signing)

