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

This option will show available middleware modules. After selection, the chosen module is added into the project's `Middlewares` folder as a Git submodule.

#### Option: `Update EmBi_Platform`

Runs the Updater tool to check the currently integrated EmBi_Platform (STM_Template) version against the latest available release and applies the update, re-running any configuration steps that changed as a result.

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
├── Middlewares                   Middlewares module (added per-module as Git submodules)
│   ├── ModBus                    Modbus protocol middleware
│   ├── Log                       Logging middleware
│   └── ...
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
