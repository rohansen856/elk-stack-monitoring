from typing import List, Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str
    redis_url: str
    secret_key: str
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    environment: str = "development"
    log_level: str = "INFO"

    # CORS - comma-separated origins. Driven by configuration so a deployed
    # origin can be set without a code change (previously hardcoded to
    # localhost, which no deployment could ever match).
    cors_origins: str = "http://localhost:3000,http://localhost:8080"

    # ELK Stack Settings
    elasticsearch_url: Optional[str] = None
    elasticsearch_host: str = "elasticsearch"
    elasticsearch_port: int = 9200
    elasticsearch_username: str = "elastic"
    # No default: a missing password must fail loudly rather than silently
    # falling back to a well-known value published throughout the repository.
    elasticsearch_password: Optional[str] = None
    elasticsearch_use_ssl: bool = False
    kibana_host: str = "kibana"
    kibana_port: int = 5601
    logstash_host: str = "logstash"
    logstash_port: int = 5044
    logstash_tcp_port: int = 5000

    # Password reset / OTP
    otp_length: int = 8
    otp_expire_minutes: int = 15
    otp_max_attempts: int = 5

    # Observability
    metrics_token: Optional[str] = None

    # Alerting
    slack_webhook_url: Optional[str] = None
    alert_email_to: Optional[str] = None

    # Email Settings
    email_smtp_server: str
    email_smtp_port: int
    email_smtp_username: str
    email_smtp_password: str
    email_sender_address: str
    email_sender_name: str

    @property
    def cors_origin_list(self) -> List[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def is_production(self) -> bool:
        return self.environment.lower() == "production"

    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",  # Ignore extra environment variables
    )


settings = Settings()
