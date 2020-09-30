#include <stdint.h>
#include "bp_utils.h"
#include <stdint.h>
#include <string.h>
#include <stdarg.h>
#include <stdio.h>
#include <limits.h>

#define MAX(a,b) ((a) > (b) ? (a) : (b))
#define MIN(a,b) ((a) < (b) ? (a) : (b))

/* CHANGEME for the number of cores under test */
#define NUM_CORES 4
volatile uint64_t core_num = 0;
volatile uint64_t barrier = 0;

/* Enable printing the allocations */
//#define HW_LOOPER_ALLOCATIONS_VERBOSE_MODE_ENABLE

/* Base address of the Multicore HW Looper */
#define MULTICORE_HW_LOOPER_BASE_ADDRESS 0x00500000

/* HW Looper active indication */
#define CONTROL_HW_LOOPER_ACTIVE 0x1

/* Number of iterations in multi-core loop */
#define GLOBAL_LOOP_NUM_ITERATIONS 1000

/* Use HW LOOPER enable */
#define ITERATE_MULTICORE_USING_HW_LOOPER_ENABLE

/* Perform random delay workload */
#define RANDOM_DELAY_WORKLOAD_ENABLE

/* Perform convolution - 1-Dimension */
//#define CONVOLUTION_1D_WORKLOAD_ENABLE

/* Perform convolution - 2-Dimensions */
//#define CONVOLUTION_2D_WORKLOAD_ENABLE

#if defined(RANDOM_DELAY_WORKLOAD_ENABLE)
#define RANDOM_DELAY_ALLOCATION_SIZE 2
#define RANDOM_DELAY_SIZE 128

#define WORKLOAD_SIZE_FROM_INDEX(iDX) (1 + ( ((((iDX<<1)+0x3E)>>2)+3) & 0x3FF))

#endif

#if defined(CONVOLUTION_1D_WORKLOAD_ENABLE)
/* Number of elements in filter buffer */
#define CONVOLUTION_SIZE_M			(16)
/* Allocation size per request */
#define CONVOLUTION_ALLOCATION_SIZE_M (CONVOLUTION_SIZE_M*8)
/* Number of elements in input buffer */
#define CONVOLUTION_SIZE_N			(CONVOLUTION_ALLOCATION_SIZE_M * 16) // (CONVOLUTION_ALLOCATION_SIZE_M * 16)
#endif

#if defined(CONVOLUTION_2D_WORKLOAD_ENABLE)
/* Number of elements in filter buffer */
#define CONVOLUTION_SIZE_M			(4) // M x M
/* Number of elements in input buffer */
#define CONVOLUTION_SIZE_N			(16) // N x N
#endif

volatile uint64_t timing_cpu[NUM_CORES];
volatile uint64_t cpu_finished_processing_ind;

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

/* Global pointer to mcore_looper registers */
volatile multicore_hw_looper_regs_t *mcore_looper_regs =
	MULTICORE_HW_LOOPER_BASE_ADDRESS;

uint32_t n_iterations_total_core[NUM_CORES];

/********************** printf integration - START ***********************/
#define NN 8

int arr[NN];
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



#if defined(CONVOLUTION_1D_WORKLOAD_ENABLE)
/* Buffers for convolution */
int8_t g_convolution_1d_filter[CONVOLUTION_SIZE_M];
int8_t g_convolution_1d_input[CONVOLUTION_SIZE_N];
int16_t g_convolution_1d_output[CONVOLUTION_SIZE_N + CONVOLUTION_SIZE_M];
#endif /* CONVOLUTION_1D_WORKLOAD_ENABLE */

static inline void
conv_1d(int8_t *filter_buf, size_t M, int8_t *input_buf, size_t N,
		int16_t *output_buf)
{
	uint32_t i;
	uint32_t j;
	int16_t temp;

	for (i = 0; i < N; i++) {
		temp = 0;
		for (j = 0; j < M; j++) {
			temp += (input_buf[i - j] * filter_buf[j]);
		}
		*output_buf = temp;
		output_buf++;
	}
}

#if defined(HW_LOOPER_ALLOCATIONS_VERBOSE_MODE_ENABLE)
/* Allocations logging per core */
uint32_t allocations_start[NUM_CORES][512];
uint32_t allocations_end[NUM_CORES][512];

