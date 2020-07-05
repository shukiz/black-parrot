RISCV_GCC = $(CROSS_COMPILE)gcc -fPIC -march=rv64im -mabi=lp64 -mcmodel=medany -static -nostdlib -nostartfiles

.DEFAULT: all

all: clean build

clean:
	rm -f bootrom.riscv cce_ucode.bin

build:
	cp $(BP_ME_DIR)/src/asm/roms/$(COH_PROTO).bin cce_ucode.bin
	$(RISCV_GCC) bootrom.S -o bootrom.riscv -Tlink.ld -static -Wl,--no-gc-sections