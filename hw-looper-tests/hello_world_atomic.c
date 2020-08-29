#include <stdint.h>
#include "bp_utils.h"

/* CHANGEME for the number of cores under test */
#define NUM_CORES 4
volatile uint64_t core_num = 0;
volatile uint64_t barrier = 0;

/* Base address of the Multicore HW Looper */
#define MULTICORE_HW_LOOPER_BASE_ADDRESS 0x00500000

/* HW Looper active indication */
#define CONTROL_HW_LOOPER_ACTIVE 0x1

/* Number of iterations in multi-core loop */
#define GLOBAL_LOOP_NUM_ITERATIONS 100000

/* Use HW LOOPER enable */
#define ITERATE_MULTICORE_USING_HW_LOOPER_ENABLE

typedef struct tag_multicore_hw_looper_regs {
	/* control register */
	uint64_t control;

	/* global_start_index register */
	uint64_t global_start_index;

	/* global_end_index register */
	uint64_t global_end_index;

	/* next_allocation_get register */
	uint64_t next_alloc_start_index;

	/* allocation_size register */
	uint64_t allocation_size;

} multicore_hw_looper_regs_t;


/********************** printf integration - START ***********************/
#include <stdint.h>
#include <string.h>
#include <stdarg.h>
#include <stdio.h>
#include <limits.h>

#define N 8

int arr[N];
uint64_t* putchar_ptr = (uint64_t*)0x00101000;
uint64_t* finish_ptr  = (uint64_t*)0x00102000;

#define static_assert(cond) switch(0) { case 0: case !!(long)(cond): ; }

#undef putchar
int putchar(int ch)
{
  *putchar_ptr = ch;
  return 0;
}

static inline void printnum(void (*putch)(int, void**), void **putdat,
                    unsigned long long num, unsigned base, int width, int padc)
{
  unsigned digs[sizeof(num)*CHAR_BIT];
  int pos = 0;

  while (1)
  {
    digs[pos++] = num % base;
    if (num < base)
      break;
    num /= base;
  }

  while (width-- > pos)
    putch(padc, putdat);

  while (pos-- > 0)
    putch(digs[pos] + (digs[pos] >= 10 ? 'a' - 10 : '0'), putdat);
}

static unsigned long long getuint(va_list *ap, int lflag)
{
  if (lflag >= 2)
    return va_arg(*ap, unsigned long long);
  else if (lflag)
    return va_arg(*ap, unsigned long);
  else
    return va_arg(*ap, unsigned int);
}

static long long getint(va_list *ap, int lflag)
{
  if (lflag >= 2)
    return va_arg(*ap, long long);
  else if (lflag)
    return va_arg(*ap, long);
  else
    return va_arg(*ap, int);
}

static void vprintfmt(void (*putch)(int, void**), void **putdat, const char *fmt, va_list ap)
{
  register const char* p;
  const char* last_fmt;
  register int ch, err;
  unsigned long long num;
  int base, lflag, width, precision, altflag;
  char padc;

  while (1) {
    while ((ch = *(unsigned char *) fmt) != '%') {
      if (ch == '\0')
        return;
      fmt++;
      putch(ch, putdat);
    }
    fmt++;

    // Process a %-escape sequence
    last_fmt = fmt;
    padc = ' ';
    width = -1;
    precision = -1;
    lflag = 0;
    altflag = 0;
  reswitch:
    switch (ch = *(unsigned char *) fmt++) {

    // flag to pad on the right
    case '-':
      padc = '-';
      goto reswitch;

    // flag to pad with 0's instead of spaces
    case '0':
      padc = '0';
      goto reswitch;

    // width field
    case '1':
    case '2':
    case '3':
    case '4':
    case '5':
    case '6':
    case '7':
    case '8':
    case '9':
      for (precision = 0; ; ++fmt) {
        precision = precision * 10 + ch - '0';
        ch = *fmt;
        if (ch < '0' || ch > '9')
          break;
      }
      goto process_precision;

    case '*':
      precision = va_arg(ap, int);
      goto process_precision;

    case '.':
      if (width < 0)
        width = 0;
      goto reswitch;

    case '#':
      altflag = 1;
      goto reswitch;

    process_precision:
      if (width < 0)
        width = precision, precision = -1;
      goto reswitch;

    // long flag (doubled for long long)
    case 'l':
      lflag++;
      goto reswitch;

    // character
    case 'c':
      putch(va_arg(ap, int), putdat);
      break;

    // string
    case 's':
      if ((p = va_arg(ap, char *)) == NULL)
        p = "(null)";
      if (width > 0 && padc != '-')
        for (width -= strnlen(p, precision); width > 0; width--)
          putch(padc, putdat);
      for (; (ch = *p) != '\0' && (precision < 0 || --precision >= 0); width--) {
        putch(ch, putdat);
        p++;
      }
      for (; width > 0; width--)
        putch(' ', putdat);
      break;

    // (signed) decimal
    case 'd':
      num = getint(&ap, lflag);
      if ((long long) num < 0) {
        putch('-', putdat);
        num = -(long long) num;
      }
      base = 10;
      goto signed_number;

    // unsigned decimal
    case 'u':
      base = 10;
      goto unsigned_number;

    // (unsigned) octal
    case 'o':
      // should do something with padding so it's always 3 octits
      base = 8;
      goto unsigned_number;

    // pointer
    case 'p':
      static_assert(sizeof(long) == sizeof(void*));
      lflag = 1;
      putch('0', putdat);
      putch('x', putdat);
      /* fall through to 'x' */

    // (unsigned) hexadecimal
    case 'x':
      base = 16;
    unsigned_number:
      num = getuint(&ap, lflag);
    signed_number:
      printnum(putch, putdat, num, base, width, padc);
      break;

    // escaped '%' character
    case '%':
      putch(ch, putdat);
      break;

    // unrecognized escape sequence - just print it literally
    default:
      putch('%', putdat);
      fmt = last_fmt;
      break;
    }
  }
}

