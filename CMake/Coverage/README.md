# 📊 Code coverage of the tests

Coverage of the **unit tests** (host) and of the **integration tests** (firmware on the board) with the
compiler instrumentation **gcov** and the report tool **gcovr**. Both kinds of tests produce the same
reports (HTML, Cobertura XML, JSON tracefile, JSON summary, text) with the same scripts, so the reports
can be merged and evaluated by the pipelines (reports in the artifacts of the runs, statistics of the pipeline
`TestStats`).

| | Unit tests | Integration tests |
|---|---|---|
| Code under test | `UUT_SOURCES` of the test set | libraries `COVERAGE_LIBS` of the test set (default `<NAME>_Lib`) |
| Compiled by | host compiler (`gcc` artifact) | ARM toolchain (`gcc-arm-none-eabi` artifact) |
| Executed | on the host | on the board |
| Switch | `-DUNIT_TEST_COVERAGE=ON` | `-DINTEGRATION_TEST_COVERAGE=ON` |
| Targets | `UnitTest_Coverage`, `UnitTest_CoverageSummary`, `UnitTest_CoverageReset` | `IntegrationTest_Coverage`, `IntegrationTest_CoverageSummary`, `IntegrationTest_CoverageReset`, `IntegrationTest_CoverageMerge` |

The only system requirements stay `cmake` and `git`: **gcovr** is the artifact `gcovr` (a standalone
application for Windows and Linux - no Python, no package, nothing but the C library of the system), **gcov**
and **gcov-tool** are taken from the compiler artifact. Nothing is searched in `PATH`.

---

## 🚀 Usage

### Setup menu / VSCode (`Build_Handler.cmake`)

`Setup` → *Tests* → *Unit tests*: the code coverage is always created and printed at the end of the run. For the integration
tests Setup asks *Code coverage of the tests (y/N)* - the firmware with the coverage is bigger (it does not fit into the flash
of small devices) and slower, so it is off unless `y` is answered. With the coverage on the
tests are built with the instrumentation, the counters of earlier runs are deleted, the selected test set (or
all of them) is executed, the report is created and the **table of the coverage by modules** is printed:

```
Unit tests coverage - TestPrj_UnitTest
----------------------------------------------------------------------------------
Folder                         Lines              Functions               Branches
----------------------------------------------------------------------------------
Bsp/Mcal/Gpio        223/230   96.9%          22/22  100.0%        126/156   80.7%
Bsp/Mcal/Nvic        177/200   88.5%          24/34   70.5%          57/62   91.9%
----------------------------------------------------------------------------------
TOTAL                400/430   93.0%          46/56   82.1%        183/218   83.9%
----------------------------------------------------------------------------------
Coverage report: Build/STM32F722xE_UnitTest/Coverage/index.html
```

The table of one test set shows only the folders named like the test set; the report (HTML, XML) always contains
everything built. *Tests* → *Coverage of the last unit / integration tests* prints the table of the last report again.
Without the menu:

```bash
cmake -DFUNCTION_ID=TEST -DTEST_TYPE=UT -DTARGET=STM32F722xE -DTEST_SET=Gpio -DTEST_COVERAGE=ON -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
cmake -DFUNCTION_ID=TEST_COVERAGE -DTEST_TYPE=UT -DTARGET=STM32F722xE -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
```

The coverage is not available for the integration tests on all connected boards (select one board).

### CMake targets

```bash
cmake --preset STM32F722xE_UnitTest -DUNIT_TEST_COVERAGE=ON
cmake --build --preset STM32F722xE_UnitTest
ctest --preset STM32F722xE_UnitTest -j 8           # tests of different executables run in parallel
```

With the coverage `ctest` itself creates the report and prints the table of the coverage by modules under the result of the
tests (`CTestCustom.cmake` of the build folder runs the target `UnitTest_Coverage` as `CTEST_CUSTOM_POST_TEST`; no test case is
added, so the numbers of the tests do not change). It is done also when a test fails; a report that cannot be created (no
coverage data, a coverage below `..._COVERAGE_MIN_LINES`) makes ctest fail. The option `UNIT_TEST_COVERAGE_CTEST_REPORT` /
`INTEGRATION_TEST_COVERAGE_CTEST_REPORT` (default `ON`) switches it off; the Setup menu, the standalone module tests and the
pipelines create the report themselves and switch it off. The target can be run alone as well:

```bash
cmake --build Build/STM32F722xE_UnitTest --target UnitTest_Coverage
```

