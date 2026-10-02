.text
    .balign 4
    .global blend_v_mock_r
    .type blend_v_mock_r, @function

# void blend_v_mock_r(uint8_t *dst, int32_t dst_stride, const uint8_t *tmp,
#                      int w, int h)
#
# Register Mapping:
# a0 = dst
# a1 = dst_stride
# a2 = tmp           (row stride = w)
# a3 = w             (the mask is dav1d_obmc_masks[w .. w + (w*3>>2) - 1])
# a4 = h
#
# Ported from dav1d src/riscv/64/mc.S (blend_v_8bpc_rvv).

blend_v_mock_r:
  # ctz t0, a3  (Ara has no Zbb): w is a power of two
  li t0, 0
  mv t2, a3
blend_v_ctz_loop:
  andi t3, t2, 1
  bnez t3, blend_v_ctz_done
  addi t0, t0, 1
  srli t2, t2, 1
  j blend_v_ctz_loop
blend_v_ctz_done:
  addi t0, t0, 0xc4
  andi t0, t0, 0xc7
  srai t1, a3, 2
  sub t1, a3, t1
  vsetvl zero, t1, t0
  csrwi vxrm, 2                  # ARA FIX (upstream: csrw vxrm, zero)
  la t1, dav1d_obmc_masks
  add t1, t1, a3
  vle8.v v8, (t1)
  li t0, 64
  vrsub.vx v10, v8, t0
  li t2, 32                      # ARA FIX (rounding constant)
  vmv.v.i v20, 1                 # ARA FIX (vector of ones, hoisted)
1:
  addi a4, a4, -2
  vle8.v v4, (a2)
  add a2, a2, a3
  vle8.v v6, (a2)
  add a2, a2, a3
  vle8.v v0, (a0)
  add t0, a0, a1
  vle8.v v2, (t0)
  vwmulu.vv v12, v4, v8
  vwmulu.vv v16, v6, v8
  vwmaccu.vv v12, v0, v10
  vwmaccu.vv v16, v2, v10
  vwmaccu.vx v12, t2, v20        # ARA FIX (+32)
  vwmaccu.vx v16, t2, v20        # ARA FIX (+32)
  vnclipu.wi v0, v12, 6
  vnclipu.wi v2, v16, 6
  vse8.v v0, (a0)
  vse8.v v2, (t0)
  add a0, t0, a1
  bnez a4, 1b
  ret
