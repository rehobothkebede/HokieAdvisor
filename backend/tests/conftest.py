"""Local-only test setup: dummy credentials, no .env, no network, no OpenAI."""
import os
import sys

import dotenv

# app.config calls load_dotenv(override=True); never let a developer's real
# .env (with real keys) into the test process.
dotenv.load_dotenv = lambda *args, **kwargs: False

os.environ.update({
    "OPENAI_API_KEY": "sk-dummy-not-a-real-key",
    "SUPABASE_URL": "http://supabase.test",
    "SUPABASE_ANON_KEY": "dummy-anon-key",
    "SUPABASE_SERVICE_ROLE_KEY": "dummy-service-role-key",
    "APP_ENV": "test",
})
os.environ.pop("LEGACY_AI_ROUTES_ENABLED", None)
os.environ.pop("ADMIN_API_TOKEN", None)

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
