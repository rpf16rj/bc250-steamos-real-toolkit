from .codec import decode_u32, pack_u32


class Queue2Mixin:
    def q2_0x03(self) -> int:
        """Return constant 23."""
        return self.send_message(2, 0x03, decode=decode_u32)

    def q2_0x04_get_device_name(self, index: int) -> int:
        """Return a 4-byte chunk of the device name for index 0-11."""
        return self.send_message(2, 0x04, arg=index, pack=pack_u32, decode=decode_u32)

    def q2_0x05_enable_smu_features(self, mask_low: int, mask_high: int = 0) -> None:
        """Enable SMU features using a 64-bit mask split into two 32-bit words."""
        self.send_message(2, 0x05, arg=mask_low, arg_high=mask_high, pack=pack_u32)

    def q2_0x06_disable_smu_features(self, mask_low: int, mask_high: int = 0) -> None:
        """Disable SMU features using a 64-bit mask split into two 32-bit words."""
        self.send_message(2, 0x06, arg=mask_low, arg_high=mask_high, pack=pack_u32)

    def _q2_0x07(self) -> int | None:
        return self.send_message(2, 0x07)

    def _q2_0x08(self) -> int | None:
        return self.send_message(2, 0x08)

    def _q2_0x09(self) -> int | None:
        return self.send_message(2, 0x09)

    def _q2_0x0a(self) -> int | None:
        return self.send_message(2, 0x0A)

    def _q2_0x0b(self) -> int | None:
        return self.send_message(2, 0x0B)

    def _q2_0x0c(self) -> int | None:
        return self.send_message(2, 0x0C)

    def _q2_message_set_some_other_addr_high(self, value: int = 0) -> int | None:
        return self.send_message(2, 0x0D, arg=value, pack=pack_u32)

    def _q2_message_set_some_other_addr_low(self, value: int = 0) -> int | None:
        return self.send_message(2, 0x0E, arg=value, pack=pack_u32)

    def _q2_0x3e(self) -> int | None:
        return self.send_message(2, 0x0F)

    def _q2_0x3f(self) -> int | None:
        return self.send_message(2, 0x10)

    def _q2_0x13(self) -> int | None:
        return self.send_message(2, 0x13)

    def _q2_0x14(self) -> int | None:
        return self.send_message(2, 0x14)

    def _q2_0x15(self) -> int | None:
        return self.send_message(2, 0x15)

    def _q2_0x16(self) -> int | None:
        return self.send_message(2, 0x16)

    def q2_0x17_cpu_droop_calibration(self, test_voltage_mv: int, margin_mv: int) -> None:
        """Run CPU droop calibration (low16=test mV, high16=margin mV)."""
        param = ((margin_mv & 0xFFFF) << 16) | (test_voltage_mv & 0xFFFF)
        self.send_message(2, 0x17, arg=param, pack=pack_u32)

    def _q2_0x1a(self) -> int | None:
        return self.send_message(2, 0x1A)

    def _q2_0x20(self) -> int | None:
        return self.send_message(2, 0x20)

    def _q2_0x21(self) -> int | None:
        return self.send_message(2, 0x21)

    def _q2_0x22(self) -> int | None:
        return self.send_message(2, 0x22)

    def _q2_0x23(self) -> int | None:
        return self.send_message(2, 0x23)

    def _q2_0x29(self) -> int | None:
        return self.send_message(2, 0x29)

    def _q2_0x2c_probably_power_limit_settings(self) -> int | None:
        return self.send_message(2, 0x2C)

    def _q2_0x2d_sibling_of_0x2c_but_returns_v(self) -> int | None:
        return self.send_message(2, 0x2D)

    def _q2_0x2e(self) -> int | None:
        return self.send_message(2, 0x2E)

    def _q2_0x2f(self) -> int | None:
        return self.send_message(2, 0x2F)

    def _q2_0x30(self) -> int | None:
        return self.send_message(2, 0x30)
