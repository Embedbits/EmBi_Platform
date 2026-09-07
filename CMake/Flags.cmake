set(MCPU_CORTEX_M0                      "-mcpu=cortex-m0")
set(MCPU_CORTEX_M0PLUS                  "-mcpu=cortex-m0plus")
set(MCPU_CORTEX_M3                      "-mcpu=cortex-m3")
set(MCPU_CORTEX_M4                      "-mcpu=cortex-m4")
set(MCPU_CORTEX_M7                      "-mcpu=cortex-m7")
set(MCPU_CORTEX_M33                     "-mcpu=cortex-m33")
set(MCPU_CORTEX_M55                     "-mcpu=cortex-m55")
set(MCPU_CORTEX_M85                     "-mcpu=cortex-m85")

set(MFLOAT_ABI_SOFTWARE                 "-mfloat-abi=soft")   # Uses floating-point convention (The compiler stores the function arguments in integer registers.)
set(MFLOAT_ABI_HARDWARE                 "-mfloat-abi=hard")   # Uses floating-point convention (The compiler stores the function arguments in the registers of the floating-point unit.)
set(MFLOAT_ABI_MIX                      "-mfloat-abi=softfp") # Uses floating-point convention (The compiler uses the floating-point unit, but it stores the function arguments in the integer registers.)

set(MFPU_NONE                           "-mfpu=none")        # Prevents the compiler from using hardware-based floating-point functions. If the compiler encounters floating-point types in the source code, it uses software-based floating-point library functions. This is similar to the -mfloat-abi=soft option.
set(MFPU_FPV4_SP_D16                    "-mfpu=fpv4-sp-d16") # Enable the Armv7 FPv4-SP-D16 floating-point extension.
set(MFPU_FPV5_D16                       "-mfpu=fpv5-d16")    # Enable the Armv7 FPv5-D16 floating-point extension.
set(MFPU_FPV4_D16                       "-mfpu=vfpv4-d16")   # Enable the Armv7 VFPv4-D16 floating-point extension. Disable the Advanced SIMD extension.
set(MFPU_FPV5_SP_D16                    "-mfpu=fpv5-sp-d16") # Enable the Armv7 FPv5-SP-D16 floating-point extension.

set(RUNTIME_LIBRARY_REDUCED_C           "--specs=nano.specs")
set(RUNTIME_LIBRARY_STD_C               "")
set(RUNTIME_LIBRARY_SYSCALLS_MINIMAL    "--specs=nosys.specs")
set(RUNTIME_LIBRARY_SYSCALLS_NONE       "")

# Architecture settings
set(THUMB_MODE                          "-mthumb") # Enables Thumb instruction set (reduces code size)
                                        
# Warning settings                      
set(THREAT_WARNINGS_AS_ERRORS           "-Werror")                         # Treats all warnings as errors (forces strict coding)
set(ENABLE_ALL_WARNINGS                 "-Wall")                           # Enables most common warnings
set(ENABLE_EXTRA_WARNINGS               "-Wextra")                         # Enables additional warnings
set(WARN_SHADOW                         "-Wshadow")                        # Warns when a variable shadows another variable
set(WARN_IMPLICIT_FUNC                  "-Wimplicit-function-declaration") # Warns about missing function declarations in C
set(WARN_POINTER_ARITH                  "-Wpointer-arith")                 # Warns about unsafe pointer arithmetic
set(WARN_CAST_ALIGN                     "-Wcast-align")                    # Warns when a pointer cast changes alignment requirements
set(WARN_REDUNDANT_DECLS                "-Wredundant-decls")               # Warns about redundant function declarations
set(WARN_DOUBLE_PROMOTION               "-Wdouble-promotion")              # Warns when a float is implicitly promoted to double
                                        
# Optimization settings                 
set(REMOVE_UNUSED_FUNCTIONS             "-ffunction-sections")      # Moves each function to its own section (allows linker garbage collection)
set(REMOVE_UNUSED_DATA                  "-fdata-sections")          # Moves each data item to its own section (allows linker garbage collection)
set(DISABLE_COMMON                      "-fno-common")              # Forces global variables to be explicitly defined
set(STACK_PROTECTOR                     "-fstack-protector-strong") # Adds stack protection against buffer overflows
set(SHORT_MESSAGES                      "-fmessage-length=0")       # Prevents line wrapping in compiler messages
                                        
# Optimization Levels                   
set(OPTIMIZATION_NONE                   "-O0")    # No optimization (useful for debugging)
set(OPTIMIZATION_BASIC                  "-O1")    # Basic optimizations, reduces code size slightly
set(OPTIMIZATION_MORE                   "-O2")    # Standard level of optimization, balances performance and code size
set(OPTIMIZATION_FULL                   "-O3")    # Aggressive optimizations, may increase code size
set(OPTIMIZATION_FAST                   "-Ofast") # Like -O3 but enables non-standard aggressive optimizations
set(OPTIMIZATION_SIZE                   "-Os")    # Optimizes for smallest code size
set(OPTIMIZATION_SIZE_AGGRESSIVE        "-Oz")    # Even more aggressive size optimizations
                                        
