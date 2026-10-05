/**
 * \author Mr.Nobody
 * \file CmsisHost.h
 * \ingroup UnitTesting
 * \brief Host replacement of CMSIS compiler header (cmsis_gcc.h) for unit tests.
 *
 * The file is force-included (-include) into every MCU source built for host.
 * It defines include guard of cmsis_gcc.h, so the original header (ARM inline
 * assembler: DSB, ISB, LDREX, ...) is not used. Compiler attribute macros are
 * defined same as in cmsis_gcc.h, core intrinsics are implemented as host
 * functions (CmsisHost.c) emulating core registers (PRIMASK, BASEPRI, ...) and
 * counting executed barriers, so tests can check them.
 *
 * \note Intrinsic missing here results in compile error of the test. Add it
 *       here with host implementation in CmsisHost.c.
 */

#ifndef UNITTESTING_CMSISHOST_H
#define UNITTESTING_CMSISHOST_H

/* Blocks original cmsis_gcc.h included by cmsis_compiler.h */
#define __CMSIS_GCC_H

#ifdef __cplusplus
extern "C" {
#endif

/* ============================= INCLUDES =================================== */
#include <stdint.h>                         /* Standard integer types         */
/* ============================= TYPEDEFS =================================== */

/** Enumeration of counted core instructions */
typedef enum
{
    CMSISHOST_INSTR_DSB = 0u,   /**< Data synchronization barrier        */
    CMSISHOST_INSTR_ISB,        /**< Instruction synchronization barrier */
    CMSISHOST_INSTR_DMB,        /**< Data memory barrier                 */
    CMSISHOST_INSTR_NOP,        /**< No operation                        */
    CMSISHOST_INSTR_WFI,        /**< Wait for interrupt                  */
    CMSISHOST_INSTR_WFE,        /**< Wait for event                      */
    CMSISHOST_INSTR_SEV,        /**< Send event                          */
    CMSISHOST_INSTR_CNT         /**< Count of counted instructions       */
}   cmsisHost_Instr_t;

/* ======================= COMPILER SPECIFIC DEFINES ======================== */

#ifndef   __has_builtin
  #define __has_builtin(x)                  (0)
#endif
#ifndef   __ASM
  #define __ASM                             __asm
#endif
#ifndef   __INLINE
  #define __INLINE                          inline
#endif
#ifndef   __STATIC_INLINE
  #define __STATIC_INLINE                   static inline
#endif
#ifndef   __STATIC_FORCEINLINE
  #define __STATIC_FORCEINLINE              __attribute__((always_inline)) static inline
#endif
#ifndef   __NO_RETURN
  #define __NO_RETURN                       __attribute__((__noreturn__))
#endif
#ifndef   __USED
  #define __USED                            __attribute__((used))
#endif
#ifndef   __WEAK
  #define __WEAK                            __attribute__((weak))
#endif
#ifndef   __PACKED
  #define __PACKED                          __attribute__((packed, aligned(1)))
#endif
#ifndef   __PACKED_STRUCT
  #define __PACKED_STRUCT                   struct __attribute__((packed, aligned(1)))
#endif
#ifndef   __PACKED_UNION
  #define __PACKED_UNION                    union __attribute__((packed, aligned(1)))
#endif
#ifndef   __ALIGNED
  #define __ALIGNED(x)                      __attribute__((aligned(x)))
#endif
#ifndef   __RESTRICT
  #define __RESTRICT                        __restrict
#endif
#ifndef   __COMPILER_BARRIER
  #define __COMPILER_BARRIER()              __asm volatile("":::"memory")
#endif

#ifndef   __UNALIGNED_UINT16_WRITE
  #define __UNALIGNED_UINT16_WRITE(addr, val)   CmsisHost_UnalignedWrite16( (void *)(addr), (uint16_t)(val) )
#endif
#ifndef   __UNALIGNED_UINT16_READ
  #define __UNALIGNED_UINT16_READ(addr)         CmsisHost_UnalignedRead16( (const void *)(addr) )
#endif
#ifndef   __UNALIGNED_UINT32_WRITE
  #define __UNALIGNED_UINT32_WRITE(addr, val)   CmsisHost_UnalignedWrite32( (void *)(addr), (uint32_t)(val) )
#endif
#ifndef   __UNALIGNED_UINT32_READ
  #define __UNALIGNED_UINT32_READ(addr)         CmsisHost_UnalignedRead32( (const void *)(addr) )
#endif
#ifndef   __UNALIGNED_UINT32
  #define __UNALIGNED_UINT32(x)                 (*(uint32_t *)(x))
#endif

/* Startup symbols (not used by host build, defined for completeness) */
#define __PROGRAM_START                     __cmsis_start
#define __INITIAL_SP                        __StackTop
#define __STACK_LIMIT                       __StackLimit
#define __VECTOR_TABLE                      __Vectors
#define __VECTOR_TABLE_ATTRIBUTE            __attribute__((used, section(".vectors")))

/* ========================== CORE INSTRUCTIONS ============================= */

#define __NOP()                             CmsisHost_Instr( CMSISHOST_INSTR_NOP )
#define __WFI()                             CmsisHost_Instr( CMSISHOST_INSTR_WFI )
#define __WFE()                             CmsisHost_Instr( CMSISHOST_INSTR_WFE )
#define __SEV()                             CmsisHost_Instr( CMSISHOST_INSTR_SEV )
#define __ISB()                             CmsisHost_Instr( CMSISHOST_INSTR_ISB )
#define __DSB()                             CmsisHost_Instr( CMSISHOST_INSTR_DSB )
#define __DMB()                             CmsisHost_Instr( CMSISHOST_INSTR_DMB )
#define __BKPT(value)                       CmsisHost_Bkpt( (uint32_t)(value) )
#define __SSAT(val, sat)                    CmsisHost_Ssat( (int32_t)(val), (uint32_t)(sat) )
#define __USAT(val, sat)                    CmsisHost_Usat( (int32_t)(val), (uint32_t)(sat) )

/* ========================= EXPORTED FUNCTIONS ============================= */

/* Host helpers (test interface) */
void        CmsisHost_Reset             ( void );
uint32_t    CmsisHost_Get_InstrCnt      ( cmsisHost_Instr_t instr );
void        CmsisHost_Instr             ( cmsisHost_Instr_t instr );
void        CmsisHost_Bkpt              ( uint32_t value );
int32_t     CmsisHost_Ssat              ( int32_t val, uint32_t sat );
uint32_t    CmsisHost_Usat              ( int32_t val, uint32_t sat );
uint16_t    CmsisHost_UnalignedRead16   ( const void *addr );
void        CmsisHost_UnalignedWrite16  ( void *addr, uint16_t val );
uint32_t    CmsisHost_UnalignedRead32   ( const void *addr );
void        CmsisHost_UnalignedWrite32  ( void *addr, uint32_t val );

/* Core register access (emulated registers) */
void        __enable_irq                ( void );
void        __disable_irq               ( void );
void        __enable_fault_irq          ( void );
void        __disable_fault_irq         ( void );
uint32_t    __get_PRIMASK               ( void );
void        __set_PRIMASK               ( uint32_t priMask );
uint32_t    __get_FAULTMASK             ( void );
void        __set_FAULTMASK             ( uint32_t faultMask );
uint32_t    __get_BASEPRI               ( void );
void        __set_BASEPRI               ( uint32_t basePri );
void        __set_BASEPRI_MAX           ( uint32_t basePri );
uint32_t    __get_CONTROL               ( void );
void        __set_CONTROL               ( uint32_t control );
uint32_t    __get_IPSR                  ( void );
uint32_t    __get_APSR                  ( void );
uint32_t    __get_xPSR                  ( void );
uint32_t    __get_PSP                   ( void );
void        __set_PSP                   ( uint32_t topOfProcStack );
uint32_t    __get_MSP                   ( void );
void        __set_MSP                   ( uint32_t topOfMainStack );
uint32_t    __get_PSPLIM                ( void );
void        __set_PSPLIM                ( uint32_t procStackPtrLimit );
uint32_t    __get_MSPLIM                ( void );
void        __set_MSPLIM                ( uint32_t mainStackPtrLimit );
uint32_t    __get_FPSCR                 ( void );
void        __set_FPSCR                 ( uint32_t fpscr );

/* Data processing */
uint8_t     __CLZ                       ( uint32_t value );
uint32_t    __RBIT                      ( uint32_t value );
uint32_t    __REV                       ( uint32_t value );
uint32_t    __REV16                     ( uint32_t value );
int16_t     __REVSH                     ( int16_t value );
uint32_t    __ROR                       ( uint32_t op1, uint32_t op2 );

/* Exclusive access (host is single threaded - store always succeeds) */
uint8_t     __LDREXB                    ( volatile uint8_t  *addr );
uint16_t    __LDREXH                    ( volatile uint16_t *addr );
uint32_t    __LDREXW                    ( volatile uint32_t *addr );
uint32_t    __STREXB                    ( uint8_t  value, volatile uint8_t  *addr );
uint32_t    __STREXH                    ( uint16_t value, volatile uint16_t *addr );
uint32_t    __STREXW                    ( uint32_t value, volatile uint32_t *addr );
void        __CLREX                     ( void );

#ifdef __cplusplus
}
#endif

#endif /* UNITTESTING_CMSISHOST_H */