void
hw_looper_debug_allocations_print(void)
{
	uint32_t i;
	uint32_t j;

	volatile uint32_t delay = 1000;
	while (delay > 0) {
		delay--;
	}
	for (i = 0; i < 10; i++) {
		for (j = 0; j < NUM_CORES; j++) {
			printf2("core#%u: allocations_start=%u, allocations_end=%u\n",
					j, allocations_start[j][i], allocations_end[j][i]);
		}
	}
}
#endif /* HW_LOOPER_ALLOCATIONS_VERBOSE_MODE_ENABLE */

void
conv_1d_parallel_with_hw_looper(int8_t *filter_buf, size_t M,
		int8_t *input_buf, size_t N,
		int16_t *output_buf,
		uint64_t core_id,
		uint32_t *n_allocations)
{
	register uint64_t atomic_read_val;
	register uint32_t start_index = 0;
	register uint32_t end_index = 0;
	uint32_t size_N;
	uint32_t allocs = 0;
	uint32_t threshold = (((N - start_index)*7)/8);
	int allocation_updated = 0;

	/* Start multi-core looper */
#if defined(HW_LOOPER_ALLOCATIONS_VERBOSE_MODE_ENABLE)
	n_iterations_total_core[core_id] = 0;
#endif
	while (end_index < N) {
		atomic_read_val = mcore_looper_regs->next_alloc_start_index;
		start_index = (atomic_read_val & 0xffffffff); //MAX((atomic_read_val & 0xffffffff), M);
		end_index = (atomic_read_val >> 32); //MIN((atomic_read_val >> 32), N);
		size_N = end_index - start_index;

#if defined(HW_LOOPER_ALLOCATIONS_VERBOSE_MODE_ENABLE)
		// debug
		allocations_start[core_id][allocs] = start_index;
		allocations_end[core_id][allocs] = end_index;
		allocs++;
		n_iterations_total_core[core_id] += size_N;
#endif

		/* Do convolution */
		conv_1d(filter_buf, M,
				&input_buf[start_index], size_N,
				&output_buf[start_index]);
	}

	*n_allocations = allocs;
}

void
conv_1d_parallel_without_hw_looper(int8_t *filter_buf, size_t M, int8_t *input_buf, size_t N,
		int16_t *output_buf, uint64_t core_id)
{
	uint32_t start_index = MAX(core_id*(N / NUM_CORES), M);
	uint32_t end_index = MIN( (core_id+1)*(N / NUM_CORES), N);
	size_t size_N = end_index - start_index;
	conv_1d(filter_buf, M,
			&input_buf[start_index], size_N,
			&output_buf[start_index]);
}


#if defined(CONVOLUTION_2D_WORKLOAD_ENABLE)
/* Buffers for convolution */
int8_t g_convolution_2d_filter[CONVOLUTION_SIZE_M * CONVOLUTION_SIZE_M];
int8_t g_convolution_2d_input[CONVOLUTION_SIZE_N * CONVOLUTION_SIZE_N];
// need smaller buf but it's ok to define a larger buffer than really needed.
int16_t g_convolution_2d_output[CONVOLUTION_SIZE_N * CONVOLUTION_SIZE_N];
#endif /* CONVOLUTION_2D_WORKLOAD_ENABLE */

/*
  filter_buf is M x M.
  input_buf is N x N.
  output_buf is just a pointer to one result of a single iteration.
*/
static inline void
conv_2d(int8_t *filter_buf, size_t M, int8_t *input_buf, size_t N,
		int16_t *output_buf)
{
	uint32_t i;
	uint32_t j;
	uint32_t offset_row_filter = 0;
	uint32_t offset_row_data = 0;
	int16_t conv_result = 0;

	for (i = 0; i < M; i++) { // rows
		for (j = 0; j < M; j++) { // columns
			conv_result +=
				(input_buf[j + offset_row_data] * filter_buf[j + offset_row_filter]);
		}
		offset_row_filter += M;
		offset_row_data += N;
	}

	*output_buf = conv_result;
}

void
conv_2d_parallel_with_hw_looper(int8_t *filter_buf, size_t M,
		int8_t *input_buf, size_t N,
		int16_t *output_buf,
		uint64_t core_id)
{
	uint32_t i;
	uint32_t j;
	uint32_t offset_row_filter = 0;
	uint32_t offset_row_data = 0;
	register uint64_t atomic_read_val;
	register uint32_t start_index = 0;
	register uint32_t end_index = 0;
	uint32_t size_N;
	int16_t conv_result = 0;
	uint64_t max_index = N * N;

	while (end_index < max_index) {
		atomic_read_val = mcore_looper_regs->next_alloc_start_index;
		start_index = (atomic_read_val & 0xffffffff);
		end_index = (atomic_read_val >> 32);
		size_N = end_index - start_index;

		for (i = start_index; i < end_index; i++) {
			conv_2d(filter_buf, M, &input_buf[i], N,
					&output_buf[i]);
		}

	}
}


