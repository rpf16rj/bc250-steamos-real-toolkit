import json
import os

import decky

_CONFIG_DIR = getattr(decky, "DECKY_PLUGIN_SETTINGS_DIR", None) or os.path.join(
    os.path.expanduser("~"), ".config", "bc250-launch-coach"
)
_CONFIG_FILE = os.path.join(_CONFIG_DIR, "options.json")


class Plugin:
    async def _main(self):
        os.makedirs(_CONFIG_DIR, exist_ok=True)
        decky.logger.info("BC-250 Launch Coach started (config: %s)", _CONFIG_FILE)

    async def _unload(self):
        decky.logger.info("BC-250 Launch Coach stopped")

    def _load(self) -> dict:
        try:
            with open(_CONFIG_FILE, encoding="utf-8") as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    def _save(self, data: dict):
        os.makedirs(_CONFIG_DIR, exist_ok=True)
        tmp = _CONFIG_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, _CONFIG_FILE)

    async def get_state(self) -> dict:
        return self._load()

    async def get_app(self, appid) -> dict | None:
        return self._load().get(str(appid))

    async def save_app(self, appid, options: str):
        data = self._load()
        data[str(appid)] = {"options": options}
        self._save(data)
        return True

    async def dismiss_app(self, appid):
        data = self._load()
        data[str(appid)] = {"dismissed": True}
        self._save(data)
        return True

    async def remove_app(self, appid):
        data = self._load()
        data.pop(str(appid), None)
        self._save(data)
        return True
