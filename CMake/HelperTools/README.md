# Project tools

This module provides a Windows and Linux/Unix scripts, that offers an interactive menu for executing various CMake utility scripts.  
It is designed to simplify project setup and maintenance tasks by grouping commonly used actions into an easy-to-use interface.

---

## 📌 Main screen

After script execution the main menu looks like this:

```
=====================================
0: Exit
1. Add module
2: Add module component
3: Add module CMake file
4: Add tests to existing module
5: Configuration
6: Build
7: Tests
8: Documentation
=====================================
Enter your selection (0-8):
```

Note: The actual menu may vary based on the specific implementation and available scripts.

---

## Create module

This option allows user to create a new module in the project.  
When selected, the script will prompt for the module name and other relevant details, then generate the necessary folder structure and files.

### Folder structure created:

```
ModuleName/
├─ CMakeLists.txt
├─ ModuleName_Port.h
├─ ModuleName_Types.h
├─ ModuleName.c
├─ ModuleName.h
└─ Tests/                        - Unit and integration tests (see Add tests)
```

#### CMakeLists.txt

CMakeLists.txt file will contain basic configuration to include the module in the build system. 
It will generate static library target for the module. The library name will be same as module name with postfix "_Lib".

#### ModuleName_Port.h

This header file will contain public port definitions for the module, such as function prototypes. 
User shall not call any other internal functions directly. This shall be the single entry point for the module.

#### ModuleName_Types.h

This header file will contain all public type definitions, enums, structs and macros.

#### ModuleName.c

This source file will contain the implementation of the module's functions.
This file is usually used as public API for the module. All necessary external functions shall be encapsulated here same as public functions defined in ModuleName_Port.h.

#### ModuleName.h

This header file will contain internal type definitions, enums, structs and macros used only within the module.

---

## Add component

This option allows user to add new component to an existing module.
When selected, the script will prompt for the module name and component details, then generate the necessary files within the specified module.

### Folder structure created:

```
ModuleName/
├─ CMakeLists.txt                - Existing file
├─ ModuleName_Port.h             - Existing file
├─ ModuleName_Types.h            - Existing file
├─ ModuleName.c                  - Existing file
├─ ModuleName.h                  - Existing file
├─ ModuleName_ComponentName.c    - New component source file
└─ ModuleName_ComponentName.h    - New component header file
```

---

## Add CMake file

This option allows user to create or update the CMakeLists.txt file for a specific module.

---

## Add tests

This option copies the testing template (`Test_Handler/Template`) into an existing module - unit
tests (`UT`), integration tests (`IT`) or both (`ALL`). "Create module" calls the same script
(`Test_Handler/TestInit.cmake`), so every new module has its tests from the start. Existing files
are never overwritten, registration of the tests (`UnitTesting_AddPath`,
`IntegrationTesting_AddPath`) is added to `CMakeLists.txt` of the module if missing.

The testing frameworks (`UnitTesting`, `IntegrationTesting`) are independent of the target - every
test set lists and initializes everything it needs itself:

```
ModuleName/Tests/
├─ UnitTests/
│  ├─ CMakeLists.txt             - UnitTesting_Add_Test (mocks, target emulation, HOST_LIBS)
│  └─ Test_ModuleName.c          - Unity test cases on host
└─ IntegrationTests/
   ├─ CMakeLists.txt             - IntegrationTesting_Add_Test (all libraries of the firmware)
   ├─ ItTest_ModuleName.c        - Unity test cases on target
   ├─ ItTarget_ModuleName.c      - Target interface: entry point, init, debug freeze, faults, reset
   └─ BspMain.h                  - Entry point called by StartUp
```

Direct call:

```bash
cmake -DTEST_INIT_MODULE_PATH=Bsp/Mcal -DTEST_INIT_MODULE_NAME=Gpio -DTEST_INIT_TYPES=IT -P CMake/HelperTools/Test_Handler/TestInit.cmake
```

---

## Build

This option configures and builds the project (`Build_Handler/Build_Handler.cmake`). The script lists
all MCUs of the project - configure presets of the project `CMakePresets.json` (project root) - and
asks for the build type (`Debug` / `Release`). Preset `<MCU>_<BuildType>` is configured and built,
the output is stored in `Build/<MCU>_<BuildType>`.