void
conv_2d_parallel_without_hw_looper(int8_t *filter_buf, size_t M,
		int8_t *input_buf, size_t N,
		int16_t *output_buf,
		uint64_t core_id)
{
	uint32_t i;
	uint32_t size_N;
	int16_t conv_result = 0;
	uint64_t max_index = N * N;

	register uint32_t start_index = core_id*(max_index / NUM_CORES);
	register uint32_t end_index = (core_id+1)*(max_index / NUM_CORES);

	for (i = start_index; i < end_index; i++) {
		conv_2d(filter_buf, M, &input_buf[i], N,
				&output_buf[i]);
	}
}

static inline void
random_delay_workload_generate(uint32_t iterations)
{
	volatile uint32_t i;
	volatile uint32_t x;
	volatile uint32_t *y = &x;

	for (i = 0; i < iterations; i++) {
		*y = i;
	}

}

void
random_delay_workload_with_hw_looper(size_t total_size,
		size_t allocation_size)
{
	uint32_t i;
	uint32_t j;
	uint32_t offset_row_filter = 0;
	uint32_t offset_row_data = 0;
	register uint64_t atomic_read_val;
	register uint32_t start_index = 0;
	register uint32_t end_index = 0;
	//uint32_t size_N;
	int16_t conv_result = 0;
	uint64_t max_index = total_size;

	while (end_index < max_index) {
		atomic_read_val = mcore_looper_regs->next_alloc_start_index;
		start_index = (atomic_read_val & 0xffffffff);
		end_index = (atomic_read_val >> 32);
		//size_N = end_index - start_index;

		for (i = start_index; i < end_index; i++) {
			random_delay_workload_generate(WORKLOAD_SIZE_FROM_INDEX(i));
		}
	}
}

void
random_delay_workload_without_hw_looper(size_t total_size,
		size_t allocation_size, uint64_t core_id)
{
	uint32_t i;
	uint32_t size_N;
	int16_t conv_result = 0;
	uint64_t max_index = total_size;

	register uint32_t start_index = core_id*(max_index / NUM_CORES);
	register uint32_t end_index = (core_id+1)*(max_index / NUM_CORES);

	for (i = start_index; i < end_index; i++) {
		random_delay_workload_generate(WORKLOAD_SIZE_FROM_INDEX(i));
	}
}

uint32_t core_print_feedback = 0;

