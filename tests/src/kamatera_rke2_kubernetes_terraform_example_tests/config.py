import os

import dotenv


dotenv.load_dotenv()


KAMATERA_API_CLIENT_ID = os.getenv("KAMATERA_API_CLIENT_ID")
KAMATERA_API_SECRET = os.getenv("KAMATERA_API_SECRET")

DEFAULT_WAIT_FOR_TIMEOUT_SECONDS = os.getenv("DEFAULT_WAIT_FOR_TIMEOUT_SECONDS") or 1200  # 20 minutes
