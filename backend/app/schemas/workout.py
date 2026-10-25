from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator


class ExerciseSetIn(BaseModel):
    position: int = Field(ge=1, le=100)
    reps: int = Field(ge=0, le=999)
    weight: float | None = Field(default=None, ge=0, le=1500)
    set_type: Literal['work', 'warmup'] = 'work'
    rpe: float | None = Field(default=None, ge=0, le=10)
    notes: str | None = Field(default=None, max_length=500)


class ExerciseSetOut(ExerciseSetIn):
    id: int

    model_config = {'from_attributes': True}


class WorkoutExerciseIn(BaseModel):
    catalog_exercise_id: int | None = None
    exercise_name: str = Field(min_length=1, max_length=120)
    position: int = Field(ge=1, le=50)
    notes: str | None = Field(default=None, max_length=500)
    sets: list[ExerciseSetIn] = Field(default_factory=list, max_length=50)


class WorkoutExerciseOut(WorkoutExerciseIn):
    id: int
    sets: list[ExerciseSetOut]

    model_config = {'from_attributes': True}


class WorkoutCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    notes: str | None = Field(default=None, max_length=1000)
    started_at: datetime
    finished_at: datetime | None = None
    exercises: list[WorkoutExerciseIn] = Field(default_factory=list, max_length=50)

    @model_validator(mode='after')
    def finished_after_started(self) -> 'WorkoutCreate':
        if self.finished_at is not None and self.finished_at < self.started_at:
            raise ValueError('finished_at must be >= started_at')
        return self


class WorkoutUpdate(WorkoutCreate):
    pass


class WorkoutOut(BaseModel):
    id: int
    name: str
    notes: str | None
    started_at: datetime
    finished_at: datetime | None
    exercises: list[WorkoutExerciseOut]

    model_config = {'from_attributes': True}


class TemplateExerciseIn(BaseModel):
    catalog_exercise_id: int | None = None
    exercise_name: str = Field(min_length=1, max_length=120)
    position: int = Field(ge=1, le=50)
    target_sets: int = Field(default=3, ge=1, le=20)
    target_reps: str | None = Field(default=None, max_length=40)
    target_weight: float | None = Field(default=None, ge=0, le=1500)


class TemplateExerciseOut(TemplateExerciseIn):
    id: int

    model_config = {'from_attributes': True}


class TemplateCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    notes: str | None = Field(default=None, max_length=1000)
    exercises: list[TemplateExerciseIn] = Field(default_factory=list, max_length=50)


class TemplateOut(BaseModel):
    id: int
    name: str
    notes: str | None
    exercises: list[TemplateExerciseOut]
    share_token: str | None = None

    model_config = {'from_attributes': True}


class TemplateSharedOut(BaseModel):
    name: str
    exercises: list[TemplateExerciseOut]

    model_config = {'from_attributes': True}


class ExerciseCatalogCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    primary_muscle: str = Field(min_length=1, max_length=40)
    secondary_muscles: list[str] = Field(default_factory=list, max_length=10)


class ExerciseCatalogUpdate(ExerciseCatalogCreate):
    pass


class ExerciseCatalogOut(BaseModel):
    id: int
    name: str
    slug: str
    primary_muscle: str
    secondary_muscles: list[str]

    model_config = {'from_attributes': True}
