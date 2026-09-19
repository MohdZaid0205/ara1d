#include "rvv_test_common.h"

extern void ipred_paeth_mock_r(uint8_t *dst, int32_t stride,
                                const uint8_t *topleft, int width, int height);

static inline int iabs(int x) { return x < 0 ? -x : x; }

void ipred_paeth_mock_c(uint8_t *dst, int32_t stride,
                         const uint8_t *topleft, int width, int height)
{
    const int tl = topleft[0];
    for (int y = 0; y < height; y++) {
        const int left = topleft[-(y + 1)];
        for (int x = 0; x < width; x++) {
            const int top = topleft[1 + x];
            const int base = left + top - tl;
            const int ldiff = iabs(left - base);
            const int tdiff = iabs(top - base);
            const int tldiff = iabs(tl - base);
            dst[x] = (uint8_t)(ldiff <= tdiff && ldiff <= tldiff ? left :
                                tdiff <= tldiff ? top : tl);
        }
        dst += stride;
    }
}

#define MAX_DIM 64
/* topleft[-height .. width]; store at buf[MAX_DIM + i] so topleft = buf + MAX_DIM. */
static uint8_t topleft_buf[2 * MAX_DIM + 1];
static uint8_t dst_c_buf[MAX_DIM * MAX_DIM];
static uint8_t dst_r_buf[MAX_DIM * MAX_DIM];

/* Non-flat, non-monotonic-enough-to-degenerate gradient so all three
 * paeth candidate branches (left/top/topleft) actually get exercised,
 * per plan_prompt's "flat data hides bugs in paeth" note. */
static void init_topleft(int width, int height)
{
    for (int i = -height; i <= width; i++) {
        int v = 20 + ((i + height) * 5) % 200;
        if ((i + height) & 1) v += 3;
        topleft_buf[MAX_DIM + i] = (uint8_t)v;
    }
}

int main(void)
{
    rvv_print_title("IPRED_PAETH");
    rvv_print_header();

    int sizes[] = {4, 8, 16, 32, 64};
    int num_sizes = sizeof(sizes) / sizeof(sizes[0]);
    int num_failed = 0;
    int num_cases = 0;

    for (int wi = 0; wi < num_sizes; wi++) {
        for (int hi = 0; hi < num_sizes; hi++) {
            int w = sizes[wi];
            int h = sizes[hi];
            int stride = w;

            init_topleft(w, h);
            const uint8_t *topleft = topleft_buf + MAX_DIM;

            rvv_zero_u8(dst_c_buf, stride * h);
            rvv_zero_u8(dst_r_buf, stride * h);

            uint64_t start_c = rvv_read_cycles();
            ipred_paeth_mock_c(dst_c_buf, stride, topleft, w, h);
            uint64_t cycles_c = rvv_read_cycles() - start_c;

            uint64_t start_r = rvv_read_cycles();
            ipred_paeth_mock_r(dst_r_buf, stride, topleft, w, h);
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
