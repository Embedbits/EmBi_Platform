################################################################################
# Author: Mr.Nobody
# file:  CMakeLists.txt
# brief: Unit tests of the self-test module of the coverage report.
################################################################################

UnitTesting_Add_Test(
    NAME            Calc
    TEST_SOURCE     Test_Calc.c
    UUT_SOURCES     ${CMAKE_CURRENT_SOURCE_DIR}/../../Calc.c
    INCLUDE_DIRS    ${CMAKE_CURRENT_SOURCE_DIR}/../..
)
