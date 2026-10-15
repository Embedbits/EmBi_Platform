################################################################################
# Author: Mr.Nobody
# file:  CMakeLists.txt
# brief: Unit tests of RegMem.
################################################################################

# Synchronous HW model (write trap)
UnitTesting_Add_Test(
    NAME            RegMem
    TEST_SOURCE     Test_RegMem.c
    LINK_LIBS       ut_RegMem
)

# HW model thread (fallback of the synchronous model)
UnitTesting_Add_Test(
    NAME            RegMemThread
    TEST_SOURCE     Test_RegMemThread.c
    LINK_LIBS       ut_RegMem
    RUN_SERIAL
)
