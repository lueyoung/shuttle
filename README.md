# Shuttle (for Apple Silicon)

A simple shortcut menu for macOS

This fork is maintained by Young Lue and updated for modern macOS and Apple Silicon development.

Status:

* Builds locally with `xcodebuild` on Apple Silicon
* Produces app bundles inside the project at `products/Debug/Shuttle.app`
* Includes recent compatibility fixes for terminal launching and launch-at-login

## This Fork

This repository is a fork of the original Shuttle project with local changes for modern macOS and Apple Silicon development.

Notable differences in this fork:

* Apple Silicon friendly build setup
* Updated local `xcodebuild` workflow
* App output goes to the project-local `products/` directory
* Ongoing maintenance by Young Lue

## Maintainer

This fork is maintained by Young Lue.

Recent work in this fork includes:

* Apple Silicon build and local development fixes
* Modernized `xcodebuild` flow and shared scheme setup
* Updated launch-at-login compatibility for modern macOS
* Build output cleanup and project-local app packaging
* README and developer workflow updates for this fork

## Installation

### Option 1: Download a Release

1. Download the latest build from this fork's GitHub Releases page.
2. Move `Shuttle.app` to `/Applications`.

### Option 2: Build Locally

1. Clone this repository.
2. Run:

```bash
./scripts/build-debug.sh
```

3. The app will be generated at:

```bash
products/Debug/Shuttle.app
```

4. Move `products/Debug/Shuttle.app` to `/Applications`, or run it directly.

## Build

Build locally with:

```bash
./scripts/build-debug.sh
```

The built app will be generated at:

```bash
products/Debug/Shuttle.app
```

You can launch it with:

```bash
open products/Debug/Shuttle.app
```

Intermediate build data is stored in:

```bash
.deriveddata/
```

## Configuration

By default Shuttle reads its config from:

```bash
~/.shuttle.json
```

It can also read:

* `~/.shuttle-alt.json`
* `~/.ssh/config`
* `/etc/ssh_config`
* `/etc/ssh/ssh_config`

## Help
See the [Wiki](https://github.com/fitztrev/shuttle/wiki) pages. 

## Roadmap

* Cloud hosting integration
  * AWS, Rackspace, Digital Ocean, etc
  * Using their APIs, automatically add all of your machines to the menu
* Preferences panel for easier configuration
* Update notifications
* Keyboard hotkeys
  * Open menu
  * Select host option within menu

## Contributors

The original Shuttle project was created by [Trevor Fitzgerald](https://github.com/fitztrev). Many people have contributed improvements over time, and this fork continues that work with Apple Silicon and modern macOS maintenance by Young Lue.

(In alphabetical order)

* [Alexis NIVON](https://github.com/anivon)
* [Alex Carter](https://github.com/blazeworx)
* [bihicheng](https://github.com/bihicheng)
* [Dave Eddy](https://github.com/bahamas10)
* [Dmitry Filimonov](https://github.com/petethepig)
* [Frank Enderle](https://github.com/fenderle)
* [Jack Weeden](https://github.com/jackbot)
* [Justin Swanson](https://github.com/geeksunny)
* [Kees Fransen](https://github.com/keesfransen)
* Marco Aurélio
* [Martin Grund](https://github.com/grundprinzip)
* [Matt Turner](https://github.com/thshdw)
* [Michael Davis](https://github.com/mpdavis)
* [Morton Fox](https://github.com/mortonfox)
* [Pluwen](https://github.com/pluwen)
* Rebecca Dominguez
* [Rui Rodrigues](https://github.com/rmrodrigues)
* [Ryan Cohen](https://github.com/imryan)
* [Stefan Jansen](https://github.com/steffex)
* Thomas Rosenstein
* [Thoro](https://github.com/Thoro)
* [Tibor Bödecs](https://github.com/tib)
* [welsonla](https://github.com/welsonla)

## Credits

Shuttle was inspired by [SSHMenu](http://sshmenu.sourceforge.net/), the GNOME applet for Linux.

I also looked to projects such as [MLBMenu](https://github.com/markolson/MLB-Menu) and [QuickSmileText](https://github.com/scturtle/QuickSmileText) for direction on building a Cocoa app for the status bar.
