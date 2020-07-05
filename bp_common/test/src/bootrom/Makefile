
RISCV_GCC = $(CROSS_COMPILE)gcc -fPIC -march=rv64im -mabi=lp64 -mcmodel=medany -static -nostdlib -nostartfiles

.DEFAULT: all

all: clean build

clean:
	rm -f bootrom.riscv *.bin *.out

build:
	$(PYTHON)  ascii2bin.py -i $(BP_ME_DIR)/src/asm/roms/$(COH_PROTO).mem -o cce_ucode.out
	xxd -r -p cce_ucode.out > cce_ucode.bin
	$(RISCV_GCC) bootrom.S -o bootrom.riscv -Tlink.ld -static -Wl,--no-gc-sections
