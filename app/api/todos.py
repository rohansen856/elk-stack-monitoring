from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List
from app.database import get_db
from app.schemas.todo import TodoCreate, TodoUpdate, TodoResponse, TodoFilter, PriorityEnum
from app.crud.todo import get_todos, get_todo, create_todo, update_todo, delete_todo, get_todo_count, get_completed_todo_count
from app.api.auth import get_current_active_user
from app.cache import cache
import structlog

logger = structlog.get_logger()
router = APIRouter()


@router.get("/", response_model=List[TodoResponse])
async def read_todos(
    completed: bool = Query(None, description="Filter by completion status"),
    priority: PriorityEnum = Query(None, description="Filter by priority"),
    search: str = Query(None, description="Search in title and description"),
    skip: int = Query(0, ge=0, description="Number of items to skip"),
    limit: int = Query(100, ge=1, le=1000, description="Number of items to return"),
    current_user = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    cache_key = f"todos:user:{current_user.id}:completed:{completed}:priority:{priority}:search:{search}:skip:{skip}:limit:{limit}"

    cached_todos = await cache.get(cache_key)
    if cached_todos:
        logger.info("Cache hit for todos", user_id=current_user.id)
        return cached_todos

    filters = TodoFilter(
        completed=completed,
        priority=priority,
        search=search,
        skip=skip,
        limit=limit
    )

    todos = get_todos(db=db, user_id=current_user.id, filters=filters)
    todo_responses = [TodoResponse.from_orm(todo) for todo in todos]

    await cache.set(cache_key, [todo.dict() for todo in todo_responses], expire=60)
    logger.info("Todos retrieved", user_id=current_user.id, count=len(todos))

    return todo_responses


@router.post("/", response_model=TodoResponse)
async def create_new_todo(
    todo: TodoCreate,
    current_user = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    db_todo = create_todo(db=db, todo=todo, user_id=current_user.id)

    await cache.delete_pattern(f"todos:user:{current_user.id}:*")
    logger.info("Todo created", user_id=current_user.id, todo_id=db_todo.id)

    return TodoResponse.from_orm(db_todo)


@router.get("/{todo_id}", response_model=TodoResponse)
async def read_todo(
    todo_id: int,
    current_user = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    cache_key = f"todo:{todo_id}:user:{current_user.id}"

    cached_todo = await cache.get(cache_key)
    if cached_todo:
        logger.info("Cache hit for todo", user_id=current_user.id, todo_id=todo_id)
        return cached_todo

    db_todo = get_todo(db=db, todo_id=todo_id, user_id=current_user.id)
    if db_todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")

    todo_response = TodoResponse.from_orm(db_todo)
    await cache.set(cache_key, todo_response.dict(), expire=300)

    return todo_response


@router.put("/{todo_id}", response_model=TodoResponse)
async def update_existing_todo(
    todo_id: int,
    todo_update: TodoUpdate,
    current_user = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    db_todo = update_todo(db=db, todo_id=todo_id, todo_update=todo_update, user_id=current_user.id)
    if db_todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")

    await cache.delete(f"todo:{todo_id}:user:{current_user.id}")
    await cache.delete_pattern(f"todos:user:{current_user.id}:*")
    logger.info("Todo updated", user_id=current_user.id, todo_id=todo_id)

    return TodoResponse.from_orm(db_todo)


@router.delete("/{todo_id}")
async def delete_existing_todo(
    todo_id: int,
    current_user = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    success = delete_todo(db=db, todo_id=todo_id, user_id=current_user.id)
    if not success:
        raise HTTPException(status_code=404, detail="Todo not found")

    await cache.delete(f"todo:{todo_id}:user:{current_user.id}")
    await cache.delete_pattern(f"todos:user:{current_user.id}:*")
    logger.info("Todo deleted", user_id=current_user.id, todo_id=todo_id)

    return {"message": "Todo deleted successfully"}


@router.get("/stats/summary")
async def get_todo_stats(
    current_user = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    cache_key = f"stats:user:{current_user.id}"

    cached_stats = await cache.get(cache_key)
    if cached_stats:
        logger.info("Cache hit for stats", user_id=current_user.id)
        return cached_stats

    total_todos = get_todo_count(db=db, user_id=current_user.id)
    completed_todos = get_completed_todo_count(db=db, user_id=current_user.id)
    pending_todos = total_todos - completed_todos

    stats = {
        "total_todos": total_todos,
        "completed_todos": completed_todos,
        "pending_todos": pending_todos,
        "completion_rate": round((completed_todos / total_todos * 100), 2) if total_todos > 0 else 0
    }

    await cache.set(cache_key, stats, expire=120)
    return stats