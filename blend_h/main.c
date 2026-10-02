#include "rvv_test_common.h"

extern void blend_h_mock_r(uint8_t *dst, int32_t dst_stride, const uint8_t *tmp,
                         int w, int h);

const uint8_t dav1d_obmc_masks[64] = {
    /* unused */
    0, 0,
    /* 2 */
    19, 0,
    /* 4 */
    25, 14, 5, 0,
    /* 8 */
    28, 22, 16, 11, 7, 3, 0, 0,
    /* 16 */
    30, 27, 24, 21, 18, 15, 12, 10, 8, 6, 4, 3, 0, 0, 0, 0,
    /* 32 */
    31, 29, 28, 26, 24, 23, 21, 20, 19, 17, 16, 14, 13, 12, 11, 9,
    8, 7, 6, 5, 4, 4, 3, 2, 0, 0, 0, 0, 0, 0, 0, 0
};

#define blend_px(a, b, m) ((uint8_t)((((a) * (64 - (m)) + (b) * (m)) + 32) >> 6))
void blend_h_mock_c(uint8_t *dst, int32_t dst_stride, const uint8_t *tmp,
                    int w, int h)
{
    const uint8_t *mask = &dav1d_obmc_masks[h];
    h = (h * 3) >> 2;
    do {
        const int m = *mask++;
        for (int x = 0; x < w; x++) {
            dst[x] = blend_px(dst[x], tmp[x], m);
        }
        dst += dst_stride;
        tmp += w;
    } while (--h);
}

#define MAX_DIM 128
#define MAX_ROWS 32
/* dst and tmp are w*h each (stride = w); the largest case is 128x32 for
 * blend_h and 32x128 for blend_v, both 4096 bytes. */
static uint8_t dst_init_buf[MAX_DIM * MAX_ROWS];
static uint8_t dst_c_buf[MAX_DIM * MAX_ROWS];
static uint8_t dst_r_buf[MAX_DIM * MAX_ROWS];
static uint8_t dst_w_buf[MAX_DIM * MAX_ROWS];    /* scratch for warm-up calls */
static uint8_t tmp_buf[MAX_DIM * MAX_ROWS];

static void init_inputs(int w, int h, int pattern)
{
    uint32_t s = 0x9E3779B9u ^ (uint32_t)(w * 131 + h);
    for (int i = 0; i < w * h; i++) {
        if (pattern) {
            dst_init_buf[i] = (i & 1) ? 255 : 0;
            tmp_buf[i]      = (i & 1) ? 0 : 255;
        } else {
            s ^= s << 13; s ^= s >> 17; s ^= s << 5;
            dst_init_buf[i] = (uint8_t)(s >> 24);
            s ^= s << 13; s ^= s >> 17; s ^= s << 5;
            tmp_buf[i]      = (uint8_t)(s >> 24);
        }
    }
}

int main(void)
{
    rvv_print_title("BLEND_H");
    rvv_print_header();

    static const int sizes[][2] = {
        {  4,  4}, {  8,  4}, { 16,  4}, { 32,  4}, { 64,  4}, {128,  4},
        {  4,  8}, {  8,  8}, { 16,  8}, { 32,  8}, { 64,  8}, {128,  8},
        {  4, 16}, {  8, 16}, { 16, 16}, { 32, 16}, { 64, 16}, {128, 16},
        {  4, 32}, {  8, 32}, { 16, 32}, { 32, 32}, { 64, 32}, {128, 32},
    };
    int num_sizes = sizeof(sizes) / sizeof(sizes[0]);
    int num_failed = 0;
    int num_cases = 0;

    for (int si = 0; si < num_sizes; si++) {
        int w = sizes[si][0];
        int h = sizes[si][1];
        int stride = w;

        for (int pattern = 0; pattern < 2; pattern++) {
            init_inputs(w, h, pattern);

            for (int k = 0; k < stride * h; k++) dst_w_buf[k] = dst_init_buf[k];
            blend_h_mock_c(dst_w_buf, stride, tmp_buf, w, h);
            for (int k = 0; k < stride * h; k++) dst_w_buf[k] = dst_init_buf[k];
            blend_h_mock_r(dst_w_buf, stride, tmp_buf, w, h);

            for (int k = 0; k < stride * h; k++) {
                dst_c_buf[k] = dst_init_buf[k];
                dst_r_buf[k] = dst_init_buf[k];
            }

            uint64_t start_c = rvv_read_cycles();
            blend_h_mock_c(dst_c_buf, stride, tmp_buf, w, h);
            uint64_t cycles_c = rvv_read_cycles() - start_c;

            uint64_t start_r = rvv_read_cycles();
            blend_h_mock_r(dst_r_buf, stride, tmp_buf, w, h);
            uint64_t cycles_r = rvv_read_cycles() - start_r;

            int failed = rvv_compare_u8(dst_c_buf, dst_r_buf, stride * h);
            num_failed += failed;
            num_cases++;

            rvv_print_row(w, h, cycles_c, cycles_r, failed);
            if (failed && num_failed == 1) {      /* only the first failing case */
                printf("first fail: w=%d h=%d pattern=%d\n C:", w, h, pattern);
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
