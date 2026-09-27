import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


@dataclass(frozen=True)
class Config:
    bot_token: str
    owner_ids: frozenset[int]
    data_dir: Path
    forward_messages: bool


def load_config() -> Config:
    load_dotenv()

    token = os.getenv("BOT_TOKEN", "").strip()
    if not token:
        raise SystemExit("BOT_TOKEN не задан (см. .env.example)")

    raw_owners = os.getenv("OWNER_IDS", "")
    try:
        owners = frozenset(int(x) for x in raw_owners.replace(" ", "").split(",") if x)
    except ValueError:
        raise SystemExit("OWNER_IDS должен быть списком числовых Telegram ID через запятую")
    if not owners:
        raise SystemExit("OWNER_IDS не задан — без него бот не знает, кому разрешено управление")

    return Config(
        bot_token=token,
        owner_ids=owners,
        data_dir=Path(os.getenv("DATA_DIR", "data")),
        forward_messages=os.getenv("FORWARD_MESSAGES", "0").strip() in {"1", "true", "yes"},
    )
