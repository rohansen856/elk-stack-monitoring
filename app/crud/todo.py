from sqlalchemy.orm import Session
from sqlalchemy import and_, or_
from typing import List, Optional
from app.models.todo import Todo
from app.schemas.todo import TodoCreate, TodoUpdate, TodoFilter


def get_todos(db: Session, user_id: int, filters: TodoFilter) -> List[Todo]:
    query = db.query(Todo).filter(Todo.owner_id == user_id)

    if filters.completed is not None:
        query = query.filter(Todo.completed == filters.completed)

    if filters.priority:
        query = query.filter(Todo.priority == filters.priority)

    if filters.search:
        search_term = f"%{filters.search}%"
        query = query.filter(
            or_(
                Todo.title.ilike(search_term),
                Todo.description.ilike(search_term)
            )
        )

    return query.order_by(Todo.created_at.desc()).offset(filters.skip).limit(filters.limit).all()


def get_todo(db: Session, todo_id: int, user_id: int) -> Optional[Todo]:
    return db.query(Todo).filter(
        and_(Todo.id == todo_id, Todo.owner_id == user_id)
    ).first()


def create_todo(db: Session, todo: TodoCreate, user_id: int) -> Todo:
    db_todo = Todo(**todo.dict(), owner_id=user_id)
    db.add(db_todo)
    db.commit()
    db.refresh(db_todo)
    return db_todo


def update_todo(db: Session, todo_id: int, todo_update: TodoUpdate, user_id: int) -> Optional[Todo]:
    db_todo = get_todo(db, todo_id, user_id)
    if not db_todo:
        return None

    update_data = todo_update.dict(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_todo, field, value)

    db.commit()
    db.refresh(db_todo)
    return db_todo


def delete_todo(db: Session, todo_id: int, user_id: int) -> bool:
    db_todo = get_todo(db, todo_id, user_id)
    if not db_todo:
        return False

    db.delete(db_todo)
    db.commit()
    return True


def get_todo_count(db: Session, user_id: int) -> int:
    return db.query(Todo).filter(Todo.owner_id == user_id).count()


def get_completed_todo_count(db: Session, user_id: int) -> int:
    return db.query(Todo).filter(
        and_(Todo.owner_id == user_id, Todo.completed == True)
    ).count()