

<div style="display: flex; align-items: center;">
  <img src="https://github.com/bloomingchad/pnimrp/raw/main/web/ico.ico" alt="pnimrp Icon" width="90" style="margin-right: 10px;" />
  <h1>♪♫ pnimrp - Poor Man's Radio Player in Nim ♫♪</h1>
</div>

sick of opening chrome just to stream some internet radio?
i made this little terminal radio player that's saved me tons of ram

with a collection of over 700 radio stations, curated and modifiable,
you can play your favorite stations all from the comfort of your terminal

inspired by [poor man's radio player](https://github.com/hakerdefo/pmrp),
**pnimrp** aims to extend pmrp whilst keeping familiarity.

[![Windows](https://img.shields.io/badge/Windows-7_|_11-0078D6?logo=windows&logoColor=white)]()
[![Debian AntiX](https://img.shields.io/badge/Debian_AntiX-19.1_|_23.2-A81D33?logo=debian&logoColor=white)]()  
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04_|_24.04-E95420?logo=ubuntu&logoColor=white)]()
[![Termux](https://img.shields.io/badge/Termux-Android-3DDC84?logo=android&logoColor=white)]()  
[![FreeBSD](https://img.shields.io/badge/FreeBSD-14.x-AB2B28?logo=freebsd&logoColor=white)]()
[![NetBSD](https://img.shields.io/badge/NetBSD-10.1-FF6600?logo=netbsd&logoColor=white)]()  
[![OpenIndiana](https://img.shields.io/badge/OpenIndiana-2022.10_|_2023.10-ED2E38?logo=openindiana&logoColor=white)]()  
[![Haiku](https://img.shields.io/badge/Haiku-R1_Beta4_|_Beta5-FFCC00?logo=haiku&logoColor=black)]()

## 🎥 demo

![pnimrp demo](https://github.com/bloomingchad/pnimrp/raw/main/web/demo.gif)

made with [asciinema](https://asciinema.org/)

## 🌟 key features

- **portable**: works on unix and windows
- **easy to use**: simple intuitive interface
- **curatable stations**: edit json files to add or remove stations easily
- **now playing**: displays the currently playing song
- **lightweight**: minimal dependencies, fast and efficient
- **customizable themes**: easily switch between themes by editing `config.json`
- **checked links**: links get checked automatically so you dont waste your time.

## ⬇️  installation

### step 1: install **mpv** (might need development build/files)

**pnimrp** uses `mpv` for audio playback.  install both the `mpv` player *and*
  its development files

**Linux:**

*   **Debian/Ubuntu:**      `sudo apt install mpv libmpv-dev`
*   **Fedora/CentOS/RHEL:** `sudo dnf install mpv mpv-devel` (may need [RPM Fusion](https://rpmfusion.org/))
*   **Arch Linux:**         `sudo pacman -S mpv` (includes development headers)
*   **openSUSE:**           `sudo zypper install mpv libmpv-devel`
*   **other distros:** Use your package manager; search for "mpv" and a related "dev/devel/headers" package.

**Windows:**

1. get mpv and development files:
   - download from:
     1. [sourceforge](https://sourceforge.net/projects/mpv-player-windows/files/)
     2. [mpv.io](https://mpv.io/installation/)
     3. [shinchiro's builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases)
     4. [zhongfly's builds](https://github.com/zhongfly/mpv-winbuild/releases)
   - you'll need:
     - the main `mpv-dev*` matching package (* means matching)

2. extract both packages. the `dev` archive contains:
   - `libmpv*.dll` (name may vary slightly)

3. after compiling `pnimrp`:
   - copy `libmpv*.dll` to the same directory as `pnimrp.exe`

**macOS X:**
*   **Homebrew (Recommended):** `brew install mpv`
*    **MacPorts:** `sudo port install mpv`

**FreeBSD:**
`sudo pkg install mpv`

**Termux (Android):**
```pkg install mpv```

### step 2: install the nim compiler:

- **unix**:
  ```bash
  curl https://nim-lang.org/choosenim/init.sh -sSf | sh
  ```
note this wouldnt work on termux, instead do
**Termux (Android):**
```pkg install nim```

- **Windows**:
  download the latest release from [choosenim](https://github.com/dom96/choosenim/releases).

- **FreeBSD**:
```pkg install nim```

- **other distros**:
  follow the official [nim installation guide](https://nim-lang.org/install.html).

### step 3: install **pnimrp**:
```bash
nimble install pnimrp
```

or compile it manually:
```bash
nim c -d:release pnimrp
./pnimrp
```
want a simple build? (very minimal):
```bash
nim c -d:release -d:simple pnimrp
```

cant/dont want emojis?: add `-d:noEmoji`

want to use smaller bin size?: add `-d:useJsmn`

<p align="right">(<a href="#top">back to top</a>)</p>

## 🎮 controls

| key          | action                      |
| ------------ | --------------------------- |
| **1-9, a-l** | select menu options         |
| **r**        | return to the previous menu |
| **q**        | quit the application        |
| **p**        | pause/resume playback       |
| **m**        | mute/unmute                 |
| **+**        | increase volume             |
| **-**        | decrease volume             |

## 📖 documentation

for detailed usage instructions, see:
- 📄 **doc/user.md**: user guide.
- 📄 **doc/installation.md**: installation instructions.

## 🤝 contributing

here is how you can help:

1. **submit pull requests**: fix bugs you found or propose and add new functionality.

please read our [Contributing Guidelines](CONTRIBUTING.md) for more details.

## 📜 license

**pnimrp** is primarily licensed under the **Mozilla Public License 2.0 (MPL-2.0)**.
see the [LICENSE](LICENSE) file for details.

however, the following component is licensed with their respective original licences:
- **illwill.nim**: adapted from [illwill](https://github.com/johnnovak/illwill),
  this file is used for non-blocking input handling and is licensed under the WTFPL.

- **jsmn.nim**: See More [jsmn.nim](https://github.com/OpenSystemsLab/jsmn.nim)
  this file is under original licence which is MIT.

for more information about WTFPL, see: [WTFPL License](http://www.wtfpl.net/).
  the original license text is included in the file.

## 🙏 credits

- **pmrp**: inspiration and initial codebase 💡
- **libmpv**: playback functionality
- **c2nim**: wrapping objects
- **illwill**: async input handling
- **jsmn.nim**: minimal json parser impl
- **GPT-3.5 Claude-3.5-Sonnet**: documentation and code improvements
- **DeepSeek-V3**: documentation and Code improvements 🥰
- **fmstream.org and others**: for providing links
- **asciinema**: for being able to show HD demo 🎥
- **you**: for using and supporting this project! ❤️

## 🎶 happy listening!

thank you for using **pnimrp**. please do share it with your minimalist friends

<p align="right">(<a href="#top">back to top</a>)</p>
