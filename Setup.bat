@echo off
cd /d %~dp0
setlocal enabledelayedexpansion


:MENU
cls
echo =====================================
echo 0: Exit
echo 1. Create module           
echo 2: Add component     
echo 3: Add CMake file
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
echo 1: Initialize project necessary files
echo 2: Initialize STM32CubeIDE project
echo 3: Configure application layer
echo 4: Configure BSP module
echo 5: Update documents module
echo 6: Configure Middleware module
echo 7: Update BSP module (same branch)
echo =====================================
set /p choice=Enter your selection (0-7):

if "%choice%"=="0" goto MENU
if "%choice%"=="1" goto RUN_INIT_PROJECT
if "%choice%"=="2" goto RUN_INIT_CUBEIDE
if "%choice%"=="3" goto RUN_APP_CONFIG
if "%choice%"=="4" goto RUN_BSP_CONFIG
if "%choice%"=="5" goto RUN_DOCS_INIT
if "%choice%"=="6" goto RUN_MW_CONFIG
if "%choice%"=="7" goto RUN_BSP_UPDATE

echo Incorrect selection. Try again.
pause
goto MENU


:RUN_INIT_PROJECT
cls
cmake -P CMake/HelperTools/Prj_Handler/Prj_Handler.cmake
pause
goto INITIALIZATION


:RUN_INIT_CUBEIDE
cls
set /p PROJECT_NAME=Enter project name (without spaces):
cmake -DPROJECT_NAME=%PROJECT_NAME% -P CMake/HelperTools/Prj_Handler/Prj_CubeIDE_Handler.cmake
pause
goto INITIALIZATION


:RUN_APP_CONFIG
cls
echo Running App_ModuleHandler.cmake ...
cmake -P CMake/HelperTools/App_Handler/App_ModuleHandler.cmake
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


:RUN_DOCS_INIT
cls
cmake -DFUNCTION_ID="DOCS_LIST" -P CMake/HelperTools/Bsp_Handler/Bsp_ModuleHandler.cmake
set /p BRANCH_ID=Enter branch ID (numerical):
cmake -DFUNCTION_ID="DOCS_INIT" -DBRANCH_ID=%BRANCH_ID% -P CMake/HelperTools/Bsp_Handler/Bsp_ModuleHandler.cmake
pause
goto INITIALIZATION


:RUN_MW_CONFIG
cls
cmake -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
set /p COMPONENT_ID=Enter component ID (numerical):
cmake -DMODULE_ID=%COMPONENT_ID% -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
pause
goto INITIALIZATION

:END
echo Exiting...
pause
exit
