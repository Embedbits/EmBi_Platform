# 🧪 Unit Testing

Host based unit tests of EmBi modules with [Unity](https://github.com/ThrowTheSwitch/Unity),
[CMock](https://github.com/ThrowTheSwitch/CMock) and optional target emulation (RegMem, CmsisHost).

The code under test (eg. `Gpio.c`) is compiled **unchanged** by host compiler, dependencies on
other modules are replaced by CMock mocks.

**The framework is independent of the target** (MCU, BSP, MCAL, CPU architecture) - it only builds
the tests, runs them and evaluates the results. **Every test set is independent** and lists
everything it needs in its `CMakeLists.txt`: code under test, mocks, target emulation (`ut_RegMem`,
`ut_CmsisHost`), target libraries compiled for host (`HOST_LIBS`, eg. `Ral_Lib`) and coverage
excludes. Test sets are created from the template by Setup scripts (`HelperTools/Test_Handler`).

---

## ⚙️ How it works

| Part | Description |
|---|---|
| `UnitTesting.cmake` | Included by `Build.cmake` for `CMAKE_BUILD_TYPE=UnitTest`. Builds `unity`, `cmock`, `ut_Common` and optional `ut_RegMem`, `ut_CmsisHost` libraries, provides `UnitTesting_AddPath()`, `UnitTesting_Generate()` and `UnitTesting_Add_Test()`. |
| `UnitTesting.yml` | CMock and Unity runner generator configuration (strict call ordering, plugins). |
| `UtCommon/` (`ut_Common`) | Common helpers (`UT_KNOWN_DEFECT`), linked to every test. |
| `RegMem/` (`ut_RegMem`, optional) | Maps host RAM at `0x40000000..0x5FFFFFFF` (peripherals, incl. secure alias) and `0xE0000000..0xE00FFFFF` (SCB, NVIC, SysTick) before `main()`. `RCC`, `GPIOA`, `SCB`, ... point to valid memory without any change of the code. |
| `CmsisHost/` (`ut_CmsisHost`, optional) | CMSIS core intrinsics on host. `${UNIT_TESTING_CMSIS_HOST_HEADER}` in `FORCE_INCLUDES` replaces `cmsis_gcc.h` (ARM assembler). |
| `ArtifactsCore/` | Drafts of Core handlers of artifacts `unity`, `cmock`, `ruby` (see [Artifacts](#-artifacts)). |

Build flow (root `CMakeLists.txt` -> `Build.cmake`, `CMAKE_BUILD_TYPE=UnitTest`):
1. Preset `UnitTest` (`CMake/Presets/PlatformPresets.json`) replaces the artifacts list of the
   project `ArtifactsConfig.txt` by host tools (`ARTIFACTS_HANDLER_REQ_LIST`), no ARM toolchain
   is loaded. Cache path and repository URL are taken from the project `ArtifactsConfig.txt`.
2. `Build.cmake` includes `UnitTesting.cmake` (sets `UNIT_TESTING_AVAILABLE=ON`), then processes
   `Bsp.cmake` (only if `TARGET_MCU` is defined), `Middlewares.cmake` and `App.cmake` exactly as
   in MCU build.
3. Every module registers its tests in its own `CMakeLists.txt` - same principle as Doxygen:
   ```cmake
   #========================= Unit tests configuration ===========================#
   if(UNIT_TESTING_AVAILABLE STREQUAL "ON")
       UnitTesting_AddPath("${CMAKE_CURRENT_SOURCE_DIR}/Tests/UnitTests")
   endif()
   ```
   Modules without this block have no unit tests in the build.
4. `UnitTesting_Generate()` (end of `UnitTest` branch, like `Doxygen_Generate()`) excludes all
   module libraries from `all` target (they are not compiled for host) and adds every registered
   `Tests/UnitTests/CMakeLists.txt`.
5. For each test: mocks are generated (`cmock.rb`), test runner is generated
   (`generate_test_runner.rb`), executable `UT_<Name>` is built with `LINK_LIBS` and `HOST_LIBS`
   of the test set (`HOST_LIBS` are compiled with host options and `FORCE_INCLUDES`).
   `UnitTest_Coverage` (option `UNIT_TEST_COVERAGE`) excludes `Tests`, `Mocks` and `COVERAGE_EXCLUDE`
   of all test sets.
6. Every `void Ut_...( void )` function is registered as separate CTest test `<Name>.<function>`.
   Test passes only if exactly one Unity test was executed without failure.

---

## 🚀 Usage

```bash
cmake --preset STM32H563xI_UnitTest
cmake --build --preset STM32H563xI_UnitTest
ctest --preset STM32H563xI_UnitTest          # JUnit: Build/<preset>/UnitTestResults.xml
```

Without artifacts (eg. Linux with system `gcc` and `ruby`):

```bash
cmake -S . -B build/ut -DCMAKE_BUILD_TYPE=UnitTest -DTARGET_MCU=STM32H563ZITx \
      -DARTIFACTS_HANDLER_REQ_LIST="ninja;1.12.0;latest" \
      -DUNITY_ROOT=<Unity> -DCMOCK_ROOT=<CMock incl. vendor/unity> -DRUBY_EXECUTABLE=<ruby>
cmake --build build/ut && ctest --test-dir build/ut
```

Useful options:
- `ctest -L Gpio` - run only tests of one module, `ctest -R Gpio.Ut_Gpio_Init` - one test.
- `build/.../UT_Gpio -v` - run test executable directly (verbose Unity output).
- `-DUNIT_TEST_COVERAGE=ON` + `cmake --build ... --target UnitTest_Coverage` - gcov/gcovr report
  (HTML + Cobertura XML for Azure Pipelines).

Tests shall be executed for every supported MCU variant (different `#if` branches in
modules and LUTs) - one preset per variant.

---

## 📦 Standalone module testing

Unit tests of one module can be executed without any project - only EmBi platform and the
module repository are needed (module CI, quick local check):

```bash
git clone <EmBi_Platform repository> EmBi_Platform      # --recurse-submodules for TOOLS=ARTIFACTS
git clone <module repository> ModBus
cmake -DMODULE_PATH=ModBus -P EmBi_Platform/CMake/UnitTesting/Standalone/RunModuleTests.cmake
```

`RunModuleTests.cmake` configures `Standalone/CMakeLists.txt`, builds the tests and runs CTest
(JUnit `Build_UnitTest/UnitTestResults.xml`). It fails if any test fails or the module registers
no test.

| Parameter    | Default            | Description |
|---|---|---|
| `MODULE_PATH` | -                 | Tested module folder. List (`A;B`) - dependencies first, tested module last. |
| `TOOLS`      | `ARTIFACTS`        | `ARTIFACTS` - host tools by ArtifactsHandler (`Standalone/Artifacts/<Win\|Unix>/ArtifactsConfig.txt`). `SYSTEM` - gcc / ruby from PATH, Unity / CMock from `UNITY_ROOT` / `CMOCK_ROOT` or downloaded from GitHub (pinned `v2.7.0`). |
| `BUILD_DIR`  | `Build_UnitTest`   | Build folder. |
| `GENERATOR`  | Ninja if available | CMake generator. |
| `CMAKE_ARGS` | -                  | Additional configuration arguments, eg. `-DRUBY_EXECUTABLE=...;-DUNIT_TEST_COVERAGE=ON`. |

Requirements on the module:
- `CMakeLists.txt` in module root registers tests (`UnitTesting_AddPath`, see above) and can be
  processed without project (no dependency on BSP / other modules targets).
- Modules depending on MCU (RAL / LL, `TARGET_MCU`, MCAL) are not supported standalone yet - they
  are tested in project `UnitTest` build.

CI (Azure Pipelines) - module pipeline uses steps template of the platform:

```yaml
resources:
  repositories:
    - repository: EmBi_Platform
      type: git
      name: EmBi_Platform/EmBi_Platform
      ref: refs/heads/main

pool:
  vmImage: 'ubuntu-latest'

steps:
  - template: CMake/UnitTesting/Standalone/azure-pipelines-unittest.yml@EmBi_Platform
    parameters:
      moduleName: 'ModBus'
```

The pipeline of the module needs read permission to `EmBi_Platform` project repository
(Project settings -> Repositories -> Security, build service account).

---

## ✍️ Writing tests

Module layout:
```
Bsp/Mcal/Gpio/
├── CMakeLists.txt              # Gpio_Lib + UnitTesting_AddPath(.../Tests/UnitTests)
├── Gpio.c ...
└── Tests/
    ├── UnitTests/              # host tests (this document)
    │   ├── CMakeLists.txt
    │   └── Test_Gpio.c
    ├── IntegrationTests/       # tests on Nucleo (../IntegrationTesting/README.md)
    └── ImplementationTests/    # planned
```

`Tests/UnitTests/CMakeLists.txt`:
```cmake
UnitTesting_Add_Test(
    NAME            Gpio
    TEST_SOURCE     Test_Gpio.c
    UUT_SOURCES     ${GPIO_DIR}/Gpio.c              # code under test (-Wall -Wextra)
    MOCK_HEADERS    ${MCAL_DIR}/Rcc/Rcc_Port.h      # -> MockRcc_Port.h
    INCLUDE_DIRS    ${GPIO_DIR} ${MCAL_DIR}/Rcc
    LINK_LIBS       ut_RegMem                       # registers in host memory
                    ut_CmsisHost                    # CMSIS core intrinsics on host
    FORCE_INCLUDES  ${UNIT_TESTING_CMSIS_HOST_HEADER}
    HOST_LIBS       Ral_Lib                         # ST LL compiled for host
    COVERAGE_EXCLUDE ".*/Ral/.*"
)
```

Module without target dependency (eg. middleware) needs none of `ut_RegMem`, `ut_CmsisHost`,
`FORCE_INCLUDES`, `HOST_LIBS`.

Test file:
```c
#include "unity.h"
#include "RegMem.h"
#include "Gpio_Port.h"
#include "MockRcc_Port.h"

void setUp( void )
{
    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Reset() );   /* all registers = 0 */
}

void tearDown( void ) { }

void Ut_Gpio_Set_PinMode_Output_WritesModer( void )
{
    TEST_ASSERT_EQUAL( GPIO_REQUEST_OK, Gpio_Set_PinMode( GPIO_PORT_A, GPIO_PIN_ID_5, GPIO_PIN_MODE_OUTPUT ) );
    TEST_ASSERT_EQUAL_HEX32( GPIO_MODER_MODE5_0, GPIOA->MODER );
}
```

Rules:
- Only functions of the other modules are mocked (`<Mod>_Port.h`), never LL - LL runs for real on
  emulated registers (MCAL layering: module uses only its own LL).
- Test function names: `test_<Function>_<Condition>_<ExpectedResult>`. Helper functions must not
  start with `test` (they would be taken as tests).
- Registers are plain memory. HW behavior (ready flags, `BSRR` -> `ODR`, write-1-to-clear) is not
  emulated - preset the state the module waits for (eg. `RCC->CR |= RCC_CR_HSERDY`), or leave it
  unset to test the timeout branch.
- Registers start at 0 after `RegMem_Reset()`, not at HW reset values. Preset reset value if the
  module depends on it.

---

## 🧩 Artifacts

| Artifact | Bin content | Releases | Status |
|---|---|---|---|
| `gcc` | Win: MinGW-w64 (`mingw64/bin/gcc.exe`), Unix: xPack GCC (`gcc/bin/gcc`) | Win, Unix | exists |
| `ruby` | Portable Ruby (`bin/ruby[.exe]`) - Win: RubyInstaller without devkit, Unix / DarwinARM: jdx/ruby or Homebrew portable-ruby | Win, Unix, DarwinARM | exists |
| `unity` | Unity repository (`src/`, `auto/`) | Win, Unix, DarwinARM (same zip) | new - `ArtifactsCore/unity` |
| `cmock` | CMock repository **incl. submodules** (`vendor/unity` is required by `cmock.rb`) | Win, Unix, DarwinARM (same zip) | new - `ArtifactsCore/cmock` |

Publication of new artifact (same structure as existing ones):
1. Create repository `Artifacts/<name>` with branches `main` (README), `Core`, `Bin`.
2. `Core` branch: content of `ArtifactsCore/<name>/` + tag `Core/1.0.0`.
3. `Bin` branch: `<name>-<X.Y.Z>-<OS>.zip` (+ `.hash`), tag `Bin/<X.Y.Z>-<OS>` per OS.
4. Add submodule to `Artifacts` root repository.
5. Remove `ArtifactsCore/` from this folder.

---

## 🔭 Next steps

- Integration tests on Nucleo boards - see [IntegrationTesting](../IntegrationTesting/README.md)
  (Unity on target, results in RAM mailbox read over SWD, CTest + JUnit).
- Renode simulation of the same integration firmware (STM32H5 platform description has to be
  created, RCC/PWR need Python peripheral models).
