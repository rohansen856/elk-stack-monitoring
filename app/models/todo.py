from sqlalchemy import Column, Integer, String, DateTime, Boolean, ForeignKey, Text, Index
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.database import Base


class Todo(Base):
    __tablename__ = "todos"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(255), nullable=False, index=True)
    description = Column(Text, nullable=True)
    completed = Column(Boolean, default=False, index=True)
    priority = Column(String(20), default="medium", index=True)  # low, medium, high
    due_date = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)

    owner = relationship("User", back_populates="todos")


# The list endpoint filters on owner_id and orders by created_at desc;
# single-column indexes could not serve that combination (AUDIT P6).
Index("ix_todos_owner_created", Todo.owner_id, Todo.created_at.desc())