| Target | Description |
|---|---|
| `<Prefix>_Coverage` | Report from the counters of the executed tests: `<build>/Coverage/` (`index.html`, `Cobertura.xml`, `coverage.json`, `coverage-summary.json`, `coverage.txt`) + the table. Fails when there is no coverage data (the tests were not executed or no source is instrumented). |
| `<Prefix>_CoverageSummary` | The table of the last report (no gcovr needed, only CMake). |
| `<Prefix>_CoverageReset` | Deletes the counters (`*.gcda`) - they sum up all runs since the last reset. |
| `IntegrationTest_CoverageMerge` | Converts the stored coverage data of the firmwares (`IT_<Name>.cov.ihex`) to `*.gcda` again. |

Parameters (CMake cache): `UNIT_TEST_COVERAGE_ROOT` / `INTEGRATION_TEST_COVERAGE_ROOT` (root of the sources, paths
of the report are relative to it; default the source folder of the project), `..._COVERAGE_MIN_LINES` (the
report fails below this line coverage, default 0 = not checked), `..._COVERAGE_CTEST_REPORT` (ctest prints the table after the
tests, default `ON`), `INTEGRATION_TEST_COVERAGE_SIZE` (buffer of
the coverage data in RAM of the firmware [B], default 49152 - the data are about 1.4 times the counters). The environment variable `COV_FILTER` (regular
expression of the path) restricts the printed table.

### Table from the command line

The table is printed by CMake alone from `coverage-summary.json`:

```bash
cmake -DCOV_SUMMARY_FILE=Build/STM32F722xE_UnitTest/Coverage/coverage-summary.json -DCOV_GROUP=file -DCOV_FILTER=Gpio -P CMake/Coverage/Coverage_Summary.cmake
```

`COV_GROUP=dir` (default) is one row per folder (a module), `file` one row per source file; `COV_MIN_LINES=<percent>`
makes the script fail below it.

---

## ⚙️ How it works

### Common part (`Coverage.cmake`, scripts)

| File | Description |
|---|---|
| `Coverage.cmake` | Included by `UnitTesting.cmake` / `IntegrationTesting.cmake`: `Coverage_Provide_Gcovr()` (parameter `GCOVR_EXECUTABLE`, environment variable or the artifact `gcovr`; the system `PATH` only in the explicit `SYSTEM` mode of the standalone unit tests), `Coverage_Find_Gcov()` (gcov **next to the compiler** - `gcc` → `gcov`, `arm-none-eabi-gcc` → `arm-none-eabi-gcov`, Clang → `llvm-cov gcov`; a gcov of another compiler gives wrong data), `Coverage_Add_Targets()`. |
| `Coverage_Report.cmake` | Script of the targets: runs gcovr (all formats in one run), merges tracefiles (`COV_TRACEFILES`), prints the table, checks the minimum. |
| `Coverage_Summary.cmake` | The table of the coverage (JSON summary → table by folders / files). |
| `Coverage_Reset.cmake` | Deletes `*.gcda`. |
| `Coverage_SelfTest.cmake`, `SelfTest/` | Self-test of the whole chain on the host (see below). |

### Unit tests

The code under test (`UUT_SOURCES`) is compiled with `--coverage`, every `Ut_...` function is a separate CTest
test (a process). The counters of the processes of one executable are written to the same `*.gcda` files, which
is not safe against two processes, so the tests of one executable never run in parallel (`RESOURCE_LOCK`); the tests
of different executables do (`ctest -j`). The tests of an MCU cover the `#if` branches of the MCU: the coverage of
a family is the **union of its MCUs** - the tracefiles (`coverage.json`) of the MCUs are merged by
`Coverage_Report.cmake` (`-DCOV_TRACEFILES="a.json;b.json"`, the pipeline `UnitTest` does it after the last MCU of the
family). Excluded from the report: `Tests`, generated mocks and `COVERAGE_EXCLUDE` of the test sets (the target library).

Standalone module tests (`UnitTesting/Standalone`) have the parameter `COVERAGE=ON` (root of the report = the common
parent folder of the modules):

```bash
cmake -DMODULE_PATH=<module> -DCOVERAGE=ON -P EmBi_Platform/CMake/UnitTesting/Standalone/RunModuleTests.cmake
```

### Integration tests

The firmware runs on the MCU, so the counters are in its RAM and have to get to the host:

1. **Instrumentation.** The libraries under test are compiled with `--coverage -fprofile-info-section -fdata-sections`
   (`COVERAGE_LIBS` of the test set, default `<NAME>_Lib`; a library shared by more firmwares is instrumented once).
   `-fprofile-info-section` needs neither constructors nor a file system: every object registers its gcov
   information in the linker section `.gcov_info`.
