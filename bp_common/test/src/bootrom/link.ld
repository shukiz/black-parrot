SECTIONS
{
    . = 0x0000;
    .text.start : { *(.text.start) }
    .rodata.ucode : { *(.rodata.ucode) }
}
