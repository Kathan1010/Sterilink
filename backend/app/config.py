from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str
    mongo_url: str = "mongodb://127.0.0.1:27017"
    mongo_db: str = "sterilink_events"
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 480

    class Config:
        env_file = ".env"


settings = Settings()
