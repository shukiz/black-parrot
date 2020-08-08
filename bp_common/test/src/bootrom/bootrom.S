#define DRAM_BASE_ADDR    0x80000000
#define SD_CARD_BASE_ADDR 0x00500000

#ifndef NUM_CORES
  #define NUM_CORES 1
#endif

#ifndef DOMAIN_MASK
  #define DOMAIN_MASK 1
#endif

#ifndef SAC_MASK
  #define SAC_MASK 0
#endif

#define CCE_PC_WIDTH 8
#define NUM_CCE_INSTR (1 << CCE_PC_WIDTH)

#define CFG_DOMAIN_MASK_ADDR    0x00200009
#define CFG_SAC_MASK_ADDR       0x0020000a
#define CFG_DCACHE_MODE_ADDR    0x00200043
#define CFG_ICACHE_MODE_ADDR    0x00200022
#define CFG_CCE_MODE_ADDR       0x00200081
#define CFG_CCE_UCODE_BASE_ADDR 0x00208000

.section .text.start
.globl _start
_start:
    li x0, 0
    li x1, 0
    li x2, 0
    li x3, 0
    li x4, 0
    li x5, 0
    li x6, 0
    li x7, 0
    li x8, 0
    li x9, 0
    li x10, 0
    li x11, 0
    li x12, 0
    li x13, 0
    li x14, 0
    li x15, 0
    li x16, 0
    li x17, 0
    li x18, 0
    li x19, 0
    li x20, 0
    li x21, 0
    li x22, 0
    li x23, 0
    li x24, 0
    li x25, 0
    li x26, 0
    li x27, 0
    li x28, 0
    li x29, 0
    li x30, 0
    li x31, 0

    # Enable FPU
    li x31, 0x2000
    csrs mstatus, x31
    
    /* Copy CCE uCode */
    li t0, CFG_CCE_UCODE_BASE_ADDR
    li t1, NUM_CCE_INSTR
    la t2, SD_CARD_BASE_ADDR
    li t3, 0
loop:
    ld t4, 0(t2)
    sd t4, 0(t0)
    addi t2, t2, 8
    addi t0, t0, 1
    addi t1, t1, -1
    bnez t1, loop

    /* Enable Domains*/
    li t0, DOMAIN_MASK
    li t1, CFG_DOMAIN_MASK_ADDR
    sd t0, 0(t1)

    /* Enable SAC */
    li t0, SAC_MASK
    li t1, CFG_SAC_MASK_ADDR
    sd t0, 0(t1)

    /* Write D$ mode */
    li t0, 1
    li t1, CFG_DCACHE_MODE_ADDR
    sd t0, 0(t1)

    /* Write I$ mode */
    li t1, CFG_ICACHE_MODE_ADDR
    sd t0, 0(t1)

    /* Write CCE mode */
    li t1, CFG_CCE_MODE_ADDR 
    sd t0, 0(t1)

    /* Load program from memory */

    li x31, DRAM_BASE_ADDR
    csrw dpc, x31
    csrwi dcsr, 0x3
    dret
halt:
    j halt
