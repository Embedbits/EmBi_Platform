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
```

---

## Tests

This option builds and executes unit tests (host) or integration tests (board):

1. Test type - `Unit tests` or `Integration tests`.
2. Target - MCU of the project presets (unit tests, preset `<MCU>_UnitTest`) or connected board
   (integration tests - boards are detected before the list is printed, MCU of every probe identified
   by `Bsp/Ral/RalPresets.json`, optional `IntegrationTestBoards.json` of the project as override,
   stored in `Build/IntegrationTestBoards.json`; preset of the board configured with
   `INTEGRATION_TEST_BOARD=<board>`, see `CMake/IntegrationTesting/README.md`) or all connected boards.
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
built and tested, `IT_LABEL` = selected test set). Results are printed per probe from
`Build/<preset>/IntegrationTestResults_<sn>.xml`.

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
1: Project structure initialization
2: STM32CubeIDE project initialization
3: VSCode project initialization
4: BSP module - Configuration
5: BSP module - Update version
6: Middleware module - Configuration
7: Middleware module - Update version
8: Documents module - Configuration
9: Module update (Updater)
=====================================
Enter your selection (0-9):
```

---

### VSCode project initialization

Generates the VSCode configuration of the project (`Prj_Handler/Prj_VSCode_Handler.cmake`) into `.vscode/`.
The script lists MCUs of the project presets and asks for MCUs of the debug configurations (IDs separated by
comma, `0` = all MCUs, empty = MCUs of the connected boards).

```
.vscode/
├─ tasks.json                    - Build, clean rebuild, flash, unit tests, integration tests, board detection, Setup
├─ launch.json                   - probe-rs debugging (firmware, attach, integration test firmware), unit tests (gdb)
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
| `EmBi: Flash` | Build, flashing by probe-rs to the connected board with the MCU, reset |
| `EmBi: Unit tests` | Build of `<MCU>_UnitTest`, execution of a test set (empty = all), summary (default test task) |
| `EmBi: Integration tests` | Detection of boards, build and execution on the board (or all connected boards), summary |
| `EmBi: Detect connected boards` | Boards connected to debug probes (`Build/IntegrationTestBoards.json`) |
| `EmBi: Setup` | This menu in the VSCode terminal |

Debug configurations of every selected MCU (debug adapter of the probe-rs extension, `probe-rs dap-server`):

- `EmBi: Debug <MCU>` - builds `<MCU>_Debug`, flashes and runs the firmware
- `EmBi: Attach <MCU>` - attaches to the running firmware without flashing
- `EmBi: Debug integration test <MCU>` - flashes an integration test firmware selected from the list (built by the
  task *Integration tests*)
- `EmBi: Debug unit test` - host gdb (gcc artifact) debugging of a unit test executable (built by the task
  *Unit tests*)

probe-rs configurations have RTT enabled - RTT channels of the firmware (SEGGER RTT control block) are shown in the
terminal of the debug session. Firmware output over ST-LINK VCP (USART) is read by the recommended Serial Monitor
extension.

The probe-rs chip of the MCU is the board chip of `IntegrationTestBoards.json` (`INTEGRATION_TEST_PROBE_RS_CHIP`),
the device of the MCU identification of `Bsp/Ral/RalPresets.json` or the MCU name - the first one probe-rs knows.
The probe is taken from the detection of connected boards and the SVD file (peripheral registers view) from the
project (`Bsp/`, `EmBi_Platform/Docs/`) or STM32Cube packs of the STM32 VSCode extension, if found. If the SVD file is
missing and the STM32Cube extension is installed, the device family pack of the MCU (e.g.
`STMicroelectronics.stm32f4xx_dfp`) is installed by `cube pack install`.

Generated files start with the comment `// Generated by EmBi_Platform Setup ...`. Existing files without it are kept
as `<file>.bak`. Repeat the initialization after change of MCUs, boards, test sets, probe-rs version or when the
boards are connected to other probes.

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