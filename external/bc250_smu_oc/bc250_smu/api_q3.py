from .codec import decode_u32, mv_to_vid, pack_s16, pack_u32, pack_vid_offset, vid_to_mv


class Queue3Mixin:
    
    def _q3_0x04(self) -> int | None:
        return self.send_message(3, 0x04)

    def _q3_0x0a(self) -> int | None:
        return self.send_message(3, 0x0A)

    def _q3_0x0b(self) -> int | None:
        return self.send_message(3, 0x0B)

    def _q3_0x0c(self) -> int | None:
        return self.send_message(3, 0x0C)

    def _q3_0x0d(self) -> int | None:
        return self.send_message(3, 0x0D)

    def _q3_0x0e(self) -> int | None:
        return self.send_message(3, 0x0E)

    def q3_0x0f_set_cpu_gpu_vid(self, kind: int, mv: int) -> None:
        """Set CPU (kind=0) or GFX (kind=1) VID using millivolts input."""
        vid = mv_to_vid(mv)
        param = ((kind & 0xFFFF) << 16) | (vid & 0xFFFF)
        self.send_message(3, 0x0F, arg=param, pack=pack_u32)

    def q3_0x10_unforce_cpu_gpu_vid(self, kind: int) -> None:
        """Unforce CPU (kind=0) or GFX (kind=1) VID."""
        param = (kind & 0xFFFF) << 16
        self.send_message(3, 0x10, arg=param, pack=pack_u32)

    def _q3_0x11(self) -> int | None:
        return self.send_message(3, 0x11)

    def _q3_0x14(self) -> int | None:
        return self.send_message(3, 0x14)

    def _q3_0x15(self) -> int | None:
        return self.send_message(3, 0x15)

    def _q3_0x18(self) -> int | None:
        return self.send_message(3, 0x18)

    def _q3_0x19(self) -> int | None:
        return self.send_message(3, 0x19)

    def _q3_0x1a(self) -> int | None:
        return self.send_message(3, 0x1A)

    def _q3_0x1b(self) -> int | None:
        return self.send_message(3, 0x1B)

    def _q3_0x1d_set_soc_clock_for_index(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x1D, arg=value, pack=pack_u32)

    def _q3_0x1e_set_perfprofileindex(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x1E, arg=value, pack=pack_u32)

    def q3_0x20_set_max_temperature_cpu_gpu(self, temp_c: int) -> None:
        """Set max temperature for CPU/GPU (0-100 C)."""
        self.send_message(3, 0x20, arg=temp_c, pack=pack_u32)

    def _q3_0x24(self) -> int | None:
        return self.send_message(3, 0x24)

    def q3_0x25_set_oc_clk(self, core_id: int, freq_mhz: int) -> None:
        """Set OC target clock for a core or all cores (core_id=0xFF)."""
        param = ((core_id & 0xFF) << 16) | (freq_mhz & 0xFFFF)
        self.send_message(3, 0x25, arg=param, pack=pack_u32)

    def q3_0x26_unset_oc_clk(self, core_id: int) -> None:
        """Clear OC target clock for a core or all cores (core_id=0xFF)."""
        param = (core_id & 0xFF) << 16
        self.send_message(3, 0x26, arg=param, pack=pack_u32)


    def _q3_0x28_write_to_dat_8b08_secure(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x28, arg=value, pack=pack_u32)

    def _q3_0x29_write_to_pointer_at_dat(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x29, arg=value, pack=pack_u32)

    def _q3_0x2b_writes_into_dat_00008b0c(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x2B, arg=value, pack=pack_u32)

    def q3_0x30_return_cpu_vid_float_or(self, selector: int) -> int:
        """Return packed status+value for CPU (0) or GFX (1) dynamic VID offset."""
        return self.send_message(3, 0x30, arg=selector, pack=pack_u32, decode=decode_u32)

    def _q3_0x34_return_dat_00015778(self) -> int | None:
        return self.send_message(3, 0x34, decode=decode_u32)

    def q3_0x36_get_current_cpu_voltage(self) -> int:
        """Return current CPU voltage in mV (truncated)."""
        return self.send_message(3, 0x36, decode=decode_u32)

    def q3_0x37_get_current_gpu_voltage(self) -> int:
        """Return current GPU voltage in mV (truncated)."""
        return self.send_message(3, 0x37, decode=decode_u32)

    def _q3_0x38_get_more_clock_assigned_to_state(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x38, arg=value, pack=pack_u32, decode=decode_u32)

    def _q3_0x39_get_other_clock_assigned_to_s(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x39, arg=value, pack=pack_u32, decode=decode_u32)

    def _q3_0x3a_get_some_clock_assigned_to_state(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x3A, arg=value, pack=pack_u32, decode=decode_u32)

    def q3_0x3b_get_clk_assigned_to_p_state(self, pstate: int) -> int:
        """Return the P-state clock in MHz for pstate 0-7."""
        return self.send_message(3, 0x3B, arg=pstate, pack=pack_u32, decode=decode_u32)

    def _q2_0x05_enable_smu_features_3c(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x3C, arg=value, pack=pack_u32)

    def _q2_0x06_disable_smu_features_3d(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x3D, arg=value, pack=pack_u32)

    def q3_0x40_get_cpu_temp_max(self) -> int:
        """Return max CPU temperature (often 100 on hardware)."""
        return self.send_message(3, 0x40, decode=decode_u32)

    def _q3_0x41_read_from_perfprofiletable(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x41, arg=value, pack=pack_u32, decode=decode_u32)

    def q3_0x42_return_vddcrsoc_dpm_value(self, index: int) -> int:
        """Return the SoC DPM clock for the given index (0-19)."""
        param = (index & 0xFFFF) << 16
        return self.send_message(3, 0x42, arg=param, pack=pack_u32, decode=decode_u32)

    def q3_0x43_get_core_freq(self, core_id: int) -> int:
        """Return core frequency in MHz for core_id 0-7."""
        return self.send_message(3, 0x43, arg=core_id, pack=pack_u32, decode=decode_u32)

    def q3_0x47_return_status_0xfe(self) -> int:
        """Return status 0xFE."""
        return self.send_message(3, 0x47)

    def q3_0x48_return_status_0xfe(self) -> int:
        """Return status 0xFE."""
        return self.send_message(3, 0x48)

    def q3_0x49_set_cpu_vid_offset(self, offset: int) -> None:
        """Set CPU VID offset (valid range -5..5)."""
        if (offset > 5) or (offset < -5):
            raise ValueError("Offset can be in range of -5 to 5")
        self.send_message(3, 0x49, arg=offset, pack=pack_u32)

    def q3_0x4a_set_gfx_vid_offset1(self, offset: int) -> None:
        """Set GFX VID offset 1 (valid range -5..5)."""
        if (offset > 5) or (offset < -5):
            raise ValueError("Offset can be in range of -5 to 5")
        self.send_message(3, 0x4A, arg=offset, pack=pack_u32)

    def _q2_0x17_cpu_droop_calibration_4b(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x4B, arg=value, pack=pack_u32)

    def q3_0x4c_gfx_droop_calibration(self, test_voltage_mv: int, margin_mv: int) -> None:
        """Run GFX droop calibration (low16=test mV, high16=margin mV)."""
        param = ((margin_mv & 0xFFFF) << 16) | (test_voltage_mv & 0xFFFF)
        self.send_message(3, 0x4C, arg=param, pack=pack_u32)

    def q3_0x4d_set_cpu_vid_offset_large(self, offset_v: float) -> None:
        """Set CPU VID float offset (valid range about -0.2..0.2 V)."""
        self.send_message(3, 0x4D, arg=offset_v, pack=pack_vid_offset)

    def q3_0x4e_set_gpu_vid_offset_large(self, offset_v: float) -> None:
        """Set GPU VID float offset (valid range about -0.2..0.2 V)."""
        self.send_message(3, 0x4E, arg=offset_v, pack=pack_vid_offset)

    def _q3_0x4f(self) -> int | None:
        return self.send_message(3, 0x4F)

    def q3_0x50_scale_f_vid_curve(self, value: int) -> None:
        """Set VID curve scaling (signed 16-bit, limit 0x3FFF)."""
        self.send_message(3, 0x50, arg=value, pack=pack_s16)

    def _q3_0x51_set_cpu_coeff(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x51, arg=value, pack=pack_u32)

    def q3_0x52_set_cpu_clock_stretch_coeff(self, coeff: int) -> None:
        """Set CPU clock stretch coefficient (0-1000)."""
        self.send_message(3, 0x52, arg=coeff, pack=pack_u32)

    def q3_0x53_set_ccx_clock_stretch_coeff(self, coeff: int) -> None:
        """Set CCX clock stretch coefficient (0-1000)."""
        self.send_message(3, 0x53, arg=coeff, pack=pack_u32)

    def _q3_0x54(self) -> int | None:
        return self.send_message(3, 0x54)

    def _q3_0x55(self) -> int | None:
        return self.send_message(3, 0x55)

    def _q3_0x56(self) -> int | None:
        return self.send_message(3, 0x56)

    def _q3_0x58(self) -> int | None:
        return self.send_message(3, 0x58)

    def _q3_0x59(self) -> int | None:
        return self.send_message(3, 0x59)

    def _q3_0x5a(self) -> int | None:
        return self.send_message(3, 0x5A)

    def _q3_0x5b(self) -> int | None:
        return self.send_message(3, 0x5B)

    def _q3_0x5c_something_freq_related(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x5C, arg=value, pack=pack_u32)

    def _q3_0x5d_something_freq_related(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x5D, arg=value, pack=pack_u32)

    def _q3_0x5e(self) -> int | None:
        return self.send_message(3, 0x5E)

    def _q3_0x5f_write_somecpu_frequency(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x5F, arg=value, pack=pack_u32)

    def _q3_0x60_somthing_pstate_related(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x60, arg=value, pack=pack_u32)

    def _q3_0x65_set_dat_000133fc_value(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x65, arg=value, pack=pack_u32)

    def _q3_0x66_reset_dat_000133fc_value_to_0(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x66, arg=value, pack=pack_u32)

    def q3_0x67_zero_return(self) -> int:
        """Return the function result (typically zero)."""
        return self.send_message(3, 0x67, decode=decode_u32)

    def _q3_0x6a(self) -> int | None:
        return self.send_message(3, 0x6A)

    def _q3_0x6b(self) -> int | None:
        return self.send_message(3, 0x6B)

    def _q3_0x6c_set_temperature_parameters(self, value: int = 0) -> None:
        self.send_message(3, 0x6C, arg=value, pack=pack_u32)

    def q3_0x6d_force_clock_stretching_vid(self, cpu_vid_mv: int, ccx_vid_mv: int) -> None:
        """Force clock stretching VIDs (low16=CPU mV, high16=CCX mV)."""
        param = ((ccx_vid_mv & 0xFFFF) << 16) | (cpu_vid_mv & 0xFFFF)
        self.send_message(3, 0x6D, arg=param, pack=pack_u32)

    def _q3_0x6e_cpu_coefficients(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x6E, arg=value, pack=pack_u32)

    def _q3_0x6f(self) -> int | None:
        return self.send_message(3, 0x6F)

    def _q3_0x70(self) -> int | None:
        return self.send_message(3, 0x70)

    def _q3_0x71(self) -> int | None:
        return self.send_message(3, 0x71)

    def _q3_0x72(self) -> int | None:
        return self.send_message(3, 0x72)

    def _q3_0x73(self) -> int | None:
        return self.send_message(3, 0x73)

    def _q3_0x74(self) -> int | None:
        return self.send_message(3, 0x74)

    def _q3_0x75(self) -> int | None:
        return self.send_message(3, 0x75)

    def _q3_0x76(self) -> int | None:
        return self.send_message(3, 0x76)

    def q3_0x77_set_cpu_max_current(self, current_ma: int) -> None:
        """Set CPU max current (mA)."""
        self.send_message(3, 0x77, arg=current_ma, pack=pack_u32)

    def q3_0x7f_get_current_perf_sample(self) -> int:
        """Return current performance sample period average (us)."""
        return self.send_message(3, 0x7F, decode=decode_u32)

    def q3_0x80_get_sample_interval_max(self) -> int:
        """Return maximum sample interval."""
        return self.send_message(3, 0x80, decode=decode_u32)

    def _q3_0x85(self) -> int | None:
        return self.send_message(3, 0x85)

    def _q3_0x86(self) -> int | None:
        return self.send_message(3, 0x86)

    def _q3_0x87(self) -> int | None:
        return self.send_message(3, 0x87)

    def q3_0x8b_set_cpu_max_temperature(self, temp_c: int) -> None:
        """Set CPU max temperature (0-100 C)."""
        self.send_message(3, 0x8B, arg=temp_c, pack=pack_u32)

    def q3_0x8c_set_gpu_max_temperature(self, temp_c: int) -> None:
        """Set GPU max temperature (0-100 C)."""
        self.send_message(3, 0x8C, arg=temp_c, pack=pack_u32)

    def q3_0x8d_get_current_sample_interval(self) -> int:
        """Return current sample interval."""
        return self.send_message(3, 0x8D, decode=decode_u32)

    def q3_0x8e_set_vid_main_2_limit(self, limit_mv: int) -> None:
        """Set VID main 2 limit (mV)."""
        self.send_message(3, 0x8E, arg=limit_mv, pack=pack_u32)

    def q3_0x8f_set_max_cpu_boost_clk(self, freq_mhz: int) -> None:
        """Set max CPU boost clock (MHz)."""
        self.send_message(3, 0x8F, arg=freq_mhz, pack=pack_u32)

    def _q3_0x90(self) -> int | None:
        return self.send_message(3, 0x90)

    def _q3_0x91(self) -> int | None:
        return self.send_message(3, 0x91)

    def _q3_0x96(self) -> int | None:
        return self.send_message(3, 0x96)

    def _q3_0x98(self) -> int | None:
        return self.send_message(3, 0x98)

    def _q3_0x99_modify_p_state_0_parameter_an(self, value: int = 0) -> int | None:
        return self.send_message(3, 0x99, arg=value, pack=pack_u32)

    def disable_extra_cpu_gpu_voltage(self, flag: bool) -> None:
        self.send_message(3, 0x9A, arg=1 if flag else 0, pack=pack_u32)

    def _q3_0x9b_switch_core_bilinear_model(self) -> int | None:
        return self.send_message(3, 0x9B)

    def _q3_0x9c(self) -> int | None:
        return self.send_message(3, 0x9C)

    def _q3_0xa7_cpu_related(self, value: int = 0) -> int | None:
        return self.send_message(3, 0xA7, arg=value, pack=pack_u32)

    def _q3_0xa8_cpu_related(self, value: int = 0) -> int | None:
        return self.send_message(3, 0xA8, arg=value, pack=pack_u32)

    # This group of functions seems to be accessable if some flag is passed to SMU at boot from bios
    # Currently we have no idea how to do it
    def _q3_0x27_secure_access(self) -> int | None:
        return self.send_message(3, 0x27)

    def _q3_0x2a_secure_access(self) -> int | None:
        return self.send_message(3, 0x2A)

    def _q3_0x2c_secure_access(self) -> int | None:
        return self.send_message(3, 0x2C)

    def _q3_0x2d_secure_access(self) -> int | None:
        return self.send_message(3, 0x2D)

    def _q3_0x2e_secure_access(self) -> int | None:
        return self.send_message(3, 0x2E)

    def _q3_0x2f_secure_access(self) -> int | None:
        return self.send_message(3, 0x2F)