Direct call (from `EmBi_Platform` folder):

```bash
cmake -DFUNCTION_ID=MCU_LIST                          -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
cmake -DFUNCTION_ID=BUILD -DMCU_ID=8 -DBUILD_TYPE=Release -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
cmake -DFUNCTION_ID=BUILD -DBOARD=STM32H503xB -DBUILD_TYPE=Debug -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
```

`BOARD` (a board name of the detection or a target `<board>@<host>:<probe>` of the board lists) builds the preset of
the MCU of the board in the build folder of the board `Build/<MCU>_<Debug|Release>_<board>` with the configuration
of the board (`TARGET_BOARD`: fixture `IT_FIXTURE` / `IT_FEATURE_<X>` and the own `defines` of `ItBoards.json`,
`CMake/IntegrationTesting/README.md`, *Board fixtures*).

---

## Tests

This option builds and executes unit tests (host) or integration tests (board):

1. Test type - `Unit tests` or `Integration tests`.
2. Target - MCU of the project presets (unit tests, preset `<MCU>_UnitTest`) or connected board
   (integration tests - boards of this machine and of the IT agents of `ItHosts.json` are detected
   before the list is printed, MCU of every probe identified by `Bsp/Ral/RalPresets.json`, optional
   `IntegrationTestBoards.json` of the project as override, stored in `Build/IntegrationTestBoards.json`;
   one item per physical board `<board> - <name of the board> [@ <IT agent>]`, the preset of its board
   configured with `INTEGRATION_TEST_BOARD=<board>`, `INTEGRATION_TEST_PROBE=<its probe>` and
   `INTEGRATION_TEST_HOST=<its IT agent>` - the firmware of a board of an IT agent is executed there,
   see `CMake/IntegrationTesting/README.md`) or all connected boards.
3. The preset is configured and built, test sets of the build (CTest labels = names of the test
   sets, eg. `Gpio`, `ModBus_Crc`) are listed.
4. One test set or all of them (`0`) are executed (`ctest --preset <preset> -L ^<TestSet>$`).
5. Results are printed per test set (passed / failed / skipped) with the list of failed and skipped
   tests, taken from the JUnit file `Build/<preset>/<Unit|Integration>TestResults.xml`.

```
=====================================
Test results
=====================================
PASSED  Crsf_Crc: passed 7, failed 0, skipped 0
FAILED  Gpio: passed 12, failed 1, skipped 0
-------------------------------------
FAIL  Gpio.It_Gpio_Set_PinPull_InputPullUp_PinReadsHigh
-------------------------------------
Total: passed 19, failed 1, skipped 0
=====================================
```

Direct call (from `EmBi_Platform` folder):

```bash
cmake -DFUNCTION_ID=TEST_TARGET_LIST -DTEST_TYPE=UT                         -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
cmake -DFUNCTION_ID=TEST_BUILD       -DTEST_TYPE=UT -DTARGET_ID=8           -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
cmake -DFUNCTION_ID=TEST_RUN         -DTEST_TYPE=UT -DTARGET_ID=8 -DTEST_ID=0 -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
```

Integration tests on all connected boards - the last entry of the boards list (`All connected boards`):
presets of all detected boards are only configured to list their test sets, the execution is done by
`CMake/IntegrationTesting/IntegrationTesting_AllBoards.cmake` (connected boards are detected again,
built and tested, `IT_LABEL` = selected test set; the boards of the IT agents too). Results are printed per
probe from `Build/<preset>/IntegrationTestResults_<sn>.xml` (`IntegrationTestResults_<host>_<sn>.xml` of an IT agent).

---

## Documentation

This option generates Doxygen documentation (HTML) of the project for selected MCU of the project
presets. Preset `<MCU>_Debug` is configured with `DOXYGEN_ENABLED=ON` into its own build folder
`Build/<MCU>_Doxygen` (the firmware build folders are not touched) and target `Doxygen` is built.
Every module registers its folder by `Doxygen_AddPath()` (condition `DOXYGEN_AVAILABLE`), the project
`README.md` is the main page. Output: `Build/<MCU>_Doxygen/Doxygen/html/index.html`.

Requirements (`ArtifactsConfig.txt` of the project):
- `doxygen;1.17.0;latest` - documentation generator (1.18.0 does not resolve references to static
  functions and variables)
