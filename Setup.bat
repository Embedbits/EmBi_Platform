@echo off
cd /d %~dp0
setlocal enabledelayedexpansion


:MENU
cls
echo =====================================
echo 0: Exit
echo 1. Add module
echo 2: Add module component
echo 3: Add module CMake file
echo 4: Add tests to existing module
echo 5: Configuration
echo 6: Build
echo 7: Tests
echo 8: Documentation
echo =====================================
set /p choice=Enter your selection (0-8):

if "%choice%"=="0" goto END
if "%choice%"=="1" goto RUN_INIT_MODULE
if "%choice%"=="2" goto RUN_ADD_COMPONENT
if "%choice%"=="3" goto RUN_INIT_MODULE_CMAKE
if "%choice%"=="4" goto RUN_INIT_TESTS
if "%choice%"=="5" goto INITIALIZATION
if "%choice%"=="6" goto RUN_BUILD
if "%choice%"=="7" goto RUN_TESTS
if "%choice%"=="8" goto RUN_DOCS

echo Incorrect selection. Try again.
pause
goto MENU


:RUN_INIT_MODULE
cls
set /p MODULE_NAME=Enter your module name:
set /p MODULE_PATH=Enter path to your module (relative to project root):

cmake -DMODULE_INIT_MODULE_PATH=%MODULE_PATH% -DMODULE_INIT_MODULE_NAME=%MODULE_NAME% -P CMake/HelperTools/SwModule_Handler/ModuleInit.cmake
pause
goto MENU


:RUN_ADD_COMPONENT
cls
set /p COMPONENT_NAME=Enter your component name:
set /p MODULE_NAME=Enter your module name:
set /p MODULE_PATH=Enter path to your module (relative to project root):

cmake -DCOMPONENT_INIT_MODULE_PATH=%MODULE_PATH% -DCOMPONENT_INIT_MODULE_NAME=%MODULE_NAME% -DCOMPONENT_INIT_COMPONENT_NAME=%COMPONENT_NAME% -P CMake/HelperTools/SwModule_Handler/ModuleComponentInit.cmake
pause
goto MENU


:RUN_INIT_MODULE_CMAKE
cls
set /p MODULE_NAME=Enter your module name:
set /p MODULE_PATH=Enter path to your module (relative to project root):

echo Initializing module CMake file...
cmake -DCMAKE_INIT_MODULE_PATH=%MODULE_PATH% -DCMAKE_INIT_MODULE_NAME=%MODULE_NAME% -P CMake/HelperTools/SwModule_Handler/ModuleCmakeInit.cmake
pause
goto MENU


:RUN_INIT_TESTS
cls
set /p MODULE_NAME=Enter your module name:
set /p MODULE_PATH=Enter path to your module (relative to project root):
set TEST_TYPES=ALL
set /p TEST_TYPES=Enter test types (UT, IT, ALL - default ALL):

echo Initializing module tests...
cmake -DTEST_INIT_MODULE_PATH=%MODULE_PATH% -DTEST_INIT_MODULE_NAME=%MODULE_NAME% -DTEST_INIT_TYPES=%TEST_TYPES% -P CMake/HelperTools/Test_Handler/TestInit.cmake
pause
goto MENU


:INITIALIZATION
cls
echo =====================================
echo 0: Back to main menu
echo 1: Project structure initialization
echo 2: Initialize STM32CubeIDE project
echo 3: Initialize VSCode project
echo 4: BSP module - Configuration
echo 5: BSP module - Update version
echo 6: Middleware module - Configuration
echo 7: Middleware module - Update version
echo 8: Documents module - Configuration
echo 9: Module update (Updater)
echo =====================================
set /p choice=Enter your selection (0-9):

if "%choice%"=="0" goto MENU
if "%choice%"=="1" goto RUN_INIT_PROJECT
if "%choice%"=="2" goto RUN_INIT_CUBEIDE
if "%choice%"=="3" goto RUN_INIT_VSCODE
if "%choice%"=="4" goto RUN_BSP_CONFIG
if "%choice%"=="5" goto RUN_BSP_UPDATE
if "%choice%"=="6" goto RUN_MW_CONFIG
if "%choice%"=="7" goto RUN_MW_UPDATE
if "%choice%"=="8" goto RUN_DOCS_INIT
if "%choice%"=="9" goto RUN_MODULE_UPDATE

echo Incorrect selection. Try again.
pause
goto INITIALIZATION


:RUN_INIT_PROJECT
cls
cmake -P CMake/HelperTools/Prj_Handler/Prj_Handler.cmake
cmake -P CMake/HelperTools/App_Handler/App_ModuleHandler.cmake
pause
goto INITIALIZATION


