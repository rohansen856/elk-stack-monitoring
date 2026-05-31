from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

from app.config import settings

# Connection arguments differ for SQLite (used by the test suite) and the
# pooled server-side databases used everywhere else.
_is_sqlite = settings.database_url.startswith("sqlite")

if _is_sqlite:
    engine = create_engine(
        settings.database_url,
        connect_args={"check_same_thread": False},
    )
else:
    engine = create_engine(
        settings.database_url,
        # pool_pre_ping avoids handing out connections that the server has
        # already dropped (after a restart or an idle timeout), which
        # previously surfaced to users as errors. See AUDIT P5.
        pool_pre_ping=True,
        pool_size=10,
        max_overflow=20,
        pool_recycle=1800,
        pool_timeout=30,
    )

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    except Exception:
        # Roll back before returning the connection to the pool; without this a
        # failed transaction could be handed to the next request mid-transaction.
        db.rollback()
        raise
    finally:
        db.close()
