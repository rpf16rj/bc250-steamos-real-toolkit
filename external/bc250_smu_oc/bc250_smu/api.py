from typing import Callable, Dict, Optional, Tuple

from .api_q0 import Queue0Mixin
from .api_q1 import Queue1Mixin
from .api_q2 import Queue2Mixin
from .api_q3 import Queue3Mixin
from .api_q4 import Queue4Mixin
from .codec import decode_u32, pack_u32
from .mailbox import Bc250Mailbox
from .transport import Bc250PciTransport


DEFAULT_QUEUE_ADDRS: Dict[int, Tuple[int, int, int]] = {
    0: (0x03B10A08, 0x03B10A68, 0x03B10A48),
    1: (0x03B10A00, 0x03B10A60, 0x03B10A40),
    2: (0x03B10528, 0x03B10564, 0x03B10998),
    3: (0x03B10A20, 0x03B10A80, 0x03B10A88),
    4: (0x03B10A24, 0x03B10A84, 0x03B10A8C),
}


class Bc250Smu(Queue0Mixin, Queue1Mixin, Queue2Mixin, Queue3Mixin, Queue4Mixin):
    def __init__(
        self,
        bdf: str = "0000:00:00.0",
        allow_queue0: bool = False,
        use_flock: bool = False,
        queue_addrs: Optional[Dict[int, Tuple[int, int, int]]] = None,
        timeout: int = 100,
    ) -> None:
        self._allow_queue0 = allow_queue0
        self._transport = Bc250PciTransport(bdf=bdf, use_flock=use_flock)
        self._transport.open()
        addrs = dict(DEFAULT_QUEUE_ADDRS)
        if queue_addrs:
            addrs.update(queue_addrs)
        self._queues: Dict[int, Bc250Mailbox] = {
            queue: Bc250Mailbox(self._transport, cmd, rsp, arg, timeout=timeout)
            for queue, (cmd, rsp, arg) in addrs.items()
        }

    def close(self) -> None:
        self._transport.close()

    def raw_send(self, queue: int, msg_id: int, arg: int = 0, arg_high: Optional[int] = None) -> int:
        self._guard_queue(queue)
        return self._get_queue(queue).send(msg_id, arg=arg, arg_high=arg_high)

    def raw_read(self, queue: int) -> int:
        self._guard_queue(queue)
        return self._get_queue(queue).read_arg()

    def raw_read_high(self, queue: int) -> int:
        self._guard_queue(queue)
        return self._get_queue(queue).read_arg_high()

    def send_message(
        self,
        queue_id: int,
        msg_id: int,
        arg: int = 0,
        arg_high: Optional[int] = None,
        pack: Optional[Callable[[int], int]] = None,
        decode: Optional[Callable[[int], int]] = None,
        check_status: bool = True,
    ) -> int:
        packed = pack(arg) if pack is not None else pack_u32(arg)
        status = self.raw_send(queue_id, msg_id, arg=packed, arg_high=arg_high)
        if check_status and status != Bc250Mailbox.SMU_RETURN_OK:
            raise RuntimeError(f"smu returned status 0x{status:02X} for queue {queue_id} msg 0x{msg_id:02X}")
        if decode is None:
            return status
        return decode(self.raw_read(queue_id))

    def test_message(self, value: int) -> bool:
        """Send test message and verify the response increments the value."""
        response = self.send_message(
            3,
            0x01,
            arg=value,
            pack=pack_u32,
            decode=decode_u32,
        )
        if response != value + 1:
            raise RuntimeError(f"unexpected test response {response}, expected {value + 1}")
        return True

    def check_test_message(self) -> bool:
        return self.test_message(123)

    def _get_queue(self, queue: int) -> Bc250Mailbox:
        if queue not in self._queues:
            raise KeyError(f"queue {queue} not configured")
        return self._queues[queue]

    def _guard_queue(self, queue: int) -> None:
        if queue == 0 and not self._allow_queue0:
            raise PermissionError("queue 0 access disabled; pass allow_queue0=True to enable")