- `graphviz;latest;latest` - optional, diagrams (include / call graphs) are generated if `dot` can be
  executed

Doxygen settings for C firmware are set by `CMake/Build.cmake` (static symbols extracted, compile
definitions and MCU predefined, GCC attributes ignored). Any `DOXYGEN_<TAG>` variable defined by the
project `CMakeLists.txt` before the platform is included overrides the default value.

Direct call (from `EmBi_Platform` folder):

```bash
cmake -DFUNCTION_ID=DOCS -DMCU_ID=8           -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
cmake -DFUNCTION_ID=DOCS -DMCU=STM32F411xE    -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
```

---

## Initialization
  
When selected, the script will display a submenu with various initialization options.

```
=====================================
0: Back to main menu
1: BSP module - Configuration
2: BSP module - Update version
3: Middleware module - Configuration
4: Middleware module - Update version
5: Documents module - Configuration
6: Module update (Updater)
7: Artifacts (artifacts handler)
8: STM32CubeIDE project initialization
9: VSCode project initialization
=====================================
Enter your selection (0-9):
```

The project structure (`ArtifactsConfig.txt`, `CMakeLists.txt`, `CMakePresets.json` and the `Application` layer) is
initialized at the beginning of *BSP module - Configuration* (`Prj_Handler.cmake`, `App_ModuleHandler.cmake`), before
the BSP itself is composed. Already existing files are kept.

---

### VSCode project initialization

Generates the VSCode configuration of the project (`Prj_Handler/Prj_VSCode_Handler.cmake`) into `.vscode/`.
The script lists MCUs of the project presets and asks for MCUs of the debug configurations (IDs separated by
comma, `0` = all MCUs). The initialization does not access any hardware and does not run probe-rs - the MCUs are
selected by the user. The MCUs come from `Bsp/Ral/RalPresets.json`; if the BSP
module is not configured yet, the option informs about it and offers a return to the menu.

After the MCU selection the script asks for the firmware name (without spaces and build type, empty = the current
name is kept). The name is written to `set(PROJECT_NAME ...)` of the root `CMakeLists.txt` as
`<name>_${CMAKE_BUILD_TYPE}` and the debug configurations and the flash task use the firmware
`<name>_<build type>.elf`.

```
.vscode/
├─ tasks.json                    - Build, clean rebuild, flash, unit tests, integration tests, board detection, Setup
├─ launch.json                   - probe-rs debugging (firmware, attach, integration test firmware, picked board of this machine or of an IT agent), unit tests (gdb)
├─ settings.json                 - CMake Tools with presets, IntelliSense, excludes (other settings are kept)
├─ c_cpp_properties.json         - IntelliSense configuration provided by CMake Tools
└─ extensions.json               - Recommended extensions (CMake Tools, C/C++, probe-rs Debugger, Serial Monitor)
```

Tasks (`Terminal > Run Task`, `Ctrl+Shift+B` build, `Run Test Task`) ask for MCU, build type, board and test set and
execute `Build_Handler.cmake` - the same flow as the menu options *Build* and *Tests*:

| Task | Description |
|------|-------------|
| `EmBi: Build` | Configuration and build of `<MCU>_<Debug/Release>` (default build task) |
| `EmBi: Clean rebuild` | Configuration without CMake cache (`--fresh`), build `--clean-first` |
| `EmBi: Build for board` | Build of a picked board (Debug / Release) in its build folder `Build/<MCU>_<type>_<board>` with its configuration (fixture, own defines) |
| `EmBi: Flash` | Build, flashing by probe-rs to the connected board with the MCU, reset |
| `EmBi: Unit tests` | Build of `<MCU>_UnitTest`, execution of a test set (empty = all), summary (default test task) |
| `EmBi: Integration tests` | Detection of boards (this machine and IT agents of `ItHosts.json`), build and execution on the picked physical board - local or on its IT agent - (or all connected boards), summary |
| `EmBi: Detect connected boards` | Detection of the boards of this machine and of all IT agents of `ItHosts.json` (`Build/IntegrationTestBoards.json`, read by the board pickers of the other tasks), printed without the numbered list of the menu (`FUNCTION_ID=DETECT_BOARDS`) |
| `EmBi: Setup` | This menu in the VSCode terminal |

