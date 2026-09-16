.text
    .balign 4
    .global blend_mock_r
    .type blend_mock_r, @function

# void blend_mock_r(uint8_t *dst, int32_t dst_stride, const uint8_t *tmp,
#                    int w, int h, const uint8_t *mask)
#
# Register Mapping:
# a0 = dst
# a1 = dst_stride
# a2 = tmp
# a3 = w
# a4 = h
# a5 = mask
#
# Ported from dav1d src/riscv/64/mc.S (blend_8bpc_rvv), commit
# 362bc1138228390a0a521ecf3af18b23c6afeb9e.
#
# Zbb lowering: upstream computes a branchless vtype value as
# ctz(w) + 0xc4 (top two bits = vma/vta = 1/1; the low 3 bits after the
# add select LMUL 1/4..2 for w=4..32 via SEW=8's vlmul field - verified
# against the pre-branchless version of this function in dav1d history),
# masks it with 0xc7 to clear the carry the add spills into the SEW
# field, and feeds the result straight to `vsetvl` as a raw vtype
# register - that `vsetvl` call itself needs no extension, only `ctz`
# does. Only `ctz t0, a3` is replaced, with a small bit-scan loop (w is
# always a power of two: 4/8/16/32/64, so at most 6 iterations). Named
# labels (ctz_w_loop/ctz_w_done) are used for it so they can't collide
# with dav1d's own local numeric labels used later in the function.
# Everything else, including the 0xc4/0xc7 constants and the vsetvl call,
# is untouched.

blend_mock_r:
    # ctz(a3) -> t0   (Ara has no Zbb; a3/width is always a power of
    # two here - 4/8/16/32/64 - so a short bit-scan loop suffices.
    # t2/t3 are free scratch registers throughout this function. Named
    # labels used here, not numeric ones, so they can't collide with
    # dav1d's own local numeric labels (1:/2:/etc.) later in the body.)
    li t0, 0
    mv t2, a3
ctz_w_loop:
    andi t3, t2, 1
    bnez t3, ctz_w_done
    addi t0, t0, 1
    srli t2, t2, 1
    j ctz_w_loop
ctz_w_done:
  addi t0, t0, 0xc4
  csrwi vxrm, 2                    # rdn: Ara drops vnclipu rounding for elements >= 4
  andi t0, t0, 0xc7
  vsetvl zero, a3, t0
  li t1, 64
  li t3, 32
  vmv.v.i v12, 1
1:
  addi a4, a4, -2
  vle8.v v4, (a2)
  add a2, a2, a3
  vle8.v v6, (a2)
  add a2, a2, a3
  vle8.v v8, (a5)
  add a5, a5, a3
  vle8.v v10, (a5)
  add a5, a5, a3
  vle8.v v0, (a0)
  add t0, a0, a1
  vle8.v v2, (t0)
  vwmulu.vv v16, v4, v8
  vwmulu.vv v20, v6, v10
  vrsub.vx v8, v8, t1
  vrsub.vx v10, v10, t1
  vwmaccu.vv v16, v0, v8
  vwmaccu.vv v20, v2, v10
  vwmaccu.vx v16, t3, v12
  vwmaccu.vx v20, t3, v12
  vnclipu.wi v0, v16, 6
  vnclipu.wi v2, v20, 6
  vse8.v v0, (a0)
  vse8.v v2, (t0)
  add a0, t0, a1
  bnez a4, 1b
  ret
