.text
    .balign 4
    .global blend_h_mock_r
    .type blend_h_mock_r, @function

# void blend_h_mock_r(uint8_t *dst, int32_t dst_stride, const uint8_t *tmp,
#                      int w, int h)
#
# Register Mapping:
# a0 = dst
# a1 = dst_stride
# a2 = tmp           (row stride = w)
# a3 = w
# a4 = h             (the mask is dav1d_obmc_masks[h .. h + h - 1]; (h*3)>>2 rows are blended)
#
# Ported from dav1d src/riscv/64/mc.S (blend_h_8bpc_rvv).

blend_h_mock_r:
  li t2, 64
  li t6, 32                      # ARA FIX (rounding constant)
  bgt a3, t2, 128f
  # ctz t0, a3  (Ara has no Zbb): w is a power of two, w <= 64
  li t0, 0
  mv t3, a3
blend_h_ctz_loop:
  andi t4, t3, 1
  bnez t4, blend_h_ctz_done
  addi t0, t0, 1
  srli t3, t3, 1
  j blend_h_ctz_loop
blend_h_ctz_done:
  addi t0, t0, 0xc4
  csrwi vxrm, 2                  # ARA FIX (upstream: csrw vxrm, zero)
  andi t0, t0, 0xc7
  vsetvl zero, a3, t0
  la t1, dav1d_obmc_masks
  srai t0, a4, 2
  add t1, t1, a4
  sub a4, a4, t0
0:
  mv t5, ra
1:
  addi a4, a4, -2
  lbu t3, (t1)
  addi t1, t1, 1
  lbu t4, (t1)
  addi t1, t1, 1
  vle8.v v8, (a2)
  add a2, a2, a3
  vle8.v v12, (a2)
  add a2, a2, a3
  vle8.v v0, (a0)
  add t0, a0, a1
  vle8.v v4, (t0)
  vwmulu.vx v16, v8, t3
  vwmulu.vx v24, v12, t4
  vmv.v.i v8, 1                  # ARA FIX (v8 is dead after the vwmulu.vx above)
  sub t3, t2, t3
  sub t4, t2, t4
  vwmaccu.vx v16, t3, v0
  vwmaccu.vx v24, t4, v4
  vwmaccu.vx v16, t6, v8         # ARA FIX (+32)
  vwmaccu.vx v24, t6, v8         # ARA FIX (+32)
  vnclipu.wi v0, v16, 6
  vnclipu.wi v4, v24, 6
  vse8.v v0, (a0)
  vse8.v v4, (t0)
  add a0, t0, a1
  bgtz a4, 1b
  jr t5
128:
  csrwi vxrm, 2                  # ARA FIX (upstream: csrw vxrm, zero)
  vsetvli zero, t2, e8, m4, ta, ma
  la t1, dav1d_obmc_masks
  srai t0, a4, 2
  add t1, t1, a4
  sub a4, a4, t0
  mv a5, a0
  mv a6, a2
  mv a7, a4
  jal t5, 1b
  add t1, t1, a4
  add a0, a5, t2
  add a2, a6, t2
  mv a4, a7
  sub t1, t1, a4
  j 0b
