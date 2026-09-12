#include "rvv_test_common.h"

extern void ipred_v_mock_r(uint8_t *dst, int32_t stride,
                            const uint8_t *topleft, int width, int height);

void ipred_v_mock_c(uint8_t *dst, int32_t stride,
                     const uint8_t *topleft, int width, int height)
{
    const uint8_t *top_neighbors = topleft + 1;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++)
            dst[x] = top_neighbors[x];
        dst += stride;
    }
}

#define MAX_DIM 64
static uint8_t topleft_buf[MAX_DIM + 1];
static uint8_t dst_c_buf[MAX_DIM * MAX_DIM];
static uint8_t dst_r_buf[MAX_DIM * MAX_DIM];

int main(void)
{
    rvv_print_title("IPRED_V");
    rvv_print_header();

    int sizes[] = {4, 8, 16, 32, 64};
    int num_sizes = sizeof(sizes) / sizeof(sizes[0]);
    int num_failed = 0;

    for (int i = 0; i < num_sizes; i++) {
        int w = sizes[i];
        int h = sizes[i];
        int stride = w;

        for (int j = 0; j < w + 1; j++)
            topleft_buf[j] = (uint8_t)(j + 10);

        rvv_zero_u8(dst_c_buf, stride * h);
        rvv_zero_u8(dst_r_buf, stride * h);

        uint64_t start_c = rvv_read_cycles();
        ipred_v_mock_c(dst_c_buf, stride, topleft_buf, w, h);
        uint64_t cycles_c = rvv_read_cycles() - start_c;

        uint64_t start_r = rvv_read_cycles();
        ipred_v_mock_r(dst_r_buf, stride, topleft_buf, w, h);
        uint64_t cycles_r = rvv_read_cycles() - start_r;

        int failed = rvv_compare_u8(dst_c_buf, dst_r_buf, stride * h);
        num_failed += failed;

        rvv_print_row(w, h, cycles_c, cycles_r, failed);
    }

    rvv_print_summary(num_sizes, num_failed);
    return num_failed;
}
