#include "rvv_test_common.h"

extern void ipred_h_mock_r(uint8_t *dst, int32_t stride,
                            const uint8_t *topleft, int width, int height);

void ipred_h_mock_c(uint8_t *dst, int32_t stride,
                     const uint8_t *topleft, int width, int height)
{
    for (int y = 0; y < height; y++) {
        uint8_t v = topleft[-(1 + y)];
        for (int x = 0; x < width; x++)
            dst[x] = v;
        dst += stride;
    }
}

#define MAX_DIM 64
static uint8_t topleft_buf[MAX_DIM];   /* topleft[-height .. -1], topleft = buf + height */
static uint8_t dst_c_buf[MAX_DIM * MAX_DIM];
static uint8_t dst_r_buf[MAX_DIM * MAX_DIM];

/* Monotonic-but-not-flat ramp down the left column so every output row
 * gets a distinct, checkable value. */
static void init_topleft(int height)
{
    for (int i = 0; i < height; i++)
        topleft_buf[i] = (uint8_t)(30 + i * 11);
}

int main(void)
{
    rvv_print_title("IPRED_H");
    rvv_print_header();

    /* ipred_h_8bpc_rvv's fast/general paths both assume height is a
     * multiple of 4 (dav1d never calls it otherwise) - all standard
     * block sizes below satisfy that. Width is swept independently of
     * height since the asm handles any power-of-two width via its
     * m1/m2/m4 fallback chain. */
    int sizes[] = {4, 8, 16, 32, 64};
    int num_sizes = sizeof(sizes) / sizeof(sizes[0]);
    int num_failed = 0;
    int num_cases = 0;

    for (int wi = 0; wi < num_sizes; wi++) {
        for (int hi = 0; hi < num_sizes; hi++) {
            int w = sizes[wi];
            int h = sizes[hi];
            int stride = w;

            init_topleft(h);
            const uint8_t *topleft = topleft_buf + h;

            rvv_zero_u8(dst_c_buf, stride * h);
            rvv_zero_u8(dst_r_buf, stride * h);

            uint64_t start_c = rvv_read_cycles();
            ipred_h_mock_c(dst_c_buf, stride, topleft, w, h);
            uint64_t cycles_c = rvv_read_cycles() - start_c;

            uint64_t start_r = rvv_read_cycles();
            ipred_h_mock_r(dst_r_buf, stride, topleft, w, h);
            uint64_t cycles_r = rvv_read_cycles() - start_r;

            int failed = rvv_compare_u8(dst_c_buf, dst_r_buf, stride * h);
            num_failed += failed;
            num_cases++;

            rvv_print_row(w, h, cycles_c, cycles_r, failed);
        }
    }

    rvv_print_summary(num_cases, num_failed);
    return num_failed;
}
