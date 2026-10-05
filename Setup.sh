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
    echo "4: Add tests to existing module"
    echo "5: Configuration"
    echo "6: Build"
    echo "7: Tests"
    echo "8: Documentation"
    echo "====================================="
    read -p "Enter your selection (0-8): " choice
    case "$choice" in
        0) end ;;
        1) run_init_module ;;
        2) run_add_component ;;
        3) run_init_module_cmake ;;
        4) run_init_tests ;;
        5) initialization ;;
        6) run_build ;;
        7) run_tests ;;
        8) run_docs ;;
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

run_init_tests() {
    clear
    read -p "Enter your module name: " MODULE_NAME
    read -p "Enter path to your module (relative to project root): " MODULE_PATH
    read -p "Enter test types (UT, IT, ALL - default ALL): " TEST_TYPES
    echo "Initializing module tests..."
    cmake -DTEST_INIT_MODULE_PATH="$MODULE_PATH" -DTEST_INIT_MODULE_NAME="$MODULE_NAME" -DTEST_INIT_TYPES="${TEST_TYPES:-ALL}" -P CMake/HelperTools/Test_Handler/TestInit.cmake
    pause
    menu
}

initialization() {
    clear
    echo "====================================="
    echo "0: Back to main menu"
    echo "1: Project structure initialization"
    echo "2: STM32CubeIDE project initialization"
    echo "3: VSCode project initialization"
    echo "4: BSP module - Configuration"
    echo "5: BSP module - Update version"
    echo "6: Middleware module - Configuration"
    echo "7: Middleware module - Update version"
    echo "8: Documents module - Configuration"
    echo "9: Module update (Updater)"
    echo "====================================="
    read -p "Enter your selection (0-9): " choice
    case "$choice" in
        0) menu ;;
        1) run_init_project ;;
        2) run_init_cubeide ;;
        3) run_init_vscode ;;
        4) run_bsp_config ;;
        5) run_bsp_update ;;
        6) run_mw_config ;;
        7) run_mw_update ;;
        8) run_docs_init ;;
        9) run_module_update ;;
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

run_init_vscode() {
    clear
    cmake -DFUNCTION_ID="MCU_LIST" -P CMake/HelperTools/Prj_Handler/Prj_VSCode_Handler.cmake
    read -p "Enter MCU IDs of debug configurations (separated by comma, 0 = all, empty = MCUs of connected boards): " MCU_IDS
    cmake -DFUNCTION_ID="INIT" -DMCU_IDS="$MCU_IDS" -P CMake/HelperTools/Prj_Handler/Prj_VSCode_Handler.cmake
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
    if [ -z "$MODULE_ID" ] || [ "$MODULE_ID" = "0" ]; then
        initialization
        return
    fi
    cmake -DFUNCTION_ID="VERSION_LIST" -DMODULE_ID="$MODULE_ID" -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
    read -p "Enter version ID (numerical, 0 = Latest): " VERSION_ID
    VERSION_ID="${VERSION_ID:-0}"
    cmake -DFUNCTION_ID="MW_CONFIG" -DMODULE_ID="$MODULE_ID" -DVERSION_ID="$VERSION_ID" -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
    pause
    initialization
}