int main(int argc, char** argv) {
    uint64_t core_id;
    uint64_t atomic_inc = 1;
    uint64_t atomic_result = 0;
    uint64_t time_ticks_start;
    uint64_t time_ticks_end;
    uint32_t n_allocations;

    volatile uint64_t *mtime_reg_64     = 0x0030bff8;

    volatile uint64_t start_i;
    volatile uint64_t end_i;
    volatile uint64_t atomic_read_val;
    volatile uint64_t i;

    cpu_finished_processing_ind = 0;

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

    if (core_id == 0) {
#if defined(RANDOM_DELAY_WORKLOAD_ENABLE)
		mcore_looper_regs->global_start_index = 0;

		/* Reset start index */
		/* Workaround for first assignment into next_alloc_start_index register */
		mcore_looper_regs->global_end_index = 0;
		mcore_looper_regs->allocation_size = 0;
		mcore_looper_regs->next_alloc_start_index = 0;
		mcore_looper_regs->allocation_size = RANDOM_DELAY_ALLOCATION_SIZE;
		mcore_looper_regs->global_end_index = RANDOM_DELAY_SIZE;

		/* Indicate ACTIVE looper to other cores */
		mcore_looper_regs->control = CONTROL_HW_LOOPER_ACTIVE;
#endif
#if defined(CONVOLUTION_1D_WORKLOAD_ENABLE)
		mcore_looper_regs->global_start_index = 0;

		/* Reset start index */
		/* Workaround for first assignment into next_alloc_start_index register */
		mcore_looper_regs->global_end_index = 0;
		mcore_looper_regs->allocation_size = 0;
		mcore_looper_regs->next_alloc_start_index = CONVOLUTION_SIZE_M;
		mcore_looper_regs->allocation_size = CONVOLUTION_ALLOCATION_SIZE_M;
		mcore_looper_regs->global_end_index = CONVOLUTION_SIZE_N;

		/* Indicate ACTIVE looper to other cores */
		mcore_looper_regs->control = CONTROL_HW_LOOPER_ACTIVE;
#endif
#if defined(CONVOLUTION_2D_WORKLOAD_ENABLE)
		mcore_looper_regs->global_start_index = 0;

		/* Reset start index */
		/* Workaround for first assignment into next_alloc_start_index register */
		mcore_looper_regs->global_end_index = 0;
		mcore_looper_regs->allocation_size = 0;
		mcore_looper_regs->next_alloc_start_index = 0;
		mcore_looper_regs->allocation_size = CONVOLUTION_SIZE_N/4;
		mcore_looper_regs->global_end_index = CONVOLUTION_SIZE_N * CONVOLUTION_SIZE_N;

		/* Indicate ACTIVE looper to other cores */
		mcore_looper_regs->control = CONTROL_HW_LOOPER_ACTIVE;
#endif
    }
    else {
    	/* Wait for work to be initiated by core#0 (cores#1,2,3) */
    	do {

    	} while ((mcore_looper_regs->control & CONTROL_HW_LOOPER_ACTIVE) == 0);
    }

    /* At this point, all 4 cores are synchronized on the work and start */
    time_ticks_start = *mtime_reg_64;
#if defined(RANDOM_DELAY_WORKLOAD_ENABLE)
#if defined(ITERATE_MULTICORE_USING_HW_LOOPER_ENABLE)
    random_delay_workload_with_hw_looper(RANDOM_DELAY_SIZE,
    		RANDOM_DELAY_ALLOCATION_SIZE);
#else
    random_delay_workload_without_hw_looper(RANDOM_DELAY_SIZE,
    		RANDOM_DELAY_ALLOCATION_SIZE, core_id);
#endif
#endif

#if defined(CONVOLUTION_2D_WORKLOAD_ENABLE)
#if defined(ITERATE_MULTICORE_USING_HW_LOOPER_ENABLE)
	conv_2d_parallel_with_hw_looper(g_convolution_2d_filter, CONVOLUTION_SIZE_M,
			g_convolution_2d_input, CONVOLUTION_SIZE_N, g_convolution_2d_output,
			core_id);

#else
	conv_2d_parallel_without_hw_looper(g_convolution_2d_filter, CONVOLUTION_SIZE_M,
			g_convolution_2d_input, CONVOLUTION_SIZE_N, g_convolution_2d_output, core_id);
#endif
#endif

#if defined(CONVOLUTION_1D_WORKLOAD_ENABLE)
#if defined(ITERATE_MULTICORE_USING_HW_LOOPER_ENABLE)
	conv_1d_parallel_with_hw_looper(g_convolution_1d_filter, CONVOLUTION_SIZE_M,
			g_convolution_1d_input, CONVOLUTION_SIZE_N, g_convolution_1d_output,
			core_id, &n_allocations);

#else
	conv_1d_parallel_without_hw_looper(g_convolution_1d_filter, CONVOLUTION_SIZE_M,
			g_convolution_1d_input, CONVOLUTION_SIZE_N, g_convolution_1d_output, core_id);
#endif
#endif /* CONVOLUTION_1D_WORKLOAD_ENABLE */

#if 0
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
#endif /* 0 */

    time_ticks_end = *mtime_reg_64;

    timing_cpu[core_id] = (time_ticks_end-time_ticks_start);

#if defined(HW_LOOPER_ALLOCATIONS_VERBOSE_MODE_ENABLE)
    printf2("\n");
   	printf2("Core#%lu finished time_ticks=%lx\n", core_id, (time_ticks_end-time_ticks_start));
    printf2("\n");

    if (core_id == 0) {
    	printf2("Core#%lu finished time_ticks=%lx\n", core_id, (time_ticks_end-time_ticks_start));
    	hw_looper_debug_allocations_print();
    	for (i = 0; i < NUM_CORES; i++) {
    		printf2("core#%lu: n_iterations_total_core = %u\n", i, n_iterations_total_core[i]);
    	}
    }
#endif


    while ((timing_cpu[0] == 0) || (timing_cpu[1] == 0) ||
    		(timing_cpu[2] == 0) || (timing_cpu[3] == 0) ) {
    }

    if (core_id == 0) {
		printf2("Timing: %lu %lu %lu %lu", timing_cpu[0],
				timing_cpu[1], timing_cpu[2], timing_cpu[3]);
    }
    /* Finish work, get dump */
	bp_finish(0);

    return 0;
}