int printf2(const char* fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);

  vprintfmt((void*)putchar, 0, fmt, ap);

  va_end(ap);
  return 0; // incorrect return value, but who cares, anyway?
}

/********************** printf integration - end ***********************/

int main(int argc, char** argv) {
    uint64_t core_id;
    uint64_t atomic_inc = 1;
    uint64_t atomic_result = 0;
    volatile multicore_hw_looper_regs_t *mcore_looper_regs =
    	MULTICORE_HW_LOOPER_BASE_ADDRESS;
    volatile uint64_t *mtime_reg_64     = 0x0030bff8;

    volatile uint64_t start_i;
    volatile uint64_t end_i;
    volatile uint64_t atomic_read_val;
    volatile uint64_t i;

    __asm__ volatile("csrr %0, mhartid": "=r"(core_id): :);

#if 0
    // synchronize with other cores and wait until it is this core's turn
    while (core_num != core_id) { }
    
    // print out this core id
    bp_hprint(core_id);

    // increment atomic counter
    __asm__ volatile("amoadd.d %0, %2, (%1)": "=r"(atomic_result) 
                                            : "r"(&core_num), "r"(atomic_inc)
                                            :);
//#if 0
    bp_barrier_end(&barrier, NUM_CORES);
//#else
    if (core_id != 0) {
    	bp_finish(core_id);
    	return 0;
    }
#endif

#if 0
    volatile uint32_t *mtime_reg_32     = 0x0030bff8;
    volatile uint32_t *test_reg_32     =  0x0030b008;

    printf2("test_reg_32 val read = %lx\n", *test_reg_32);
    *test_reg_32 = 0x111FF;
    printf2("test_reg_32 val read = %lx after write\n", *test_reg_32);


    printf2("mtime_reg 64 = %lx\n", *mtime_reg_64);
    printf2("mtime_reg 32 = %x\n", *mtime_reg_32);
#endif

    if (core_id == 0) {
		mcore_looper_regs->global_start_index = 0;
		mcore_looper_regs->global_end_index = GLOBAL_LOOP_NUM_ITERATIONS;
		mcore_looper_regs->allocation_size = 1024;

		/* Reset start index */
		mcore_looper_regs->next_alloc_start_index = 0;

		/* Indicate ACTIVE looper to other cores */
		mcore_looper_regs->control = CONTROL_HW_LOOPER_ACTIVE;
    }
    else {
    	/* Wait for work to be initiated by core#0 (cores#1,2,3) */
    	do {

    	} while ((mcore_looper_regs->control & CONTROL_HW_LOOPER_ACTIVE) == 0);
    }

    /* At this point, all 4 cores are synchronized on the work and start */

#if defined(ITERATE_MULTICORE_USING_HW_LOOPER_ENABLE)
	/* Start multi-core looper */
	while (end_i < GLOBAL_LOOP_NUM_ITERATIONS) {
		atomic_read_val = mcore_looper_regs->next_alloc_start_index;
		start_i = atomic_read_val & 0xffffffff;
		end_i = atomic_read_val >> 32;
		for (i = start_i; i < end_i; i++) {
			volatile uint64_t z = 1;
		}
	}
#else
	/* Start multi-core looper */
	start_i = core_id * (GLOBAL_LOOP_NUM_ITERATIONS / NUM_CORES);
	end_i = (core_id+1) * (GLOBAL_LOOP_NUM_ITERATIONS / NUM_CORES);
	for (i = start_i; i < end_i; i++) {
		volatile uint64_t z = 1;
	}
#endif

#if 0
    if (core_id == 0) {
		/* HW-Looper test registers */
		printf2("LOOPER registers BEFORE:\n");
		printf2("0x%lx, 0x%lx, 0x%lx, 0x%lx, 0x%lx\n\n",
			mcore_looper_regs->control,
			mcore_looper_regs->global_start_index,
			mcore_looper_regs->global_end_index,
			mcore_looper_regs->next_alloc_start_index,
			mcore_looper_regs->allocation_size);

		printf2("0x%lx, 0x%lx, 0x%lx, 0x%lx, 0x%lx\n\n",
			mcore_looper_regs->control,
			mcore_looper_regs->global_start_index,
			mcore_looper_regs->global_end_index,
			mcore_looper_regs->next_alloc_start_index,
			mcore_looper_regs->allocation_size);

#if 0
		mcore_looper_regs->control            = 0x12345678;
		mcore_looper_regs->global_start_index = 0x78654321;
		mcore_looper_regs->global_end_index   = 0x86543217;
		mcore_looper_regs->next_alloc_start_index = 0x65432178;
		mcore_looper_regs->allocation_size    = 0x54321786;
#endif
		printf2("LOOPER registers AFTER:\n");
		printf2("0x%lx, 0x%lx, 0x%lx, 0x%lx, 0x%lx\n\n",
			mcore_looper_regs->control,
			mcore_looper_regs->global_start_index,
			mcore_looper_regs->global_end_index,
			mcore_looper_regs->next_alloc_start_index,
			mcore_looper_regs->allocation_size);
    }
#endif

    if (core_id == 0) {
    	printf2("Core#%lu finished time_ticks=%lx\n", core_id, *mtime_reg_64);
    	printf2("The last start_i=%lu, end_i=%lu\n", start_i, end_i);
    }

    /* Finish work, get dump */
	bp_finish(0);

    return 0;
}

