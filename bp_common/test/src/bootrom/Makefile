
RISCV_GCC = $(CROSS_COMPILE)gcc -fPIC -march=rv64im -mabi=lp64 -mcmodel=medany -static -nostdlib -nostartfiles

.DEFAULT: all

all: clean build

clean:
	rm -f bootrom.riscv *.bin *.out

build:
	$(RISCV_GCC) bootrom.S -o bootrom.riscv -Tlink.ld -static -Wl,--no-gc-sections