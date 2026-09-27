import json
from pathlib import Path


class ConnectionStore:
    """Хранит соответствие «ID владельца → business_connection_id» в JSON-файле."""

    def __init__(self, data_dir: Path) -> None:
        self._path = data_dir / "connections.json"
        self._data: dict[str, str] = {}
        if self._path.exists():
            self._data = json.loads(self._path.read_text("utf-8"))

    def get(self, user_id: int) -> str | None:
        return self._data.get(str(user_id))

    def owner_of(self, connection_id: str) -> int | None:
        for user_id, conn_id in self._data.items():
            if conn_id == connection_id:
                return int(user_id)
        return None

    def set(self, user_id: int, connection_id: str) -> None:
        self._data[str(user_id)] = connection_id
        self._save()

    def remove(self, user_id: int) -> None:
        if self._data.pop(str(user_id), None) is not None:
            self._save()

    def _save(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self._path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self._data, ensure_ascii=False, indent=2), "utf-8")
        tmp.replace(self._path)