:RUN_INIT_CUBEIDE
cls
set /p PROJECT_NAME=Enter project name (without spaces):
cmake -DPROJECT_NAME=%PROJECT_NAME% -P CMake/HelperTools/Prj_Handler/Prj_CubeIDE_Handler.cmake
pause
goto INITIALIZATION


:RUN_INIT_VSCODE
cls
cmake -DFUNCTION_ID="MCU_LIST" -P CMake/HelperTools/Prj_Handler/Prj_VSCode_Handler.cmake
set "MCU_IDS="
set /p MCU_IDS=Enter MCU IDs of debug configurations (separated by comma, 0 = all, empty = MCUs of connected boards):
cmake -DFUNCTION_ID="INIT" "-DMCU_IDS=%MCU_IDS%" -P CMake/HelperTools/Prj_Handler/Prj_VSCode_Handler.cmake
pause
goto INITIALIZATION


:RUN_RAL_PORT_PROCESS
cls
cmake -P CMake/HelperTools/Ral_Handler/RalProcessing.cmake
pause
goto INITIALIZATION


:RUN_BSP_CONFIG
cls
cmake -DFUNCTION_ID="BRANCH_LIST" -P CMake/HelperTools/Bsp_Handler/Bsp_ModuleHandler.cmake
set /p BRANCH_ID=Enter branch ID (numerical):
cmake -DFUNCTION_ID="BSP_CONFIG" -DBRANCH_ID=%BRANCH_ID% -P CMake/HelperTools/Bsp_Handler/Bsp_ModuleHandler.cmake
pause
goto INITIALIZATION

:RUN_BSP_UPDATE
cls
cmake -DFUNCTION_ID="BSP_UPDATE" -P CMake/HelperTools/Bsp_Handler/Bsp_ModuleHandler.cmake
pause
goto INITIALIZATION


:RUN_MW_CONFIG
cls
cmake -DFUNCTION_ID="MODULE_LIST" -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
set "MODULE_ID="
set /p MODULE_ID=Enter middleware ID (numerical):
if "%MODULE_ID%"=="" goto INITIALIZATION
if "%MODULE_ID%"=="0" goto INITIALIZATION
cmake -DFUNCTION_ID="VERSION_LIST" -DMODULE_ID=%MODULE_ID% -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
set "VERSION_ID=0"
set /p VERSION_ID=Enter version ID (numerical, 0 = Latest):
cmake -DFUNCTION_ID="MW_CONFIG" -DMODULE_ID=%MODULE_ID% -DVERSION_ID=%VERSION_ID% -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
pause
goto INITIALIZATION


:RUN_MW_UPDATE
cls
cmake -DFUNCTION_ID="MODULE_LIST" -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
set "MODULE_ID="
set /p MODULE_ID=Enter middleware ID to update (numerical):
if "%MODULE_ID%"=="" goto INITIALIZATION
if "%MODULE_ID%"=="0" goto INITIALIZATION
cmake -DFUNCTION_ID="MW_UPDATE" -DMODULE_ID=%MODULE_ID% -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
pause
goto INITIALIZATION


:RUN_DOCS_INIT
cls
cmake -DFUNCTION_ID="DOCS_LIST" -P CMake/HelperTools/Bsp_Handler/Bsp_ModuleHandler.cmake
set /p BRANCH_ID=Enter branch ID (numerical):
cmake -DFUNCTION_ID="DOCS_INIT" -DBRANCH_ID=%BRANCH_ID% -P CMake/HelperTools/Bsp_Handler/Bsp_ModuleHandler.cmake
pause
goto INITIALIZATION

:RUN_BUILD
cls
cmake -DFUNCTION_ID="MCU_LIST" -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
set "MCU_ID="
set /p MCU_ID=Enter MCU ID (numerical):
if "%MCU_ID%"=="" goto MENU
if "%MCU_ID%"=="0" goto MENU
set "BUILD_TYPE_ID=1"
set /p BUILD_TYPE_ID=Enter build type (1: Debug, 2: Release - default Debug):
set "BUILD_TYPE=Debug"
if "%BUILD_TYPE_ID%"=="2" set "BUILD_TYPE=Release"
cmake -DFUNCTION_ID="BUILD" -DMCU_ID=%MCU_ID% -DBUILD_TYPE=%BUILD_TYPE% -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
pause
goto MENU


