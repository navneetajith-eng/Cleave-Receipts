import pytest
from fastapi import HTTPException
from sqlalchemy.exc import OperationalError

from app.main import health, ready


class HealthyDatabase:
    def execute(self, _query):
        return 1


class UnavailableDatabase:
    def execute(self, _query):
        raise OperationalError("SELECT 1", {}, Exception("offline"))


def test_health_and_readiness_check_the_database():
    database = HealthyDatabase()

    expected = {"status": "ok", "api_version": 3}
    assert health(database) == expected
    assert ready(database) == expected


@pytest.mark.parametrize("endpoint", [health, ready])
def test_health_endpoints_return_503_when_database_is_unavailable(endpoint):
    with pytest.raises(HTTPException) as error:
        endpoint(UnavailableDatabase())

    assert error.value.status_code == 503
