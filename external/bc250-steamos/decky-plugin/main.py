import decky

from bc250_control import ToolkitBackend


class Plugin:
    def __init__(self):
        self.backend = ToolkitBackend(decky.DECKY_USER, decky.DECKY_USER_HOME)

    async def _main(self):
        decky.logger.info("BC-250 Control backend started")

    async def get_snapshot(self):
        return await self.backend.get_snapshot()

    async def get_telemetry(self):
        return await self.backend.get_telemetry()

    async def set_cu_wgp(self, se: int, sh: int, wgp: int, enabled: bool):
        return await self.backend.set_cu_wgp(se, sh, wgp, enabled)

    async def set_gpu_frequency(self, mode: str, minimum: int, maximum: int):
        return await self.backend.set_gpu_frequency(mode, minimum, maximum)

    async def set_load_target(self, preset: str):
        return await self.backend.set_load_target(preset)

    async def set_custom_load_target(self, minimum: int, maximum: int):
        return await self.backend.set_custom_load_target(minimum, maximum)

    async def set_ramp(self, climb_ms: int):
        return await self.backend.set_ramp(climb_ms)

    async def cpu_oc_action(
        self, action: str, frequency: int, voltage: int, temperature: int
    ):
        return await self.backend.cpu_oc_action(
            action, frequency, voltage, temperature
        )

    async def cec_action(self, action: str):
        return await self.backend.cec_action(action)

    async def set_cec_toggle(self, key: str, enabled: bool):
        return await self.backend.set_cec_toggle(key, enabled)

    async def set_cec_name(self, name: str):
        return await self.backend.set_cec_name(name)
