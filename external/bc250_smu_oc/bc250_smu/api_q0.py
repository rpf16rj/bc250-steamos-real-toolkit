from .codec import decode_u32, mv_to_vid, pack_u32, vid_to_mv


class Queue0Mixin:
    def _get_smu_version(self) -> int:
        return self.send_message(0, 0x02, decode=decode_u32)

    def _get_driver_if_version(self) -> int:
        return self.send_message(0, 0x03, decode=decode_u32)

    def _set_driver_table_dram_addr_high(self, value: int) -> None:
        self.send_message(0, 0x04, arg=value, pack=pack_u32)

    def _set_driver_table_dram_addr_low(self, value: int) -> None:
        self.send_message(0, 0x05, arg=value, pack=pack_u32)

    def _transfer_table_smu2dram(self) -> None:
        self.send_message(0, 0x06)

    def _transfer_table_dram2smu(self) -> None:
        self.send_message(0, 0x07)

    def request_core_pstate(self, pstate: int, core_mask: int) -> None:
        """Request a CPU P-state for cores specified in the mask."""
        param = ((pstate & 0xF) << 16) | (core_mask & 0xFF)
        self.send_message(0, 0x0B, arg=param, pack=pack_u32)

    def query_core_pstate(self, core_id: int) -> int:
        """Return the current core P-state (status 0xFF if core_id > 7)."""
        return self.send_message(
            0,
            0x0C,
            arg=core_id,
            pack=pack_u32,
            decode=decode_u32,
            check_status=False,
        )

    def _request_gfxclk(self) -> None:
        self.send_message(0, 0x0E)

    def query_gfxclk(self) -> int:
        """Return the current GFX frequency in MHz."""
        return self.send_message(0, 0x0F, decode=decode_u32)

    def query_vddcr_soc_clock(self, index: int) -> int:
        """Return the SoC clock for the given DPM index (upper 16 bits)."""
        param = (index & 0xFFFF) << 16
        return self.send_message(0, 0x11, arg=param, pack=pack_u32, decode=decode_u32)

    def _query_df_pstate(self) -> int:
        return self.send_message(0, 0x13, decode=decode_u32)

    def _configure_s3_pwroff_register_addr_high(self, value: int) -> None:
        self.send_message(0, 0x16, arg=value, pack=pack_u32)

    def _configure_s3_pwroff_register_addr_low(self, value: int) -> None:
        self.send_message(0, 0x17, arg=value, pack=pack_u32)

    def _request_active_wgp(self) -> None:
        self.send_message(0, 0x18)

    def _set_min_deep_sleep_gfxclk_freq(self, value: int) -> None:
        self.send_message(0, 0x19, arg=value, pack=pack_u32)

    def _set_max_deep_sleep_dfll_gfx_div(self, value: int) -> None:
        self.send_message(0, 0x1A, arg=value, pack=pack_u32)

    def _start_telemetry_reporting(self, value: int = 0) -> None:
        self.send_message(0, 0x1B, arg=value, pack=pack_u32)

    def _stop_telemetry_reporting(self) -> None:
        self.send_message(0, 0x1C)

    def _clear_telemetry_max(self) -> None:
        self.send_message(0, 0x1D)

    def query_active_wgp(self) -> int:
        """Return the active workgroup processor count."""
        return self.send_message(0, 0x1E, decode=decode_u32)

    def get_gfx_frequency(self) -> int:
        """Return the current GFX frequency in MHz (alias of query_gfxclk)."""
        return self.send_message(0, 0x37, decode=decode_u32)

    def get_gfx_vid(self) -> int:
        """Return the current GFX VID in mV."""
        vid = self.send_message(0, 0x38, decode=decode_u32)
        return vid_to_mv(vid)

    def force_gfx_freq(self, freq_mhz: int) -> None:
        """Force GFX frequency; firmware interprets the argument as MHz."""
        self.send_message(0, 0x39, arg=freq_mhz, pack=pack_u32)

    def unforce_gfx_freq(self) -> None:
        """Clear any forced GFX frequency settings."""
        self.send_message(0, 0x3A)

    def force_gfx_vid(self, mv: int) -> None:
        """Force GFX VID using millivolts input."""
        vid = mv_to_vid(mv)
        self.send_message(0, 0x3B, arg=vid, pack=pack_u32)

    def unforce_gfx_vid(self) -> None:
        """Clear any forced GFX VID settings."""
        self.send_message(0, 0x3C, check_status=False)

    def get_enabled_smu_features(self) -> int:
        """Return the enabled SMU feature bitmask."""
        return self.send_message(0, 0x3D, decode=decode_u32)

    def set_core_enable_mask(self, mask: int) -> None:
        """Set the CPU core enable mask (lower 8 bits)."""
        self.send_message(0, 0x2C, arg=mask & 0xFF, pack=pack_u32)

    def _gfx_cac_weight_operation(self, value: int) -> None:
        """For CAC Weights we don't really know what it does, only related thing we found was
        described in one of AMD Patent, with just mention of it's existing
        if someone from AMD reads this and wants to explain it, please help."""
        self.send_message(0, 0x2F, arg=value, pack=pack_u32)

    def _l3_cac_weight_operation(self, value: int) -> None:
        """For CAC Weights we don't really know what it does, only related thing we found was
        described in one of AMD Patents, with just mention of it's existing
        if someone from AMD reads this and wants to explain it, please help."""
        self.send_message(0, 0x30, arg=value, pack=pack_u32)

    def _pack_core_cac_weight(self, value: int) -> None:
        """For CAC Weights we don't really know what it does, only related thing we found was
        described in one of AMD Patents, with just mention of it's existing
        if someone from AMD reads this and wants to explain it, please help."""
        self.send_message(0, 0x31, arg=value, pack=pack_u32)

    def _set_driver_table_vmid(self, value: int) -> None:
        self.send_message(0, 0x34, arg=value, pack=pack_u32)

    def set_soft_min_cclk(self, core_id: int, freq_mhz: int) -> int:
        """Set soft min CCLK for a core; returns the clamped frequency in MHz."""
        param = ((core_id & 0xFF) << 20) | (freq_mhz & 0xFFFF)
        return self.send_message(0, 0x35, arg=param, pack=pack_u32, decode=decode_u32)

    def set_soft_max_cclk(self, core_id: int, freq_mhz: int) -> int:
        """Set soft max CCLK for a core; returns the clamped frequency in MHz."""
        param = ((core_id & 0xFF) << 20) | (freq_mhz & 0xFFFF)
        return self.send_message(0, 0x36, arg=param, pack=pack_u32, decode=decode_u32)