Debug configurations of every selected MCU (debug adapter of the probe-rs extension, `probe-rs dap-server`):

- `EmBi: Debug <MCU>` - builds `<MCU>_Debug`, flashes and runs the firmware
- `EmBi: Attach <MCU>` - attaches to the running firmware without flashing
- `EmBi: Debug integration test <MCU>` - flashes an integration test firmware selected from the list (built by the
  task *Integration tests*)
- `EmBi: Debug unit test <MCU>` - host gdb (gcc artifact) debugging of a unit test executable (built by the task
  *Unit tests*)

Debug configurations of a picked board - a board of this machine or of an IT agent of `ItHosts.json` (see
`IntegrationTesting/README.md`, *Boards of IT agents*), picked from the connected boards (detected when the
configuration is started, one entry per physical board: `<board> - <name of the board>`, host):

- `EmBi: Debug on board` - builds the Debug firmware of the board (`Build/<MCU>_Debug_<board>`, its fixture and own defines), flashes and runs it
- `EmBi: Debug integration test on board` - flashes an integration test firmware of the MCU of the board selected
  from the list (built by the task *Integration tests*)

The configuration is the same for a local board and for a board of an IT agent (F5, breakpoints, registers, RTT):

1. The hidden `preLaunchTask` (`EmBi: Prepare debugging on board`, background task, `Prj_VSCode_ProbeRs.cmake`
   `DEBUG_SERVE`) builds the firmware and starts the debug server of the probe of the board - here, or on the IT
   agent over `ssh -tt -L <port>:127.0.0.1:<port of the agent>` (the host scripts are copied to `/tmp/embi-<random>` of
   the agent and removed after the session; the agent uses its probe-rs in the version of this machine).
2. The debug server locks the probe for the whole session (`IntegrationTesting_Lock.cmake`): a board used by another
   client (a job of the integration test pipeline, tests) is not debugged - the task ends with the holder of the board.
   A pipeline job waits for a board being debugged.
3. VS Code connects when the server prints `EmBi: debug server listening on port <port>`; the probe-rs extension
   sends the firmware and the SVD file to the server (`remoteServerMode`), the server needs no file of this machine.
4. The session ends the server (one session, `--single-session`), the SSH connection and the task; a broken SSH
   connection ends the server on the agent too (`-tt`), the lock is released by the operating system.

The probe of the picked board is given (`probe`), so two boards of one MCU are told apart. The ports are given by the
board (`127.0.0.1:30000-39999` of this machine without the excluded port ranges of Windows, `40000-49999` of the agent).
The Debug and IntegrationTest builds on Windows record the source paths with the drive letter in lower case
(`-fdebug-prefix-map`, `Build.cmake`) - VS Code sends the paths of breakpoints so and the debug server of a Linux agent
compares them case sensitively.

probe-rs configurations have RTT enabled - RTT channels of the firmware (SEGGER RTT control block) are shown in the
terminal of the debug session. Firmware output over ST-LINK VCP (USART) is read by the recommended Serial Monitor
extension.

The probe is not written to `launch.json` (it is selected by the debug adapter). `launch.json` contains no path of
probe-rs: the probe-rs configurations start the debug adapter through CMake (`"runtimeExecutable": "cmake"`,
`Prj_Handler/Prj_VSCode_ProbeRs.cmake`), which runs the probe-rs artifact of the artifacts cache with the arguments of
the extension (probe-rs of the system is not used). The artifact is downloaded by the artifacts handler by the
`preLaunchTask` of the configuration (`EmBi: Provide probe-rs`, a part of the hidden task `EmBi: Prepare <MCU>_Debug`
of the debug configuration), because the extension waits only 5 s for the debug adapter.

The generated files contain no static values of the project - the lists of MCUs, boards and test sets of the tasks and
the chip, the SVD file, the firmware files, the lists of tests and the gdb of the debug configurations are inputs resolved by CMake when
the task or the debug configuration is started (extension *Tasks Shell Input*, `augustocdias.tasks-shell-input`, which runs
`Prj_VSCode_Handler.cmake`). A new test, a new MCU or a changed firmware name is used without the initialization:

