from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    database_url: str
    redis_url: str
    secret_key: str
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    environment: str = "development"
    log_level: str = "INFO"

    # ELK Stack Settings
    elasticsearch_url: Optional[str] = None
    elasticsearch_host: str = "elasticsearch"
    elasticsearch_port: int = 9200
    elasticsearch_password: str = "elastic123"
    kibana_host: str = "kibana"
    kibana_port: int = 5601
    logstash_host: str = "logstash"
    logstash_port: int = 5044
    logstash_tcp_port: int = 5000

    # Email Settings
    email_smtp_server: str
    email_smtp_port: int
    email_smtp_username: str
    email_smtp_password: str
    email_sender_address: str
    email_sender_name: str

    class Config:
        env_file = ".env"
        extra = "ignore"  # Ignore extra environment variables


settings = Settings()