2. **Counters survive the resets.** Every test case runs after a reset of the MCU, which clears `.bss`. The
   linker script `ItCore/IntegrationTesting_GcovCounters.ld` (augmenting script `INSERT BEFORE .bss`, added by
   `-Wl,-T`) collects the counters (`.bss.__gcov0.*`) in the section `.gcov_counters`, which the startup code does not
   initialize - like the section `.noinit` of the result mailbox. The counters sum up all test cases; they are cleared when
   a new test session starts. `ItCore/IntegrationTesting_GcovInfo.ld` places the `.gcov_info` pointers in FLASH.
   (Requirement: memory regions `FLASH` and `RAM` of the linker script - `Bsp/Linker`.)
3. **Dump.** After the last test case `IntegrationTesting_Coverage_Dump()` serializes the gcov information by
   libgcov (`__gcov_info_to_gcda`) into the buffer `integrationTesting_Coverage` (RAM, `.noinit`).
4. **Host.** `IntegrationTesting_Run.cmake` reads the buffer through probe-rs and stores it as Intel HEX text
   (`IT_<Name>.cov.ihex`; CMake cannot write binary files and the board hosts have nothing but CMake and probe-rs).
   `IntegrationTesting_Coverage.cmake` converts it: `objcopy -I ihex -O binary` → `gcov-tool merge-stream` writes the
   `*.gcda` files (the counters of more firmwares and boards are added up).
5. **Report.** The same `Coverage_Report.cmake` with `COV_RELATIVE=ON`. The objects are compiled with
   `-fprofile-prefix-map`, so the `.gcno` / `.gcda` files name the sources relative to the project and the build folder:
   the data can be evaluated in **another folder and on another machine** than the one that built the firmware (the
   coverage stage of the pipeline, `EmBi_Tester/Scripts/HwTest/ItCoverage.cmake`); `GCOV_PREFIX` / `GCOV_PREFIX_STRIP` of
   libgcov relocate the `.gcda` files.

Cost (STM32F722, `-O0`, module Gpio / Tim): FLASH 29 → 65 kB / 61 → 138 kB, RAM 7 → 42 kB / 7 → 66 kB (libgcov, the counters and the
`gcov_info` structures of the instrumented objects, the buffer: 16 kB when measured, 48 kB now). Devices with a small memory may not fit the
instrumented firmware. The counters are 64-bit and not atomic: an interrupt that preempts the update of a counter can
lose one count (the coverage only needs "executed or not").

---

## 🧪 Self-test

`Coverage_SelfTest.cmake` executes the tests of the module `SelfTest/Calc` (a tiny module with a known coverage) with the
coverage and checks: the report files, the numbers (11 of 14 lines, 2 of 3 functions), the table, the minimum of the
coverage, the merge of tracefiles, the reset and the report without data. It checks gcovr, gcov, the scripts and the paths on
the platform of the host:

```bash
cmake -DBUILD_DIR=Build_CoverageSelfTest -P EmBi_Platform/CMake/Coverage/Coverage_SelfTest.cmake
```

Parameters of `RunModuleTests.cmake` (`TOOLS`, `GENERATOR`, `CMAKE_ARGS`) are passed on.

---

## 🔁 Pipelines and statistics

The pipelines `UnitTest` and `IntegrationTest` (project Maintenance, repository EmBi_Tester) have the parameter *Code coverage*:

- **UnitTest**: `CompatibilityTest.sh --coverage` - a report of every MCU and one merged report of the family
  (`coverage/<Family>/`) in the artifact `UtResults_<n>` of the run (HTML, Cobertura XML, JSON).
- **IntegrationTest**: the firmware is built with the coverage, the board hosts store the data of the firmwares, the stage
  *Coverage* evaluates the data of all boards (ARM toolchain and gcovr from the artifacts) and creates the report of every board and
  the merged report of the family.
- Both publish the small artifact `CoverageStats_<n>` (`coverage-stats.json`: totals, modules, MCUs / boards); the pipeline `TestStats`
  keeps the history of the coverage and writes it to `stats.json` and to its wiki.

---

## ⚠️ Notes

- Run the coverage with the optimization of the project: the unit tests are `-O0`, the integration tests `-O0` by default
  (`INTEGRATION_TEST_OPTIMIZATION`); an optimizing compiler merges branches and the report differs from the source.
- The report of a build folder shows all runs since the last reset (`..._CoverageReset`); the menu and the pipelines build in a clean state.
- macOS is not supported: there is no macOS package of the artifact `gcovr`. For a Clang compiler the report uses `llvm-cov gcov` found next to the compiler (not tested).
