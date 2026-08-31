# AIC8800DC/DW legacy MCU1 profile

This is the minimal driver and firmware subset needed by the toolkit's
explicit `legacy-mcu1` installation profile.

- Upstream: <https://github.com/shenmintao/aic8800d80>
- Branch: `legacy-mcu1`
- Commit: `4b717f40489f94988713474eb3bd7d75ba83b292`
- Upstream validation: <https://github.com/shenmintao/aic8800d80/blob/legacy-mcu1/tests/issue71-mcu1-v3-profile/README.md>

This profile is only for AIC8800DC/DW hardware reporting
`chip_id=7, chip_mcu_id=1`. It must not replace the toolkit's current D80/MCU0
profile.

Validated AIC8800DC firmware hashes:

```text
bfd8ea1d174242e7ec823813b6c5d849  fmacfw_patch_8800dc_u02.bin
7b5fde609392c2e6c2c5874838dda718  fmacfw_patch_tbl_8800dc_u02.bin
```

The vendored subset contains `drivers/aic8800` and `fw/aic8800DC` only. Its
top-level driver Makefile has one toolkit-local build adaptation: optional BTF
generation is disabled when SteamOS does not provide `pahole`.