:RUN_DOCS
cls
cmake -DFUNCTION_ID="MCU_LIST" -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
set "MCU_ID="
set /p MCU_ID=Enter MCU ID (numerical):
if "%MCU_ID%"=="" goto MENU
if "%MCU_ID%"=="0" goto MENU
cmake -DFUNCTION_ID="DOCS" -DMCU_ID=%MCU_ID% -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
pause
goto MENU


:RUN_TESTS
cls
echo =====================================
echo 0: Back to main menu
echo 1: Unit tests
echo 2: Integration tests
echo =====================================
set "choice="
set /p choice=Enter your selection (0-2):

if "%choice%"=="0" goto MENU
if "%choice%"=="1" (
    set "TEST_TYPE=UT"
    set "TARGET_TEXT=MCU"
    goto RUN_TESTS_TARGET
)
if "%choice%"=="2" (
    set "TEST_TYPE=IT"
    set "TARGET_TEXT=board"
    goto RUN_TESTS_TARGET
)

echo Incorrect selection. Try again.
pause
goto RUN_TESTS

:RUN_TESTS_TARGET
cls
cmake -DFUNCTION_ID="TEST_TARGET_LIST" -DTEST_TYPE=%TEST_TYPE% -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
set "TARGET_ID="
set /p TARGET_ID=Enter %TARGET_TEXT% ID (numerical):
if "%TARGET_ID%"=="" goto RUN_TESTS
if "%TARGET_ID%"=="0" goto RUN_TESTS
cmake -DFUNCTION_ID="TEST_BUILD" -DTEST_TYPE=%TEST_TYPE% -DTARGET_ID=%TARGET_ID% -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
if errorlevel 1 (
    pause
    goto MENU
)
set "TEST_ID=0"
set /p TEST_ID=Enter test set ID (numerical, 0 = All test sets):
cmake -DFUNCTION_ID="TEST_RUN" -DTEST_TYPE=%TEST_TYPE% -DTARGET_ID=%TARGET_ID% -DTEST_ID=%TEST_ID% -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
pause
goto MENU


:RUN_MODULE_UPDATE
cls
cmake -DFUNCTION_ID="VERSION_LIST" -P CMake/Updater/Updater.cmake
set "FROM_VERSION_ID="
set /p FROM_VERSION_ID=Enter first update ID (numerical, empty = first):
set "TO_VERSION_ID="
set /p TO_VERSION_ID=Enter last update ID (numerical, empty or 0 = latest):
echo.
cmake -DFUNCTION_ID="MODULE_LIST" -P CMake/Updater/Updater.cmake
set "MODULE_IDS="
set /p MODULE_IDS=Enter module IDs (separated by comma, empty or 0 = all):
echo.
echo Branches of the module repositories (local and origin branches):
echo   empty    - checked out branches only
echo   branches - names or patterns separated by comma, e.g. Dev/STM32F4/*,Releases/STM32G4
set "UPDATE_BRANCHES="
set /p UPDATE_BRANCHES=Enter branches:
echo.
echo 1: Dry run - show changes only (default)
echo 2: Apply - keep changes uncommitted (checked out branches only)
echo 3: Apply and commit
set "MODE_ID="
set /p MODE_ID=Enter update mode (1-3):
set "UPDATE_MODE=DRY_RUN"
set "COMMIT_MESSAGE="
set "UPDATE_PUSH=OFF"
if "%MODE_ID%"=="2" set "UPDATE_MODE=APPLY"
if not "%MODE_ID%"=="3" goto RUN_MODULE_UPDATE_EXEC
set "UPDATE_MODE=COMMIT"
set /p COMMIT_MESSAGE=Enter commit message (e.g. AB#123: Module CMakeLists updated.):
set "PUSH_ANSWER="
set /p PUSH_ANSWER=Push committed branches to origin (y/N):
if /i "%PUSH_ANSWER%"=="y" set "UPDATE_PUSH=ON"

:RUN_MODULE_UPDATE_EXEC
cmake -DFUNCTION_ID="UPDATE" "-DFROM_VERSION_ID=%FROM_VERSION_ID%" "-DTO_VERSION_ID=%TO_VERSION_ID%" "-DMODULE_IDS=%MODULE_IDS%" "-DUPDATE_BRANCHES=%UPDATE_BRANCHES%" "-DUPDATE_MODE=%UPDATE_MODE%" "-DUPDATE_COMMIT_MESSAGE=%COMMIT_MESSAGE%" "-DUPDATE_PUSH=%UPDATE_PUSH%" -P CMake/Updater/Updater.cmake
pause
goto INITIALIZATION

:END
echo Exiting...
pause
exit
