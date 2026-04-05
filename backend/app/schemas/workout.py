from datetime import datetime

from pydantic import BaseModel, Field


class ExerciseSetIn(BaseModel):
    position: int = Field(ge=1)
    reps: int = Field(ge=0)
    weight: float | None = Field(default=None, ge=0)
    rpe: float | None = Field(default=None, ge=0, le=10)
    notes: str | None = None


class ExerciseSetOut(ExerciseSetIn):
    id: int

    model_config = {'from_attributes': True}


class WorkoutExerciseIn(BaseModel):
    catalog_exercise_id: int | None = None
    exercise_name: str = Field(min_length=1, max_length=120)
    position: int = Field(ge=1)
    notes: str | None = None
    sets: list[ExerciseSetIn] = Field(default_factory=list)


class WorkoutExerciseOut(WorkoutExerciseIn):
    id: int
    sets: list[ExerciseSetOut]

    model_config = {'from_attributes': True}


class WorkoutCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    notes: str | None = None
    started_at: datetime
    finished_at: datetime | None = None
    exercises: list[WorkoutExerciseIn] = Field(default_factory=list)


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
    position: int = Field(ge=1)
    target_sets: int = Field(default=3, ge=1)
    target_reps: str | None = Field(default=None, max_length=40)
    target_weight: float | None = Field(default=None, ge=0)


class TemplateExerciseOut(TemplateExerciseIn):
    id: int

    model_config = {'from_attributes': True}


class TemplateCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    notes: str | None = None
    exercises: list[TemplateExerciseIn] = Field(default_factory=list)


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
    secondary_muscles: list[str] = Field(default_factory=list)


class ExerciseCatalogUpdate(ExerciseCatalogCreate):
    pass


class ExerciseCatalogOut(BaseModel):
    id: int
    name: str
    slug: str
    primary_muscle: str
    secondary_muscles: list[str]

    model_config = {'from_attributes': True}
