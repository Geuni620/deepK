<p align="center">
  <img src="DeepK/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="">
</p>

<h1 align="center">deepK</h1>
<p align="center"><a href="README.md">한국어</a> · <b>English</b></p>
<p align="center"><b>Select the text you're reading and press ⌘C twice. A Mac menu bar translator that runs on the AI subscription you already have.</b></p>

<p align="center">
  <a href="https://github.com/Geuni620/deepK/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/Geuni620/deepK?style=flat-square&label=release"></a>
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-bf5af2?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple_silicon-native-5e5ce6?style=flat-square">
</p>

```sh
brew install --cask Geuni620/tap/deepk
```

Select text in any app and press **⌘C twice** to open the translation window. You can copy the translation or explicitly insert it back where you were typing. deepK translates between Korean and English through Codex CLI signed in with ChatGPT, or Claude Code signed in with a Claude subscription.

![Translation window](docs/screenshots/translation-result.png)

## Install

Requires an Apple silicon Mac running macOS 15 or later. There is no Intel build yet.

**Homebrew**

```sh
brew install --cask Geuni620/tap/deepk
```

**Direct download**

Download `deepK-distribution-*.zip` from the [latest release](https://github.com/Geuni620/deepK/releases/latest), unzip it, and move `DeepK.app` to your Applications folder. The app is signed with a Developer ID and notarized by Apple. Each release includes a `.sha256` file you can use to verify the download.

```sh
shasum -a 256 deepK-distribution-*.zip
```

After installing, install [Codex CLI](docs/development.md#codex-cli-준비) or [Claude Code](docs/development.md#claude-code-준비) for translation, sign in with your subscription account on this Mac, and follow [First run](#first-run). Your provider's subscription terms and usage limits still apply.

**Update and uninstall**

- Homebrew: quit the app, then run `brew update && brew upgrade --cask Geuni620/tap/deepk`
- Direct download: replace the app with `DeepK.app` from the new release
- Uninstall: `brew uninstall --cask Geuni620/tap/deepk`, or delete `DeepK.app` from Applications

## Status

deepK is in its first public release. Translation speed depends on the provider, model, and input.

- Text input with automatic translation, automatic or manual language direction
- Results that keep code blocks, inline code, and links, with copy
- Continued translation of paragraphs separated by a divider (`---`)
- Lives in the menu bar, returns to the original app, and inserts only when you ask

## First run

deepK lives only in the menu bar. Launching it does not show a Dock icon or a window; it only adds an icon to the menu bar at the top right of the screen.

1. Open deepK from Applications, or run `open /Applications/DeepK.app` in Terminal, then find the deepK icon in the menu bar.
2. Open Settings from the menu bar, choose Codex or Claude Code, and check the connection.
3. Allow Input Monitoring in macOS System Settings. Inserting back into the original app also needs Accessibility permission. If it still does not work after you allow a permission, quit deepK and launch it again.
4. Select text in another app and press ⌘C twice. You can also type text directly.
5. Review the translation, then copy or insert it. Quit from the menu or with ⌘Q.

Double-copy translation is on by default in a new install and can be turned off in Settings. If the app path changes because of a new checkout or signing method, you may need to grant macOS permissions again.

**If nothing appears after launch**

- With many menu bar icons, the deepK icon can be hidden behind the notch or other icons. Hide or rearrange some menu bar icons and look again.
- A deepK built from source and the released app share the bundle ID `com.deepk.app`. If another copy is already running, `open -a DeepK` only activates that copy instead of launching the new one. Check which path is running with `pgrep -fl DeepK`, quit the other copy from its menu, then run `open /Applications/DeepK.app` again.
- macOS may register permissions separately for each copy of the app. If System Settings lists more than one deepK, turn on permissions for the copy you actually use.

## What is sent, and security limits

deepK sends the translation instructions and your source text to the provider you selected. It uses the official CLI you signed in to and never switches automatically to another provider or to API-key billing. Credentials, local environment files, and signing keys are not part of this repository.

- **Codex global instructions:** if `~/.codex/AGENTS.md` exists, its contents are included in requests. Do not put company secrets or tokens in that file. Project instructions and skill blocking do not remove this global file.
- **Sensitive copies:** copies that a password manager marks as concealed or transient are rejected. Copies that are marked late or not marked at all, and text pasted directly into the source field, are not protected. Testing against specific password managers is still pending.
- **Translation cache:** successful results are kept in memory for up to 32 entries and 5 minutes, and cleared when the app restarts.
- **Test coverage:** offline tests and synthetic request checks are kept separate from checks with real accounts, apps, and permissions. This is not a complete real-world security audit.

See the [development guide](docs/development.md#보내는-내용과-실행-환경) for which environment variables are passed through, and the [security review notes](plans/public-release-security.md) for known limits. Do not post source text, tokens, or credential files in public issues or logs. Detailed documents are written in Korean.

## Build from source

Requires macOS 15 or later, full Xcode, and Swift 6. The tested environment is Xcode 26.1.1 / Swift 6.2.1. Install the CLI for your provider separately and sign in with your subscription account on the same Mac.

```sh
git clone https://github.com/Geuni620/deepK.git
cd deepK
./scripts/build-and-run.sh
```

The script quits any running deepK, then builds, signs, and launches it. This also quits the released deepK, which uses the same bundle ID. Any open translation is not preserved. To build only, use `./scripts/build.sh`.

- [Set up Codex CLI](docs/development.md#codex-cli-준비)
- [Set up Claude Code](docs/development.md#claude-code-준비): the app's install script needs Node.js and npm.
- To update later: `git pull --ff-only`, then `./scripts/build-and-run.sh`

A source ZIP without Git history must set `DEEPK_BUILD_NUMBER` when building. See the [development guide](docs/development.md#새-git-이력의-빌드-번호) for build numbers under the new Git history and what to watch for when replacing an existing install.

## Repository layout

```text
deepK/
├── DeepK/                 # Mac app source and resources
├── DeepKTests/            # App tests and synthetic fixtures
├── DeepK.xcodeproj/       # Xcode project
├── scripts/              # Build, test, and packaging tools
├── docs/                 # Development and distribution guides, test material
├── plans/                # App plans and earlier notes
├── benchmarks/           # Measurement samples and results
└── landing/              # Astro landing page and plans
```

Installers are published in this repository's [GitHub Releases](https://github.com/Geuni620/deepK/releases), and the Homebrew cask lives in [Geuni620/homebrew-tap](https://github.com/Geuni620/homebrew-tap). See the [landing guide](landing/README.md) to run and test the landing page.

## Development and testing

```sh
./scripts/test.sh
./scripts/build.sh
node --test scripts/fixture-server.test.mjs
python3 scripts/test-app-bundle-contents.py
```

The test tools need `rg` and Python 3. The development fixture server checks also use Node.js. `test.sh` covers logic, fake transport, and offscreen rendering, and never calls a real subscription. Checks that use real accounts or the GUI require separate, explicit options.

- [Development details and test commands](docs/development.md)
- [Preparing and distributing installers](docs/distribution.md)
- [Per-app real-world check notes](plans/mac-integration-checks.md)
- [Landing page docs](landing/README.md)

This repository starts from the current source with a new Git history. PR numbers and commit references in older development documents belong to the earlier private history.

## Third-party data

The Hanja reading table includes Unicode Unihan data. The full Unicode License v3 text is kept in the [third-party notices](THIRD-PARTY-NOTICES.txt) and the [data source](DeepK/Translation/HanjaReadingData.swift). The reuse license for the project as a whole has not been decided yet.
