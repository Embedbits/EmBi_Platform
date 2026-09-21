#!/bin/bash
cd "$(dirname "$0")" || exit 1

pause() {
    read -n 1 -s -r -p "Press any key to continue . . ."
    echo
}

menu() {
    clear
    echo "====================================="
    echo "0: Exit"
    echo "1. Add module"
    echo "2: Add module component"
    echo "3: Add module CMake file"
    echo "4: Configuration"
    echo "====================================="
    read -p "Enter your selection (0-4): " choice
    case "$choice" in
        0) end ;;
        1) run_init_module ;;
        2) run_add_component ;;
        3) run_init_module_cmake ;;
        4) initialization ;;
        *)
            echo "Incorrect selection. Try again."
            pause
            menu
            ;;
    esac
}

run_init_module() {
    clear
    read -p "Enter your module name: " MODULE_NAME
    read -p "Enter path to your module (relative to project root): " MODULE_PATH
    cmake -DMODULE_INIT_MODULE_PATH="$MODULE_PATH" -DMODULE_INIT_MODULE_NAME="$MODULE_NAME" -P CMake/HelperTools/SwModule_Handler/ModuleInit.cmake
    pause
    menu
}

run_add_component() {
    clear
    read -p "Enter your component name: " COMPONENT_NAME
    read -p "Enter your module name: " MODULE_NAME
    read -p "Enter path to your module (relative to project root): " MODULE_PATH
    cmake -DCOMPONENT_INIT_MODULE_PATH="$MODULE_PATH" -DCOMPONENT_INIT_MODULE_NAME="$MODULE_NAME" -DCOMPONENT_INIT_COMPONENT_NAME="$COMPONENT_NAME" -P CMake/HelperTools/SwModule_Handler/ModuleComponentInit.cmake
    pause
    menu
}

run_init_module_cmake() {
    clear
    read -p "Enter your module name: " MODULE_NAME
    read -p "Enter path to your module (relative to project root): " MODULE_PATH
    echo "Initializing module CMake file..."
    cmake -DCMAKE_INIT_MODULE_PATH="$MODULE_PATH" -DCMAKE_INIT_MODULE_NAME="$MODULE_NAME" -P CMake/HelperTools/SwModule_Handler/ModuleCmakeInit.cmake
    pause
    menu
}

initialization() {
    clear
    echo "====================================="
    echo "0: Back to main menu"
    echo "1: Project structure initialization"
    echo "2: STM32CubeIDE project initialization"
    echo "3: BSP module - Configuration"
    echo "4: BSP module - Update version"
    echo "5: Middleware module - Configuration"
    echo "6: Middleware module - Update version"
    echo "7: Documents module - Configuration"
    echo "====================================="
    read -p "Enter your selection (0-7): " choice
    case "$choice" in
        0) menu ;;
        1) run_init_project ;;
        2) run_init_cubeide ;;
        3) run_bsp_config ;;
        4) run_bsp_update ;;
        5) run_mw_config ;;
        6) run_mw_update ;;
        7) run_docs_init ;;
        *)
            echo "Incorrect selection. Try again."
            pause
            initialization
            ;;
    esac
}

run_init_project() {
    clear
    cmake -P CMake/HelperTools/Prj_Handler/Prj_Handler.cmake
    cmake -P CMake/HelperTools/App_Handler/App_ModuleHandler.cmake
    pause
    initialization
}

run_init_cubeide() {
    clear
    read -p "Enter project name (without spaces): " PROJECT_NAME
    cmake -DPROJECT_NAME="$PROJECT_NAME" -P CMake/HelperTools/Prj_Handler/Prj_CubeIDE_Handler.cmake
    pause
    initialization
}

run_bsp_config() {
    clear
    cmake -DFUNCTION_ID="BRANCH_LIST" -P CMake/HelperTools/Bsp_Handler/Bsp_ModuleHandler.cmake
    read -p "Enter branch ID (numerical): " BRANCH_ID
    cmake -DFUNCTION_ID="BSP_CONFIG" -DBRANCH_ID="$BRANCH_ID" -P CMake/HelperTools/Bsp_Handler/Bsp_ModuleHandler.cmake
    pause
    initialization
}

run_bsp_update() {
    clear
    cmake -DFUNCTION_ID="BSP_UPDATE" -P CMake/HelperTools/Bsp_Handler/Bsp_ModuleHandler.cmake
    pause
    initialization
}

run_mw_config() {
    clear
    cmake -DFUNCTION_ID="MODULE_LIST" -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
    read -p "Enter middleware ID (numerical): " MODULE_ID
    cmake -DFUNCTION_ID="VERSION_LIST" -DMODULE_ID="$MODULE_ID" -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
    read -p "Enter version ID (numerical, 0 = Latest): " VERSION_ID
    cmake -DFUNCTION_ID="MW_CONFIG" -DMODULE_ID="$MODULE_ID" -DVERSION_ID="$VERSION_ID" -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
    pause
    initialization
}

run_mw_update() {
    clear
    cmake -DFUNCTION_ID="MODULE_LIST" -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
    read -p "Enter middleware ID to update (numerical): " MODULE_ID
    cmake -DFUNCTION_ID="MW_UPDATE" -DMODULE_ID="$MODULE_ID" -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
    pause
    initialization
}

run_docs_init() {
    clear
    cmake -DFUNCTION_ID="DOCS_LIST" -P CMake/HelperTools/Bsp_Handler/Bsp_ModuleHandler.cmake
    read -p "Enter branch ID (numerical): " BRANCH_ID
    cmake -DFUNCTION_ID="DOCS_INIT" -DBRANCH_ID="$BRANCH_ID" -P CMake/HelperTools/Bsp_Handler/Bsp_ModuleHandler.cmake
    pause
    initialization
}

end() {
    echo "Exiting..."
    pause
    exit 0
}

menu