# Debug Levels                          
set(DEBUG_LEVEL_0                       "-g0") # No debug information
set(DEBUG_LEVEL_1                       "-g1") # Minimal debug information
set(DEBUG_LEVEL_2                       "-g2") # Default level, suitable for most debugging tasks
set(DEBUG_LEVEL_3                       "-g3") # Most detailed debug information, includes macro expansions
                                        
# C Language Standards                  
set(C_STANDARD_C89                      "-std=c89") # ANSI C (ISO/IEC 9899:1990)
set(C_STANDARD_C90                      "-std=c90") # C90 (equivalent to C89)
set(C_STANDARD_C99                      "-std=c99") # C99 standard with inline functions and new data types (e.g., long long)
set(C_STANDARD_C11                      "-std=c11") # C11 standard with better multi-threading support and static assertions
set(C_STANDARD_C17                      "-std=c17") # C17 (also known as C18) is a bug-fix revision of C11
set(C_STANDARD_C23                      "-std=c23") # C23, the upcoming revision of the C standard
                                        
# C++ Language Standards                
set(CXX_STANDARD_CXX98                  "-std=c++98") # First standardized version of C++
set(CXX_STANDARD_CXX03                  "-std=c++03") # Minor improvements over C++98
set(CXX_STANDARD_CXX11                  "-std=c++11") # Introduces smart pointers, lambdas, auto keyword, etc.
set(CXX_STANDARD_CXX14                  "-std=c++14") # Adds minor improvements over C++11 (e.g., generic lambdas)
set(CXX_STANDARD_CXX17                  "-std=c++17") # Introduces structured bindings, constexpr if, and more
set(CXX_STANDARD_CXX20                  "-std=c++20") # Adds concepts, coroutines, and ranges
set(CXX_STANDARD_CXX23                  "-std=c++23") # Upcoming standard with more minor improvements
                                        
# Additional Debugging Options          
set(DEBUG_DWARF2                        "-gdwarf-2") # Use DWARF v2 debugging format
set(DEBUG_DWARF3                        "-gdwarf-3") # Use DWARF v3 debugging format
set(DEBUG_DWARF4                        "-gdwarf-4") # Use DWARF v4 debugging format
set(DEBUG_DWARF5                        "-gdwarf-5") # Use DWARF v5 debugging format, latest version
                                        
# C++ language standard settings        
set(DISABLE_EXCEPTIONS                  "-fno-exceptions")         # Disables C++ exception handling
set(DISABLE_RTTI                        "-fno-rtti")               # Disables runtime type information (RTTI)
set(DISABLE_THREADSAFE_STATICS          "-fno-threadsafe-statics") # Disables thread-safe initialization of static variables
set(PRINT_HEADER_DEPENDENCIES           "-H")                      # Prints list of all included header files in execution order
                                        
# Linker settings                       
set(LINKER_NOSYS                        "--specs=nosys.specs")      # Removes dependency on system calls (useful for embedded systems)
set(LINKER_NANO                         "--specs=nano.specs")       # Enables smaller standard library functions
set(ENABLE_GC_SECTIONS                  "-Wl,--gc-sections")        # Enables linker garbage collection (removes unused sections)
set(PRINT_MEMORY_USAGE                  "-Wl,--print-memory-usage") # Prints memory usage statistics after linking
set(PRINTF_FLOAT                        "-u _printf_float")         # Enables floating-point support for printf
set(SCANF_FLOAT                         "-u _scanf_float")          # Enables floating-point support for scanf
set(LINKER_START_GROUP                  "-Wl,--start-group")        # Groups multiple libraries together to resolve circular dependencies
set(LINK_LIB_STDCPP                     "-lstdc++")                 # Links the GNU Standard C++ Library
set(LINK_LIB_SUPCXX                     "-lsupc++")                 # Links the GCC support library, which provides low-level runtime support for C++
set(LINKER_END_GROUP                    "-Wl,--end-group")          # Ends the grouped linking process
set(LINK_LIB_C                          "-lc")                      # Links the C standard library, which provides basic C runtime functions
set(LINK_LIB_MATH                       "-lm")                      # Links the math library, which provides mathematical functions like sin, cos, exp, etc.
                                        
                                        
# Assembler settings                    
set(ASSEMBLER_MODE                      "-x assembler-with-cpp")  # Allows preprocessing of assembly files
set(GENERATE_DEPENDENCY_FILE            "-MMD") # Generate dependency files (.d) for the source file, which includes the headers it depends on 
set(INCLUDE_EMPTY_DEPENDENCY_RULES      "-MP")  # Include empty rules for non-existent dependencies, preventing errors when header files are removed