| Function (`-DFUNCTION_ID=`) | Used by | Output |
|-----------------------------|---------|--------|
| `PICK_MCU` | tasks | MCUs of the project presets |
| `PICK_BOARD` | tasks | connected boards of this machine and of the IT agents (detected now, one option per physical board, value = ID `<board>@<host>:<probe>`), all connected boards |
| `PICK_TEST_SET` (`-DTEST_TYPE=UT/IT`) | tasks | test sets = names of the tests registered in the project (the first option = all) |
| `DEBUG_CHIP` (`-DMCU=`) | debug | probe-rs chip: board chip of `ItBoards.json`, device of the MCU identification of `Bsp/Ral/RalPresets.json` or the MCU name (the first one probe-rs knows if the artifact is in the cache, otherwise the first defined) |
| `DEBUG_SVD` (`-DMCU=`) | debug | SVD file of the MCU (peripheral registers of the debugger, `coreConfigs[].svdFile`) from the Ral module `Svd` of the BSP (`Bsp/Ral/Svd/<Device>.svd`): the file `Bsp/Ral/Svd/Devices.csv` (`Device;Core;File;Pack`, generated by the importer from the pack descriptions of ST) assigns the file to a device, the device is the one of the MCU identification of `Bsp/Ral/RalPresets.json`, otherwise the first device whose name matches the MCU (`x` of the MCU name = any character). No file of the host is used. An MCU without an SVD file (BSP without the module `Svd`, a device ST delivers no SVD file for) prints the expected path with a warning, the debugger runs without the peripheral registers. The row of the core 0 is used (a multi core device, e.g. STM32H745, has a row per core, ordered by the access port) |
| `DEBUG_FIRMWARE` (`-DMCU=`) | debug | firmware file: build directory of the preset and the firmware name of the root `CMakeLists.txt` (the same file the flash task uses) |
| `DEBUG_TESTS` (`-DTEST_TYPE=UT/IT -DMCU=`) | debug | test executables of the MCU registered in the project (`Build/<MCU>_<UnitTest|IntegrationTest>`; unit tests need the build of the task *Unit tests*) |
| `DEBUG_GDB` (`-DMCU=`) | debug | host gdb of the artifact `gdb`, otherwise `gcc`, in the version configured for the unit test preset of the MCU; gdb of the system is not used |
| `PICK_DEBUG_BOARD` | debug | connected boards of this machine and of the IT agents (detected now): `<ID>\|<board> - <name>\|<host>`, ID `<board>@<host>:<probe>` |
| `DEBUG_BOARD_SERVER` (`-DTARGET=<ID>`) | debug | `127.0.0.1:<port>` of the debug server of the picked board; writes `Build/DebugTarget.cmake` (the board for the `preLaunchTask`) |
| `DEBUG_BOARD_PROBE`, `_CHIP`, `_SVD`, `_FIRMWARE`, `_TESTS` (`-DTARGET=<ID>`) | debug | probe of the picked board, chip / SVD file / Debug firmware of the board / integration test firmwares of its MCU (as `DEBUG_CHIP`, `DEBUG_SVD`, `DEBUG_FIRMWARE`, `DEBUG_TESTS`) |

The generated configuration uses VSCode extensions (CMake Tools, C/C++, probe-rs Debugger, Serial Monitor and
*Tasks Shell Input*, without which the tasks and debug configurations with inputs do not start - `shellCommand.execute not
found`). The initialization checks the extension folders of VSCode (`~/.vscode/extensions`, Insiders, VSCodium, Cursor, remote
server; extensions in `.obsolete` count as uninstalled) and lists the missing ones; the Setup menu then offers their
installation by the `code` command (`EXTENSIONS_CHECK` prints the missing extensions, `EXTENSIONS_INSTALL` installs
them - nothing is installed without the answer of the user).

Only the build types (`Debug`, `Release`) are a fixed list. The system requirements are CMake and git, every other tool
(probe-rs, gdb, compilers) is an artifact of the artifacts cache **in the version configured for the preset**
(`ARTIFACTS_HANDLER_REQ_LIST` of the preset of the MCU or `ArtifactsConfig.txt`, see `ArtifactsHandler/README.md`,
*ArtifactsResolver*): probe-rs by the integration test preset of the MCU, gdb by the unit test preset of the MCU. The
newest version found in the cache is never used instead of the configured one.

