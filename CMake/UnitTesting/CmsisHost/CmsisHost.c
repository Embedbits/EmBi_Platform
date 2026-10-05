/**
 * \author Mr.Nobody
 * \file CmsisHost.c
 * \ingroup UnitTesting
 * \brief Host implementation of CMSIS core intrinsics for unit tests.
 *
 */

/* ============================= INCLUDES =================================== */
#include "CmsisHost.h"                      /* Self include                   */
#include "string.h"                         /* memcpy / memset                */
/* ============================= TYPEDEFS =================================== */

/** Emulated core registers */
typedef struct
{
    uint32_t PriMask;       /**< PRIMASK   */
    uint32_t FaultMask;     /**< FAULTMASK */
    uint32_t BasePri;       /**< BASEPRI   */
    uint32_t Control;       /**< CONTROL   */
    uint32_t Psp;           /**< PSP       */
    uint32_t Msp;           /**< MSP       */
    uint32_t PspLim;        /**< PSPLIM    */
    uint32_t MspLim;        /**< MSPLIM    */
    uint32_t Fpscr;         /**< FPSCR     */
}   cmsisHost_CoreRegs_t;

/* ========================= SYMBOLIC CONSTANTS ============================= */

/** Count of bits in 32-bit word */
#define CMSISHOST_WORD_BITS                 ( 32u )

/** Mask of BASEPRI priority bits (8-bit register) */
#define CMSISHOST_BASEPRI_MASK              ( 0xFFu )

/** Mask of PRIMASK / FAULTMASK bit */
#define CMSISHOST_MASK_BIT                  ( 0x1u )

/* ========================== LOCAL VARIABLES =============================== */

static cmsisHost_CoreRegs_t cmsisHost_CoreRegs;

static uint32_t             cmsisHost_InstrCnt[ CMSISHOST_INSTR_CNT ];

/* ======================== EXPORTED FUNCTIONS ============================== */

/**
 * \brief Resets emulated core registers and instruction counters.
 *
 * \note  Shall be called in `setUp()` of tests checking core state.
 */
void CmsisHost_Reset( void )
{
    (void)memset( &cmsisHost_CoreRegs, 0, sizeof( cmsisHost_CoreRegs ) );
    (void)memset( cmsisHost_InstrCnt,  0, sizeof( cmsisHost_InstrCnt ) );
}


/**
 * \brief Returns how many times the instruction was executed since reset.
 *
 * \param instr [in]: Instruction, value from \ref cmsisHost_Instr_t
 *
 * \return Execution count, 0 for invalid instruction.
 */
uint32_t CmsisHost_Get_InstrCnt( cmsisHost_Instr_t instr )
{
    uint32_t retCnt = 0u;

    if( CMSISHOST_INSTR_CNT > instr )
    {
        retCnt = cmsisHost_InstrCnt[ instr ];
    }
    else
    {
        retCnt = 0u;
    }

    return ( retCnt );
}


/**
 * \brief Emulates instruction without operands (counts its execution).
 *
 * \param instr [in]: Instruction, value from \ref cmsisHost_Instr_t
 */
void CmsisHost_Instr( cmsisHost_Instr_t instr )
{
    if( CMSISHOST_INSTR_CNT > instr )
    {
        cmsisHost_InstrCnt[ instr ]++;
    }
    else
    {
        /* Unknown instruction */
    }
}


/**
 * \brief Breakpoint instruction - aborts test execution in debugger.
 *
 * \param value [in]: Breakpoint value (ignored)
 */
void CmsisHost_Bkpt( uint32_t value )
{
    (void)value;
    __builtin_trap();
}


int32_t CmsisHost_Ssat( int32_t val, uint32_t sat )
{
    int32_t retVal = val;

    if( ( 1u <= sat ) && ( CMSISHOST_WORD_BITS >= sat ) )
    {
        const int32_t max = (int32_t)( ( 1ULL << ( sat - 1u ) ) - 1u );
        const int32_t min = -1 - max;

        if( val > max )
        {
            retVal = max;
        }
        else if( val < min )
        {
            retVal = min;
        }
        else
        {
            retVal = val;
        }
    }
    else
    {
        retVal = val;
    }

    return ( retVal );
}


uint32_t CmsisHost_Usat( int32_t val, uint32_t sat )
{
    uint32_t retVal = (uint32_t)val;

    if( CMSISHOST_WORD_BITS > sat )
    {
        const uint32_t max = (uint32_t)( ( 1ULL << sat ) - 1u );

        if( val > (int32_t)max )
        {
            retVal = max;
        }
        else if( 0 > val )
        {
            retVal = 0u;
        }
        else
        {
            retVal = (uint32_t)val;
        }
    }
    else
    {
        retVal = (uint32_t)val;
    }

    return ( retVal );
}


uint16_t CmsisHost_UnalignedRead16( const void *addr )
{
    uint16_t retVal;

    (void)memcpy( &retVal, addr, sizeof( retVal ) );

    return ( retVal );
}


void CmsisHost_UnalignedWrite16( void *addr, uint16_t val )
{
    (void)memcpy( addr, &val, sizeof( val ) );
}


uint32_t CmsisHost_UnalignedRead32( const void *addr )
{
    uint32_t retVal;

    (void)memcpy( &retVal, addr, sizeof( retVal ) );

    return ( retVal );
}


void CmsisHost_UnalignedWrite32( void *addr, uint32_t val )
{
    (void)memcpy( addr, &val, sizeof( val ) );
}

/* ====================== CORE REGISTER ACCESS ============================== */

