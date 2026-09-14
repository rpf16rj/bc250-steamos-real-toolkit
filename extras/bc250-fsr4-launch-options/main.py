import decky

class Plugin:
    async def _main(self):
        decky.logger.info("BC-250 FSR4 Launch Options started")

    async def _unload(self):
        decky.logger.info("BC-250 FSR4 Launch Options stopped")
