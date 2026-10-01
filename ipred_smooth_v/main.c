#include "rvv_test_common.h"

extern void ipred_smooth_v_mock_r(uint8_t *dst, int32_t stride,
                                  const uint8_t *topleft, int width, int height,
                                  int a, int max_width, int max_height);

const uint8_t dav1d_sm_weights[128] = {
    /* unused (always offset by bs >= 2) */
    0, 0,
    /* bs = 2 */
    255, 128,
    /* bs = 4 */
    255, 149, 85, 64,
    /* bs = 8 */
    255, 197, 146, 105, 73, 50, 37, 32,
    /* bs = 16 */
    255, 225, 196, 170, 145, 123, 102, 84, 68, 54, 43, 33, 26, 20, 17, 16,
    /* bs = 32 */
    255, 240, 225, 210, 196, 182, 169, 157, 145, 133, 122, 111, 101, 92, 83, 74,
    66, 59, 52, 45, 39, 34, 29, 25, 21, 17, 14, 12, 10, 9, 8, 8,
    /* bs = 64 */
    255, 248, 240, 233, 225, 218, 210, 203, 196, 189, 182, 176, 169, 163, 156,
    150, 144, 138, 133, 127, 121, 116, 111, 106, 101, 96, 91, 86, 82, 77, 73, 69,
    65, 61, 57, 54, 50, 47, 44, 41, 38, 35, 32, 29, 27, 25, 22, 20, 18, 16, 15,
    13, 12, 10, 9, 8, 7, 6, 6, 5, 5, 4, 4, 4
};

void ipred_smooth_v_mock_c(uint8_t *dst, int32_t stride,
                           const uint8_t *topleft, int width, int height,
                           int a, int max_width, int max_height)
{
    (void)a; (void)max_width; (void)max_height;
    const uint8_t *const weights_ver = &dav1d_sm_weights[height];
    const int bottom = topleft[-height];

    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            const int pred = weights_ver[y]  * topleft[1 + x] +
                      (256 - weights_ver[y]) * bottom;
            dst[x] = (uint8_t)((pred + 128) >> 8);
        }
        dst += stride;
    }
}

#define MAX_DIM 64
/* topleft[-height .. width] is stored at topleft_buf[MAX_DIM + i], so
 * topleft = topleft_buf + MAX_DIM. */
static uint8_t topleft_buf[2 * MAX_DIM + 1];
static uint8_t dst_c_buf[MAX_DIM * MAX_DIM];
static uint8_t dst_r_buf[MAX_DIM * MAX_DIM];
static uint8_t dst_w_buf[MAX_DIM * MAX_DIM];   /* scratch for warm-up calls */

static void init_topleft(int width, int height, int pattern)
{
    uint32_t s = 0x9E3779B9u ^ (uint32_t)(width * 131 + height);
    for (int i = -height; i <= width; i++) {
        s ^= s << 13; s ^= s >> 17; s ^= s << 5;
        topleft_buf[MAX_DIM + i] = pattern ? 255 : (uint8_t)(s >> 24);
    }
    if (!pattern) {          /* make sure bottom and the last top pixel differ */
        topleft_buf[MAX_DIM + width]  = 251;
        topleft_buf[MAX_DIM - height] = 3;
    }
}

int main(void)
{
    rvv_print_title("IPRED_SMOOTH_V");
    rvv_print_header();

    static const int sizes[][2] = {
        { 4,  4}, { 4,  8}, { 4, 16},
        { 8,  4}, { 8,  8}, { 8, 16}, { 8, 32},
        {16,  4}, {16,  8}, {16, 16}, {16, 32}, {16, 64},
        {32,  8}, {32, 16}, {32, 32}, {32, 64},
        {64, 16}, {64, 32}, {64, 64},
    };
    int num_sizes = sizeof(sizes) / sizeof(sizes[0]);
    int num_failed = 0;
    int num_cases = 0;

    for (int si = 0; si < num_sizes; si++) {
        int w = sizes[si][0];
        int h = sizes[si][1];
        int stride = w;

        for (int pattern = 0; pattern < 2; pattern++) {
            init_topleft(w, h, pattern);
            const uint8_t *topleft = topleft_buf + MAX_DIM;

            /* Discarded warm-up call of each implementation (scratch dst)
             * so cold-cache / first-call effects don't land in the timing. */
            ipred_smooth_v_mock_c(dst_w_buf, stride, topleft, w, h, 0, w, h);
            ipred_smooth_v_mock_r(dst_w_buf, stride, topleft, w, h, 0, w, h);

            rvv_zero_u8(dst_c_buf, stride * h);
            rvv_zero_u8(dst_r_buf, stride * h);

            uint64_t start_c = rvv_read_cycles();
            ipred_smooth_v_mock_c(dst_c_buf, stride, topleft, w, h, 0, w, h);
            uint64_t cycles_c = rvv_read_cycles() - start_c;

            uint64_t start_r = rvv_read_cycles();
            ipred_smooth_v_mock_r(dst_r_buf, stride, topleft, w, h, 0, w, h);
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
