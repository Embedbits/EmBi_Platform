# EmBi_Platform Module

The EmBi_Platform module provides a unified way to initialize, structure, and manage STM32-based projects.
It automates project creation, directory setup, and BSP initialization for the selected STM32 MCU family.

---

## Contents

This module contains:

- **Artifact handling utilities** – Tools for managing and processing build artifacts (e.g., downloading, versioning, verification).
- **STM32CubeIDE project templates** – Ready-to-use project structures for STM32 microcontrollers.
- **CMake helper scripts** – A collection of helper scripts that simplify integration with CMake-based build systems.
- **Common utilities** – General-purpose tools that can be reused across RAL modules (e.g., hashing, path resolution, or configuration parsing).
- **Updater** – Tool handling necessary EmBi_Platform (STM_Template) updates.

---

## Integration

### 1. Add `EmBi_Platform` as a Git submodule

In your project's **root directory**, execute:

```bash
git submodule add <URL to EmBi_Platform GIT repository> ./EmBi_Platform
```

> **Tip:**
> It is recommended to add the submodule directly under the project root to keep paths consistent with CMake scripts.

---

### 2. Run the Setup Script

#### Windows
```bash
Setup.bat
```

#### Linux / macOS
```bash
./Setup.sh
```

The script will display a **menu with several options**. To initialize a new project, **choose the option "Configuration"** by typing its corresponding number. Several sub-options will be shown, described below.

#### Option: `Initialize project necessary files`

> **This has to be executed once during first project initialization.**

This option will copy user-managed files into the project.

##### CMakeLists.txt

The project root CMakeLists file. User can add pre- and post-build steps, specify required build flags and user functionality.

##### ArtifactsConfig.txt

The artifactory handler configuration file. User can specify required artifacts, their versions and subversion, using the syntax:

```
<artifact_name>;<binary_version>;<handler_version>
```

Example:
```
ninja;1.12.1;1
gcc-arm-none-eabi;13.2.rel1;2
```

#### Option: `Initialize STM32CubeIDE project`

