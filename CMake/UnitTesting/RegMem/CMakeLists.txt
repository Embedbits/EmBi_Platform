################################################################################
# Author: Mr.Nobody
# file:  CMakeLists.txt
# brief: Unit tests of the register memory emulation (RegMem) itself.
#
# RegMem is part of the unit testing framework (ut_RegMem library, see
# UnitTesting.cmake), this file only registers its self-test. The tests are
# not part of any project build, they are executed standalone:
#
#   cmake -DMODULE_PATH=EmBi_Platform/CMake/UnitTesting/RegMem
#         -P EmBi_Platform/CMake/UnitTesting/Standalone/RunModuleTests.cmake
################################################################################

if(UNIT_TESTING_AVAILABLE STREQUAL "ON")
    UnitTesting_AddPath("${CMAKE_CURRENT_SOURCE_DIR}/Tests/UnitTests")
endif()