run_mw_update() {
    clear
    cmake -DFUNCTION_ID="MODULE_LIST" -P CMake/HelperTools/Mw_Handler/Mw_ModuleHandler.cmake
    read -p "Enter middleware ID to update (numerical): " MODULE_ID
    if [ -z "$MODULE_ID" ] || [ "$MODULE_ID" = "0" ]; then
        initialization
        return
    fi
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

run_build() {
    clear
    cmake -DFUNCTION_ID="MCU_LIST" -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
    read -p "Enter MCU ID (numerical): " MCU_ID
    if [ -z "$MCU_ID" ] || [ "$MCU_ID" = "0" ]; then
        menu
        return
    fi
    read -p "Enter build type (1: Debug, 2: Release - default Debug): " BUILD_TYPE_ID
    BUILD_TYPE="Debug"
    if [ "$BUILD_TYPE_ID" = "2" ]; then
        BUILD_TYPE="Release"
    fi
    cmake -DFUNCTION_ID="BUILD" -DMCU_ID="$MCU_ID" -DBUILD_TYPE="$BUILD_TYPE" -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
    pause
    menu
}

run_docs() {
    clear
    cmake -DFUNCTION_ID="MCU_LIST" -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
    read -p "Enter MCU ID (numerical): " MCU_ID
    if [ -z "$MCU_ID" ] || [ "$MCU_ID" = "0" ]; then
        menu
        return
    fi
    cmake -DFUNCTION_ID="DOCS" -DMCU_ID="$MCU_ID" -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
    pause
    menu
}

run_tests() {
    clear
    echo "====================================="
    echo "0: Back to main menu"
    echo "1: Unit tests"
    echo "2: Integration tests"
    echo "====================================="
    read -p "Enter your selection (0-2): " choice
    case "$choice" in
        0) menu; return ;;
        1) TEST_TYPE="UT" ;;
        2) TEST_TYPE="IT" ;;
        *)
            echo "Incorrect selection. Try again."
            pause
            run_tests
            return
            ;;
    esac
    clear
    cmake -DFUNCTION_ID="TEST_TARGET_LIST" -DTEST_TYPE="$TEST_TYPE" -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
    if [ "$TEST_TYPE" = "UT" ]; then
        read -p "Enter MCU ID (numerical): " TARGET_ID
    else
        read -p "Enter board ID (numerical): " TARGET_ID
    fi
    if [ -z "$TARGET_ID" ] || [ "$TARGET_ID" = "0" ]; then
        run_tests
        return
    fi
    if ! cmake -DFUNCTION_ID="TEST_BUILD" -DTEST_TYPE="$TEST_TYPE" -DTARGET_ID="$TARGET_ID" -P CMake/HelperTools/Build_Handler/Build_Handler.cmake; then
        pause
        menu
        return
    fi
    read -p "Enter test set ID (numerical, 0 = All test sets): " TEST_ID
    TEST_ID="${TEST_ID:-0}"
    cmake -DFUNCTION_ID="TEST_RUN" -DTEST_TYPE="$TEST_TYPE" -DTARGET_ID="$TARGET_ID" -DTEST_ID="$TEST_ID" -P CMake/HelperTools/Build_Handler/Build_Handler.cmake
    pause
    menu
}

run_module_update() {
    clear
    cmake -DFUNCTION_ID="VERSION_LIST" -P CMake/Updater/Updater.cmake
    read -p "Enter first update ID (numerical, empty = first): " FROM_VERSION_ID
    read -p "Enter last update ID (numerical, empty or 0 = latest): " TO_VERSION_ID
    echo
    cmake -DFUNCTION_ID="MODULE_LIST" -P CMake/Updater/Updater.cmake
    read -p "Enter module IDs (separated by comma, empty or 0 = all): " MODULE_IDS
    echo
    echo "Branches of the module repositories (local and origin branches):"
    echo "  empty    - checked out branches only"
    echo "  branches - names or patterns separated by comma, e.g. Dev/STM32F4/*,Releases/STM32G4"
    read -p "Enter branches: " UPDATE_BRANCHES
    echo
    echo "1: Dry run - show changes only (default)"
    echo "2: Apply - keep changes uncommitted (checked out branches only)"
    echo "3: Apply and commit"
    read -p "Enter update mode (1-3): " MODE_ID
    UPDATE_MODE="DRY_RUN"
    COMMIT_MESSAGE=""
    UPDATE_PUSH="OFF"
    case "$MODE_ID" in
        2) UPDATE_MODE="APPLY" ;;
        3)
            UPDATE_MODE="COMMIT"
            read -p "Enter commit message (e.g. AB#123: Module CMakeLists updated.): " COMMIT_MESSAGE
            read -p "Push committed branches to origin (y/N): " PUSH_ANSWER
            if [ "$PUSH_ANSWER" = "y" ] || [ "$PUSH_ANSWER" = "Y" ]; then
                UPDATE_PUSH="ON"
            fi
            ;;
    esac
    cmake -DFUNCTION_ID="UPDATE" -DFROM_VERSION_ID="$FROM_VERSION_ID" -DTO_VERSION_ID="$TO_VERSION_ID" \
          -DMODULE_IDS="$MODULE_IDS" -DUPDATE_BRANCHES="$UPDATE_BRANCHES" -DUPDATE_MODE="$UPDATE_MODE" \
          -DUPDATE_COMMIT_MESSAGE="$COMMIT_MESSAGE" -DUPDATE_PUSH="$UPDATE_PUSH" -P CMake/Updater/Updater.cmake
    pause
    initialization
}

end() {
    echo "Exiting..."
    pause
    exit 0
}

menu
