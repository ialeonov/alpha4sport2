from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', env_file_encoding='utf-8', case_sensitive=False)

    app_name: str = 'Alpha4Sport API'
    api_v1_prefix: str = '/api/v1'
    secret_key: str = 'change-me'
    access_token_expire_minutes: int = 60 * 24 * 365
    database_url: str
    allowed_origins: str = '*'
    allowed_origin_regex: str = r'https?://(localhost|127\.0\.0\.1)(:\d+)?'
    allow_credentials: bool = False
    upload_dir: str = './uploads'
    ai_coach_base_url: str = 'https://api.timeweb.cloud/api-models/v1'
    ai_coach_api_key: str = ''
    ai_coach_model: str = ''
    ai_coach_system_prompt: str = ''
    ai_coach_timeout_seconds: float = 45.0
    ai_coach_temperature: float = 0.6
    ai_coach_referer: str = ''
    ai_coach_title: str = 'Alpha4Sport AI Coach'

    @property
    def allowed_origins_list(self) -> list[str]:
        return [item.strip() for item in self.allowed_origins.split(',') if item.strip()]


settings = Settings()
