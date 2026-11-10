from pydantic import BaseModel, ConfigDict, Field
from typing import Optional
from datetime import datetime
from enum import Enum


class PriorityEnum(str, Enum):
    low = "low"
    medium = "medium"
    high = "high"


# Mirrors the String(255) column in app/models/todo.py. Without the bound an
# overlong title passed validation and failed in the database as a 500.
TITLE_MAX_LENGTH = 255


class TodoBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=TITLE_MAX_LENGTH)
    description: Optional[str] = None
    priority: PriorityEnum = PriorityEnum.medium
    due_date: Optional[datetime] = None


class TodoCreate(TodoBase):
    pass


class TodoUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=TITLE_MAX_LENGTH)
    description: Optional[str] = None
    completed: Optional[bool] = None
    priority: Optional[PriorityEnum] = None
    due_date: Optional[datetime] = None


class TodoResponse(TodoBase):
    id: int
    completed: bool
    created_at: datetime
    updated_at: Optional[datetime] = None
    owner_id: int

    model_config = ConfigDict(from_attributes=True)


class TodoFilter(BaseModel):
    completed: Optional[bool] = None
    priority: Optional[PriorityEnum] = None
    search: Optional[str] = None
    skip: int = 0
    limit: int = 100