################################################################################
# Author: Mr.Nobody
# file:  CMakeLists.txt
# brief: Self-test module of the coverage report.
#
# A tiny module (Calc) with unit tests whose coverage is known: Calc_Unused is
# never called, Calc_Clamp is not tested below the minimum. The test
# Coverage_SelfTest.cmake executes the tests with the coverage and compares the
# report with the known numbers - it checks gcovr, gcov, the report scripts and the
# paths on the platform of the host. The module is not part of any project build.
#
#   cmake -P EmBi_Platform/CMake/Coverage/Coverage_SelfTest.cmake
################################################################################

if(UNIT_TESTING_AVAILABLE STREQUAL "ON")
    UnitTesting_AddPath("${CMAKE_CURRENT_SOURCE_DIR}/Tests/UnitTests")
endif()
