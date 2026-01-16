import os

import dotenv


dotenv.load_dotenv()


KAMATERA_API_CLIENT_ID = os.getenv("KAMATERA_API_CLIENT_ID")
KAMATERA_API_SECRET = os.getenv("KAMATERA_API_SECRET")
