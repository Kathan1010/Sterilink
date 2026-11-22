from datetime import datetime

from pydantic import BaseModel, field_validator


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str
    username: str


class OperationCreate(BaseModel):
    procedure_id: int
    scheduled_start: datetime

    @field_validator("scheduled_start")
    @classmethod
    def must_be_future(cls, value: datetime) -> datetime:
        now = datetime.now(value.tzinfo) if value.tzinfo else datetime.now()
        if value <= now:
            raise ValueError("scheduled_start must be in the future")
        return value

    @field_validator("procedure_id")
    @classmethod
    def must_be_positive(cls, value: int) -> int:
        if value <= 0:
            raise ValueError("procedure_id must be positive")
        return value


class OperationOut(BaseModel):
    operation_id: int
    procedure_id: int
    procedure_name: str
    user_id: int
    scheduled_start: datetime
    status: str


class BatchOut(BaseModel):
    batch_id: int
    autoclave_id: int
    autoclave_name: str
    start_time: datetime
    expected_end: datetime
    status: str


class OperationPlanResult(BaseModel):
    operation: OperationOut
    planning_status: str
    message: str | None = None
    batches: list[BatchOut] = []
