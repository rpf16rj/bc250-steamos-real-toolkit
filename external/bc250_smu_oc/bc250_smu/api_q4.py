from .codec import pack_u32


class Queue4Mixin:
    def _q5_0x04(self) -> int | None:
        return self.send_message(4, 0x04)

    def _q5_0x05(self) -> int | None:
        return self.send_message(4, 0x05)

    def _q5_0x06(self) -> int | None:
        return self.send_message(4, 0x06)

    def _q5_0x07(self) -> int | None:
        return self.send_message(4, 0x07)

    def _q5_0x08(self) -> int | None:
        return self.send_message(4, 0x08)

    def _q5_0x09(self) -> int | None:
        return self.send_message(4, 0x09)

    def _q5_0x0a_freq_op1(self, value: int = 0) -> int | None:
        return self.send_message(4, 0x0A, arg=value, pack=pack_u32)

    def _q5_0x0b(self) -> int | None:
        return self.send_message(4, 0x0B)

    def _q5_0x0d(self) -> int | None:
        return self.send_message(4, 0x0D)

    def _q5_0x10(self) -> int | None:
        return self.send_message(4, 0x10)

    def _q5_0x11(self) -> int | None:
        return self.send_message(4, 0x11)