This option will copy STM32CubeIDE project files into the project repository (the top-level `STM32CubeIDE/` folder — see [Project Structure](#project-structure) for how this relates to the template copy shipped inside `EmBi_Platform/STM32CubeIDE`).

#### Option: `Initialize VSCode project`

This option generates the VSCode configuration of the project (`.vscode/`): tasks for build, flashing, unit tests and integration tests, probe-rs debug configurations of the selected MCUs (firmware, attach, integration test firmware), gdb debugging of unit tests, CMake Tools / IntelliSense settings and recommended extensions. See [Project tools](CMake/HelperTools/README.md#vscode-project-initialization).

#### Option: `Configure application layer`

> **This has to be executed once during first project initialization.**

The application module folder structure will be generated, application main entry point header and function files are copied.

#### Option: `Configure BSP module`

> **This has to be executed once during first project initialization or during MCU family change.**

The script will **list all available STM32 MCU families** supported by the BSP system.

Example output:
```
Available BSP Families:
[0]: STM32G4
[1]: STM32G4_Dev
[2]: STM32H5
[3]: STM32H5_Dev
[4]: STM32U5
[5]: master
Enter branch ID (numerical):
```

Enter the corresponding number of your desired MCU family (e.g., `0` for the STM32G4 family). Entries suffixed `_Dev` track the family's development branch; `master` tracks the latest unreleased BSP changes across all families and is intended for platform development/testing rather than production projects.

After the MCU family is selected, the setup script automatically:
- Adds all required **BSP submodules**
- Checks out the correct **branches and commits**
- Updates **CMake configurations** for the selected MCU family

#### Option: `Update documents module`

This option refreshes the local copy of the Docs module content used by the project (e.g., generated/reference documentation pulled in from the platform's docs source).

#### Option: `Configure Middleware module`

> **Run this once per middleware component you want to use, and again any time you want to switch that component to a different version.**

The script first **lists all available middleware components** declared in the Middlewares catalog repository, then, once one is selected, **lists all available versions** (Git tags) of that component's own repository.

Example output:
```
[0]: Return back
[1]: FreeRTOS
[2]: u8g2
Enter middleware ID (numerical):
```
```
Available versions for 'FreeRTOS':
[0]: Latest (V10.4.3)
[1]: V10.3.1
[2]: V10.4.3
Enter version ID (numerical, 0 = Latest):
```

After both are selected, the setup script:
- Adds the component as a **Git submodule** under `Middlewares/ThirdParty/<Name>`, checked out at the selected version.
- Scaffolds a project-side handler folder `Middlewares/<Name>App` (module `<Name>App`, CMake library `<Name>App_Lib` — distinct from the vendored component's names) the **first time only** — this is where your own glue/port code and configuration for the component goes; it is never overwritten by a later re-configuration.
- Wires both folders into `Middlewares/Middlewares.cmake` via `add_subdirectory()` (the `ThirdParty/<Name>` one only if that vendored folder ships its own `CMakeLists.txt`).

Re-running this option for an already-added component with a different version ID switches that component's `Middlewares/ThirdParty/<Name>` checkout to the newly selected version, without touching your handler folder.

#### Option: `Update Middleware module`

Updates a single, already-added middleware component to its **latest available version** — its newest Git tag, or the latest commit of its default branch if it has no tags yet. The same middleware list as above is shown first, so you can pick which component to update.

#### Option: `Module update (Updater)`

Runs the Updater tool (`CMake/Updater/Updater.cmake`), which applies update steps of EmBi_Platform to the **modules of the project** - folders in `Application`, `Bsp` and `Middlewares` with a `CMakeLists.txt` generated from the module template (header `# Template version:`); test sets in `Tests/` are not modules. Every update version is a folder in `CMake/Updater/Updates/<version>/` with one or more step scripts, executed in alphabetical order for every selected module.

| Update | Step |
|--------|------|
| `0.0.1` | Regenerates module `CMakeLists.txt` from the current template (lists parsed from the file), module specific content after the template part (e.g. test registration) is kept. |
| `0.0.2` | Fixes include directories in `target_include_directories()` - `${<Module>_PublicIncludeDirs}` / `${<Module>_PrivateIncludeDirs}` instead of the variable names (only these lines are changed). |
| `0.0.3` | Defines doxygen group of the module (`\defgroup <Module>` block inserted at the beginning of `<Module>_Types.h`, otherwise `<Module>.h`) if the files of the module use `\ingroup <Module>` and the group is not defined. |

The option asks for:
1. **Range of updates** - first and last update ID of the printed list (empty = all updates).
2. **Modules** - module IDs separated by comma (empty or `0` = all modules).
3. **Branches** of the module repositories - empty = the checked out branches only, or branch names / patterns separated by comma (`*` any characters, `?` one character), e.g. `Dev/STM32F4/*,Releases/STM32G4`. Local branches and branches of remote `origin` are matched (a local tracking branch is created when needed). Every matching branch is checked out, updated and the originally checked out branch is restored at the end. The project repository itself is updated on its checked out branch only.
4. **Mode**
   - `Dry run` (default) - changes are shown as a diff and reverted, nothing is written.
   - `Apply` - changes are kept uncommitted (checked out branches only).
   - `Apply and commit` - changes are committed with the entered message (e.g. `AB#123: Module CMakeLists updated.`), optionally pushed to `origin`.

Repositories with uncommitted changes of tracked files are skipped in `Dry run` and `Apply and commit` modes. A summary with the result for every repository and branch (up to date, changed files, commit ID) is printed at the end. Update steps are idempotent - a repeated run reports `up to date`.

The same update can be run from the command line, e.g.:

```bash
cmake -DFUNCTION_ID=UPDATE -DUPDATE_FROM_VERSION=0.0.2 -DUPDATE_BRANCHES="Dev/STM32F4/*" \
      -DUPDATE_MODE=COMMIT -DUPDATE_COMMIT_MESSAGE="AB#123: Module CMakeLists updated." \
      -P EmBi_Platform/CMake/Updater/Updater.cmake
```

All parameters are described in the header of the main functionality in `Updater.cmake`.

---

## Usage

The EmBi_Platform module is intended to be used as a **support layer** within the
Embedded Abstraction framework. It does not contain any hardware-related
components itself, but provides shared functionality and development tools that other,
hardware-specific modules (Application, Bsp, Middlewares) build on.

Typical usage includes:
1. **Artifact Handling** — scripts for managing and verifying downloaded
   or cached artifacts used across the build system.
2. **CMake Integration** — helper scripts for automated setup, environment
   validation, and module registration.
3. **STM32CubeIDE Support** — project templates for generating IDE-compatible
   configurations and testing environments.

> **Note:**
> The EmBi_Platform module is not required for firmware execution on target hardware,
> but it is strongly recommended for development and CI/CD workflows.

---

## Requirements

- Git 1.7.10+
- Bash (Linux/macOS) or the bundled `Setup.bat` (Windows)
- CMake 3.19+
- STM32CubeIDE 1.4.0+
- Supported host OS: Windows, Linux, macOS

---

## Project Structure

```
Project_root/
│
├── Application                   Application module
│   ├── AppCom                    Application communication interface
│   ├── AppComp                   Application components
│   ├── AppCore                   Application core handler
│   ├── AppFun                    Application functionality
│   └── AppMain                   Application main function
│
├── Bsp                           Board Support Packages
│   ├── Hal                       Hardware Abstraction Layer
│   ├── Linker                    Linker generator module
│   ├── Mcal                      Micro-Controller Abstraction Layer
│   ├── Ral                       Register Abstraction Layer
│   └── Startup                   Startup handler
│
├── Middlewares                   Middlewares module
│   ├── ThirdParty                Vendored middleware sources (added per-component as Git submodules)
│   │   ├── FreeRTOS              FreeRTOS sources, checked out at the selected version
│   │   ├── u8g2                  u8g2 sources, checked out at the selected version
│   │   └── ...
│   ├── FreeRTOS                  Project-side FreeRTOS handler (port layer, configuration)
│   ├── u8g2                      Project-side u8g2 handler (port layer, configuration)
│   ├── ...
│   └── Middlewares.cmake         Middlewares root CMake file
│
├── EmBi_Platform                 Platform root folder (this module, added as a submodule)
│   ├── CMake                     CMake build functionality
│   │   ├── ArtifactsManager      Artifacts handling module
│   │   │   ├── Artifacts.cmake   Artifacts core CMake file
│   │   │   └── README.md         Artifacts module documentation
│   │   │
│   │   ├── HelperTools           Reusable CMake helper scripts (hashing, path resolution, config parsing, etc.)
│   │   ├── Build.cmake           CMake core build script
│   │   ├── Flags.cmake           Build flags list
│   │   ├── Platform.c            Top level .c file
│   │   ├── Platform.h            Top level .h file
│   │   └── README.md             CMake component documentation
│   │
│   ├── STM32CubeIDE              STM32CubeIDE project *template* (source copied into the root STM32CubeIDE folder below)
│   └── README.md                 Template documentation
│
├── STM32CubeIDE                  Generated STM32CubeIDE project folder (created from the template above)
│   ├── .cproject                 STM32CubeIDE C project file
│   ├── .project                  STM32CubeIDE project file
│   ├── Debug                     Build output folder
│   └── ...
│
├── ArtifactsConfig.txt           Artifacts configuration file
├── CMakeLists.txt                Project root CMake file
└── README.md                     Project documentation
```

---

## Notes

- The EmBi_Platform module may include external open-source utilities when necessary.
- All internal scripts are written to be platform-independent whenever possible.
- Modifications to this module should be carefully reviewed, as they may
  affect multiple modules across the build system.

---

## License

This platform is made up of components from two different sources, licensed separately:

- **Third-party components** (e.g., packages sourced from STMicroelectronics and other vendors) retain their own original licenses. Refer to each component's folder/README for details.
- **Embedbits-authored components** (EmBi_Platform itself, the CMake helper scripts, Artifact handling utilities, the Updater, and other original tooling not attributed to a third party) are licensed under the [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/): free to use, copy, modify and distribute for **non-commercial purposes**. **Commercial use requires a separate written license from Embedbits.**

Selected companies may be granted a free license to use Embedbits-authored components for commercial purposes under a separate written agreement. Contact nobody@embedbits.com to request one.

---

## Authors

- **Mr.Nobody** — [embedbits.com](https://embedbits.com)

Contributions are welcome for non-commercial improvements! Please open a pull request.

---

## Useful Links

- [STM32CubeIDE](https://www.st.com/en/development-tools/stm32cubeide.html)
- [Azure DevOps](https://azure.microsoft.com/en-us/services/devops/)
- [Embedbits GitHub](https://github.com/Embedbits)
- [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)
