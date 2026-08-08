# Liquid Notes

Liquid Notes is a Flutter iOS notes app with a Cupertino interface and a liquid-glass inspired visual style.

## Features

- Create and edit notes
- Search by title or body
- Pin, favorite, and swipe-delete notes
- Local persistence with `shared_preferences`
- Translucent glass panels, blur, soft highlights, and floating controls

## Local Checks

```bash
flutter pub get
flutter analyze
flutter test
```

## Build IPA With GitHub Actions

This repository includes `.github/workflows/ios-ipa.yml`.

1. Push this project to GitHub.
2. Open the repository on GitHub.
3. Go to `Actions`.
4. Select `Build iOS IPA`.
5. Click `Run workflow`.
6. After it finishes, download the `liquid-notes-unsigned-ipa` artifact.

The workflow builds on GitHub's macOS runner with:

```bash
flutter build ios --release --no-codesign
```

Then it packages `Runner.app` into:

```text
LiquidNotes-unsigned.ipa
```

## Signing Note

The generated IPA is unsigned. It is useful as a build artifact, but it will not install on a real iPhone unless it is signed with an Apple Developer certificate and provisioning profile.

For a directly installable IPA, configure Apple signing on macOS or extend the workflow with Apple certificate and provisioning profile secrets.
