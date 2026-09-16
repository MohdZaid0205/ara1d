#include "rvv_test_common.h"

extern void blend_mock_r(uint8_t *dst, int32_t dst_stride, const uint8_t *tmp,
                          int w, int h, const uint8_t *mask);

#define BLEND_PX(a, b, m) ((uint8_t)((((a) * (64 - (m))) + ((b) * (m)) + 32) >> 6))

void blend_mock_c(uint8_t *dst, int32_t dst_stride, const uint8_t *tmp,
                   int w, int h, const uint8_t *mask)
{
    do {
        for (int x = 0; x < w; x++)
            dst[x] = BLEND_PX(dst[x], tmp[x], mask[x]);
        dst += dst_stride;
        tmp += w;
        mask += w;
    } while (--h);
}

#define MAX_DIM 64
static uint8_t dst_c_buf[MAX_DIM * MAX_DIM];
static uint8_t dst_r_buf[MAX_DIM * MAX_DIM];
static uint8_t tmp_buf[MAX_DIM * MAX_DIM];
static uint8_t mask_buf[MAX_DIM * MAX_DIM];

/* mask ramps across 0..64 (dav1d's valid blend-mask range) so the blend
 * genuinely mixes dst/tmp with varying weight per pixel. */
static void init_inputs(int n)
{
    for (int i = 0; i < n; i++) {
        tmp_buf[i] = (uint8_t)(60 + (i * 3) % 180);
        int m = i % 65;
        mask_buf[i] = (uint8_t)m;
    }
}

int main(void)
{
    rvv_print_title("BLEND");
    rvv_print_header();

    /* width must be a power of two (drives the computed vsetvl), height
     * must be even (the asm processes 2 rows/iteration) - all satisfied
     * by every size below. */
    int sizes[] = {4, 8, 16, 32, 64};
    int num_sizes = sizeof(sizes) / sizeof(sizes[0]);
    int num_failed = 0;
    int num_cases = 0;

    for (int wi = 0; wi < num_sizes; wi++) {
        for (int hi = 0; hi < num_sizes; hi++) {
            int w = sizes[wi];
            int h = sizes[hi];
            int stride = w;

            init_inputs(w * h);
            for (int k = 0; k < stride * h; k++) {
                dst_c_buf[k] = 180;   /* distinct base value the blend mixes away from */
                dst_r_buf[k] = 180;
            }

            uint64_t start_c = rvv_read_cycles();
            blend_mock_c(dst_c_buf, stride, tmp_buf, w, h, mask_buf);
            uint64_t cycles_c = rvv_read_cycles() - start_c;

            uint64_t start_r = rvv_read_cycles();
            blend_mock_r(dst_r_buf, stride, tmp_buf, w, h, mask_buf);
            uint64_t cycles_r = rvv_read_cycles() - start_r;

            int failed = rvv_compare_u8(dst_c_buf, dst_r_buf, stride * h);
            num_failed += failed;
            num_cases++;

            rvv_print_row(w, h, cycles_c, cycles_r, failed);
if (failed && num_failed == 1) {          /* only the first failing case */
    printf("first fail: w=%d h=%d\n C:", w, h);
    for (int k = 0; k < 16; k++) printf(" %d", dst_c_buf[k]);
    printf("\n R:");
    for (int k = 0; k < 16; k++) printf(" %d", dst_r_buf[k]);
    printf("\n");
}
        }
    }

    rvv_print_summary(num_cases, num_failed);
    return num_failed;
}
