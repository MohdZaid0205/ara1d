#include "rvv_test_common.h"

extern void cfl_pred_mock_r(uint8_t *dst, int32_t stride, int width, int height,
                             int dc, const int16_t *ac, int alpha);

static inline int iclip_pixel(int v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }
static inline int apply_sign(int v, int s) { return s < 0 ? -v : v; }

void cfl_pred_mock_c(uint8_t *dst, int32_t stride, int width, int height,
                      int dc, const int16_t *ac, int alpha)
{
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            const int diff = alpha * ac[x];
            const int a = diff < 0 ? -diff : diff;
            dst[x] = (uint8_t)iclip_pixel(dc + apply_sign((a + 32) >> 6, diff));
        }
        ac += width;
        dst += stride;
    }
}

/* CfL prediction only ever runs on blocks up to 32x32 in AV1. */
#define MAX_DIM 32
static uint8_t dst_c_buf[MAX_DIM * MAX_DIM];
static uint8_t dst_r_buf[MAX_DIM * MAX_DIM];
static int16_t ac_buf[MAX_DIM * MAX_DIM];

/* Zero-mean-ish alternating ramp, like a real CfL AC buffer. */
static void init_ac(int n)
{
    for (int i = 0; i < n; i++)
        ac_buf[i] = (int16_t)(((i % 2) ? 1 : -1) * (4 + (i % 24)));
}

int main(void)
{
    rvv_print_title("CFL_PRED");
    rvv_print_header();

    int sizes[] = {4, 8, 16, 32};
    int num_sizes = sizeof(sizes) / sizeof(sizes[0]);
    /* One negative and one positive alpha so apply_sign()'s two branches
     * both get exercised, per the extraction's own test rationale. */
    int alphas[] = {-12, 7};
    int num_alphas = sizeof(alphas) / sizeof(alphas[0]);
    int num_failed = 0;
    int num_cases = 0;

    for (int wi = 0; wi < num_sizes; wi++) {
        for (int hi = 0; hi < num_sizes; hi++) {
            int w = sizes[wi];
            int h = sizes[hi];
            int stride = w;

            init_ac(w * h);

            for (int ai = 0; ai < num_alphas; ai++) {
                int alpha = alphas[ai];
                int dc = 128;

                for (int k = 0; k < stride * h; k++) {
                    dst_c_buf[k] = 128;
                    dst_r_buf[k] = 128;
                }

                uint64_t start_c = rvv_read_cycles();
                cfl_pred_mock_c(dst_c_buf, stride, w, h, dc, ac_buf, alpha);
                uint64_t cycles_c = rvv_read_cycles() - start_c;

                uint64_t start_r = rvv_read_cycles();
                cfl_pred_mock_r(dst_r_buf, stride, w, h, dc, ac_buf, alpha);
                uint64_t cycles_r = rvv_read_cycles() - start_r;

                int failed = rvv_compare_u8(dst_c_buf, dst_r_buf, stride * h);
                num_failed += failed;
                num_cases++;

                rvv_print_row(w, h, cycles_c, cycles_r, failed);
                if (failed && num_failed == 1) {          /* only the first failing case */
                    printf("first fail: w=%d h=%d alpha=%d\n C:", w, h, alpha);
                    for (int k = 0; k < 16; k++) printf(" %d", dst_c_buf[k]);
                    printf("\n R:");
                    for (int k = 0; k < 16; k++) printf(" %d", dst_r_buf[k]);
                    printf("\n");
                }
            }
        }
    }

    rvv_print_summary(num_cases, num_failed);
    return num_failed;
}