void     __enable_irq       ( void )            { cmsisHost_CoreRegs.PriMask   = 0u; }
void     __disable_irq      ( void )            { cmsisHost_CoreRegs.PriMask   = CMSISHOST_MASK_BIT; }
void     __enable_fault_irq ( void )            { cmsisHost_CoreRegs.FaultMask = 0u; }
void     __disable_fault_irq( void )            { cmsisHost_CoreRegs.FaultMask = CMSISHOST_MASK_BIT; }
uint32_t __get_PRIMASK      ( void )            { return ( cmsisHost_CoreRegs.PriMask ); }
void     __set_PRIMASK      ( uint32_t priMask ){ cmsisHost_CoreRegs.PriMask   = priMask & CMSISHOST_MASK_BIT; }
uint32_t __get_FAULTMASK    ( void )            { return ( cmsisHost_CoreRegs.FaultMask ); }
void     __set_FAULTMASK    ( uint32_t mask )   { cmsisHost_CoreRegs.FaultMask = mask & CMSISHOST_MASK_BIT; }
uint32_t __get_BASEPRI      ( void )            { return ( cmsisHost_CoreRegs.BasePri ); }
void     __set_BASEPRI      ( uint32_t basePri ){ cmsisHost_CoreRegs.BasePri   = basePri & CMSISHOST_BASEPRI_MASK; }
uint32_t __get_CONTROL      ( void )            { return ( cmsisHost_CoreRegs.Control ); }
void     __set_CONTROL      ( uint32_t control ){ cmsisHost_CoreRegs.Control   = control; }
uint32_t __get_IPSR         ( void )            { return ( 0u ); }  /* Thread mode */
uint32_t __get_APSR         ( void )            { return ( 0u ); }
uint32_t __get_xPSR         ( void )            { return ( 0u ); }
uint32_t __get_PSP          ( void )            { return ( cmsisHost_CoreRegs.Psp ); }
void     __set_PSP          ( uint32_t value )  { cmsisHost_CoreRegs.Psp       = value; }
uint32_t __get_MSP          ( void )            { return ( cmsisHost_CoreRegs.Msp ); }
void     __set_MSP          ( uint32_t value )  { cmsisHost_CoreRegs.Msp       = value; }
uint32_t __get_PSPLIM       ( void )            { return ( cmsisHost_CoreRegs.PspLim ); }
void     __set_PSPLIM       ( uint32_t value )  { cmsisHost_CoreRegs.PspLim    = value; }
uint32_t __get_MSPLIM       ( void )            { return ( cmsisHost_CoreRegs.MspLim ); }
void     __set_MSPLIM       ( uint32_t value )  { cmsisHost_CoreRegs.MspLim    = value; }
uint32_t __get_FPSCR        ( void )            { return ( cmsisHost_CoreRegs.Fpscr ); }
void     __set_FPSCR        ( uint32_t fpscr )  { cmsisHost_CoreRegs.Fpscr     = fpscr; }


/**
 * \brief Raises BASEPRI only if the new value increases priority masking.
 *
 * \param basePri [in]: Required BASEPRI value
 */
void __set_BASEPRI_MAX( uint32_t basePri )
{
    const uint32_t newBasePri = basePri & CMSISHOST_BASEPRI_MASK;

    if( ( 0u != newBasePri ) &&
        ( ( 0u == cmsisHost_CoreRegs.BasePri ) || ( newBasePri < cmsisHost_CoreRegs.BasePri ) ) )
    {
        cmsisHost_CoreRegs.BasePri = newBasePri;
    }
    else
    {
        /* Masking is not increased */
    }
}

/* ========================== DATA PROCESSING =============================== */

uint8_t __CLZ( uint32_t value )
{
    uint8_t retVal = (uint8_t)CMSISHOST_WORD_BITS;

    if( 0u != value )
    {
        retVal = (uint8_t)__builtin_clz( value );
    }
    else
    {
        retVal = (uint8_t)CMSISHOST_WORD_BITS;
    }

    return ( retVal );
}


uint32_t __RBIT( uint32_t value )
{
    uint32_t retVal = 0u;

    for( uint32_t bitIdx = 0u; CMSISHOST_WORD_BITS > bitIdx; bitIdx++ )
    {
        retVal = ( retVal << 1u ) | ( ( value >> bitIdx ) & 1u );
    }

    return ( retVal );
}


uint32_t __REV  ( uint32_t value )              { return ( __builtin_bswap32( value ) ); }
uint32_t __REV16( uint32_t value )              { return ( ( ( value & 0x00FF00FFu ) << 8u ) | ( ( value >> 8u ) & 0x00FF00FFu ) ); }
int16_t  __REVSH( int16_t value )               { return ( (int16_t)__builtin_bswap16( (uint16_t)value ) ); }


uint32_t __ROR( uint32_t op1, uint32_t op2 )
{
    uint32_t       retVal = op1;
    const uint32_t shift  = op2 % CMSISHOST_WORD_BITS;

    if( 0u != shift )
    {
        retVal = ( op1 >> shift ) | ( op1 << ( CMSISHOST_WORD_BITS - shift ) );
    }
    else
    {
        retVal = op1;
    }

    return ( retVal );
}

/* ========================== EXCLUSIVE ACCESS ============================== */

uint8_t  __LDREXB( volatile uint8_t  *addr )                    { return ( *addr ); }
uint16_t __LDREXH( volatile uint16_t *addr )                    { return ( *addr ); }
uint32_t __LDREXW( volatile uint32_t *addr )                    { return ( *addr ); }
uint32_t __STREXB( uint8_t  value, volatile uint8_t  *addr )    { *addr = value; return ( 0u ); }
uint32_t __STREXH( uint16_t value, volatile uint16_t *addr )    { *addr = value; return ( 0u ); }
uint32_t __STREXW( uint32_t value, volatile uint32_t *addr )    { *addr = value; return ( 0u ); }
void     __CLREX ( void )                                       { }