Generated files start with the comment `// Generated by EmBi_Platform Setup ...`. Existing files without it are kept
as `<file>.bak`. Repeat the initialization after change of the MCUs of the debug configurations.

---

### Initialize folder structure

This option creates the basic folder structure for the project, including directories for source files, headers, and tests.

#### Folder structure created:

```
ProjectRoot/
├─ CMakeLists.txt                - Project root CMake file 
├─ ArtifactsConfig.txt           - Artifacts configuration file 
├─ Application/                  - Project application part
│  ├─ AppCom/                      - Application communication modules
│  ├─ AppComp/                     - Application components (Low level logic)
│  ├─ AppFun/                      - Application functionalities (High level logic)
│  ├─ AppCore/                     - Application core (Top level logic)
│  ├─ AppMain/                     - Application main file
│  └─ App.cmake                    - Application CMake file
├─ Middlewares/                  - Project middlewares part
├─ BSP/                          - Board Support Package
└─ STM_Template/                 - CMake build system submodule 
```

--- 

### Initialize BSP module

This option initializes the Board Support Package (BSP) module. Script will ask for target microcontroller and set up necessary files and configurations.

#### BSP Folder structure created:

```
BSP/                          - Board Support Package
├─ Hal/                         - Hardware Abstraction Layer
├─ Mcal/                        - Microcontroller Abstraction Layer
├─ Ral/                         - Register Abstraction Layer 
├─ Linker/                      - Linker script
├─ Startup/                     - Startup files
├─ Docs/                        - BSP documentation
└─ Bsp.cmake                    - BSP CMake file
```

---

### Artifacts (artifacts handler)

The build tools of the project (ninja, gcc-arm-none-eabi, doxygen, probe-rs, ...) are artifacts. The artifacts handler
(`CMake/ArtifactsHandler`, see its README) installs them into the artifacts cache folder, normally as a part of the project
configuration. This option lets you use the handler directly:

```
=====================================
0: Back to configuration menu
1: Install artifacts of ArtifactsConfig.txt
2: Install one artifact
3: Show artifacts (configuration, cache folder, installed versions)
=====================================
Enter your selection (0-3):
```

- **Install artifacts of ArtifactsConfig.txt** - installs (or updates to the latest version) the artifacts listed in `ArtifactsConfig.txt`
  of the project. *Offline mode* checks only the local cache and downloads nothing (it ends with an error if an artifact is missing).
- **Install one artifact** - asks for the artifact name, the Bin version and the Core version (`X.Y.Z`, empty = `latest`). The artifact does
  not have to be listed in `ArtifactsConfig.txt`.
- **Show artifacts** - prints the configuration file, the root repository, the cache folder with the source it comes from (CMake parameter,
  environment variable `ARTIFACTS_HANDLER_CACHE_PATH`, `ArtifactsConfig.txt` for the host system or the default folder of the handler)
  and the required artifacts with the Bin / Core versions installed in the cache.

The project needs `ArtifactsConfig.txt` in its root folder (created by *BSP module - Configuration*). The actions are in
`Artifacts_Handler/Artifacts_Menu.cmake` and can be started without the menu:

```bash
cmake -DFUNCTION_ID="SHOW" -P CMake/HelperTools/Artifacts_Handler/Artifacts_Menu.cmake
cmake -DFUNCTION_ID="INSTALL" -DOFFLINE=ON -P CMake/HelperTools/Artifacts_Handler/Artifacts_Menu.cmake
cmake -DFUNCTION_ID="INSTALL_ONE" -DARTIFACT_NAME=ninja -DARTIFACT_BIN_VERSION=1.12.0 -DARTIFACT_CORE_VERSION=latest -P CMake/HelperTools/Artifacts_Handler/Artifacts_Menu.cmake
```

---

## ⚙️ Requirements

Following tools must be installed and available in your system's PATH:
- CMake
- Git

All other dependencies are managed by the CMake scripts themselves.

---

## 📝 Notes

- Each menu item calls a specific **CMake script** located in the `Scripts/` directory.
- The script ensures consistent execution flow, so you don’t have to manually call the CMake commands.

---

## License

This project is licensed under the [CC BY-NC](../../LICENSE.md) license.  
You are free to use, modify, and share for **non-commercial purposes** with attribution.

---