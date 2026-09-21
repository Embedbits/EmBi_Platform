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
echo 4: Configuration
echo =====================================
set /p choice=Enter your selection (0-4):

if "%choice%"=="0" goto END
if "%choice%"=="1" goto RUN_INIT_MODULE
if "%choice%"=="2" goto RUN_ADD_COMPONENT
if "%choice%"=="3" goto RUN_INIT_MODULE_CMAKE
if "%choice%"=="4" goto INITIALIZATION

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


:INITIALIZATION
cls
echo =====================================
echo 0: Back to main menu
echo 1: Project structure initialization
echo 2: Initialize STM32CubeIDE project
echo 3: BSP module - Configuration
echo 4: BSP module - Update version
echo 5: Middleware module - Configuration
echo 6: Middleware module - Update version
echo 7: Documents module - Configuration
echo =====================================
set /p choice=Enter your selection (0-7):

if "%choice%"=="0" goto MENU
if "%choice%"=="1" goto RUN_INIT_PROJECT
if "%choice%"=="2" goto RUN_INIT_CUBEIDE
if "%choice%"=="3" goto RUN_BSP_CONFIG
if "%choice%"=="4" goto RUN_BSP_UPDATE
if "%choice%"=="5" goto RUN_MW_CONFIG
if "%choice%"=="6" goto RUN_MW_UPDATE
if "%choice%"=="7" goto RUN_DOCS_INIT

echo Incorrect selection. Try again.
pause
goto MENU


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
set /p MODULE_ID=Enter middleware ID (numerical):
cmake -DFUNCTION_ID="VERSION_LIST" -DMODULE_ID=%MODULE_ID% -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
set /p VERSION_ID=Enter version ID (numerical, 0 = Latest):
cmake -DFUNCTION_ID="MW_CONFIG" -DMODULE_ID=%MODULE_ID% -DVERSION_ID=%VERSION_ID% -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
pause
goto INITIALIZATION


:RUN_MW_UPDATE
cls
cmake -DFUNCTION_ID="MODULE_LIST" -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
set /p MODULE_ID=Enter middleware ID to update (numerical):
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

:END
echo Exiting...
pause
exit
