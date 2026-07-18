import struct


def pack_u32(value: int) -> int:
    return int(value) & 0xFFFFFFFF


def pack_s16(value: int) -> int:
    return struct.unpack("<I", struct.pack("<h", int(value)) + b"\x00\x00")[0]


def pack_f32(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", float(value)))[0]


def pack_vid_offset(volts: float) -> int:
    return pack_f32(volts)


def decode_u32(value: int) -> int:
    return int(value) & 0xFFFFFFFF


def vid_to_mv(vid: int) -> int:
    return int(round(((float(vid) * -0.00625) + 1.55) * 1000.0))


def mv_to_vid(mv: int) -> int:
    return int(round((1.55 - (float(mv) / 1000.0)) / 0.00625))
