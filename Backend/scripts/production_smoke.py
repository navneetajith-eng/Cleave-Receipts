#!/usr/bin/env python3
"""Run Cleave's destructive, disposable production smoke test.

The script creates three random Supabase users, exercises the deployed API, and
removes all generated data even if an assertion fails. Secrets are accepted only
through environment variables and are never printed.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path
from typing import Any


class SmokeFailure(RuntimeError):
    pass


@dataclass
class Response:
    status: int
    body: bytes
    elapsed_ms: int
    headers: Any

    def json(self) -> Any:
        if not self.body:
            return None
        return json.loads(self.body.decode("utf-8"))


@dataclass
class User:
    label: str
    email: str
    password: str
    username: str
    id: str | None = None
    token: str | None = None


@dataclass
class RunState:
    users: list[User] = field(default_factory=list)
    group_id: str | None = None
    timings: dict[str, int] = field(default_factory=dict)


class Client:
    def __init__(self, *, api_base: str, supabase_url: str, publishable_key: str, secret_key: str):
        self.api_base = api_base.rstrip("/") + "/"
        self.supabase_url = supabase_url.rstrip("/")
        self.publishable_key = publishable_key
        self.secret_key = secret_key

    def request(
        self,
        method: str,
        url: str,
        *,
        token: str | None = None,
        json_body: Any = None,
        body: bytes | None = None,
        content_type: str | None = None,
        admin: bool = False,
        publishable: bool = False,
    ) -> Response:
        headers = {"Accept": "application/json"}
        if admin:
            headers["apikey"] = self.secret_key
            headers["Authorization"] = f"Bearer {self.secret_key}"
        elif publishable:
            headers["apikey"] = self.publishable_key
        elif token:
            headers["Authorization"] = f"Bearer {token}"
        if json_body is not None:
            body = json.dumps(json_body).encode("utf-8")
            content_type = "application/json"
        if content_type:
            headers["Content-Type"] = content_type
        request = urllib.request.Request(url, data=body, headers=headers, method=method)
        started = time.perf_counter()
        try:
            with urllib.request.urlopen(request, timeout=60) as result:
                response_body = result.read()
                status = result.status
                response_headers = result.headers
        except urllib.error.HTTPError as error:
            response_body = error.read()
            status = error.code
            response_headers = error.headers
        except urllib.error.URLError as error:
            raise SmokeFailure(f"Network request failed: {error.reason}") from error
        return Response(
            status=status,
            body=response_body,
            elapsed_ms=round((time.perf_counter() - started) * 1000),
            headers=response_headers,
        )

    def api(self, method: str, path: str, *, user: User | None = None, **kwargs: Any) -> Response:
        token = user.token if user else None
        return self.request(method, urllib.parse.urljoin(self.api_base, path.lstrip("/")), token=token, **kwargs)

    def admin(self, method: str, path: str, **kwargs: Any) -> Response:
        return self.request(
            method,
            f"{self.supabase_url}/auth/v1/admin/{path.lstrip('/')}",
            admin=True,
            **kwargs,
        )

    def create_user(self, user: User) -> None:
        response = self.admin(
            "POST",
            "users",
            json_body={
                "email": user.email,
                "password": user.password,
                "email_confirm": True,
                "user_metadata": {"username": user.username},
            },
        )
        expect(response, {200, 201}, f"create auth user {user.label}")
        payload = response.json()
        user.id = payload.get("id") or payload.get("user", {}).get("id")
        if not user.id:
            raise SmokeFailure(f"create auth user {user.label}: response had no user ID")

    def sign_in(self, user: User) -> None:
        response = self.request(
            "POST",
            f"{self.supabase_url}/auth/v1/token?grant_type=password",
            json_body={"email": user.email, "password": user.password},
            content_type="application/json",
            publishable=True,
        )
        # Supabase OAuth/Auth endpoints may return any successful 2xx status.
        expect(response, range(200, 300), f"sign in {user.label}")
        user.token = response.json().get("access_token")
        if not user.token:
            raise SmokeFailure(f"sign in {user.label}: response had no access token")


def expect(response: Response, statuses: Any, action: str) -> Response:
    if response.status not in statuses:
        detail = ""
        try:
            payload = response.json()
            detail = payload.get("detail") or payload.get("message") or payload.get("msg") or ""
        except (ValueError, AttributeError):
            pass
        suffix = f": {detail}" if detail else ""
        raise SmokeFailure(f"{action}: expected {sorted(statuses)}, got HTTP {response.status}{suffix}")
    return response


def multipart_file(path: Path, field_name: str = "file") -> tuple[bytes, str]:
    boundary = f"cleave-{uuid.uuid4().hex}"
    mime_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    prefix = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="{field_name}"; filename="{path.name}"\r\n'
        f"Content-Type: {mime_type}\r\n\r\n"
    ).encode("utf-8")
    body = prefix + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode("utf-8")
    return body, f"multipart/form-data; boundary={boundary}"


def money(value: Any) -> Decimal:
    return Decimal(str(value)).quantize(Decimal("0.01"))


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise SmokeFailure(message)


def print_check(name: str, elapsed_ms: int | None = None) -> None:
    timing = f" ({elapsed_ms} ms)" if elapsed_ms is not None else ""
    print(f"PASS  {name}{timing}", flush=True)


def run(client: Client, state: RunState, image_path: Path, exercise_parser: bool) -> None:
    health = expect(client.request("GET", client.api_base.removesuffix("api/") + "health"), {200}, "health")
    health_payload = health.json()
    assert_true(
        health_payload.get("status") == "ok" and health_payload.get("api_version") == 3,
        "health returned an unexpected payload",
    )
    capabilities = expect(client.api("GET", "capabilities"), {200}, "capabilities").json()
    required_features = {
        "receipt_review",
        "payment_status",
        "profile_settings",
        "scan_idempotency",
        "individual_receipt_claims",
        "receipt_deletion",
        "group_leave",
        "display_names",
        "receipt_currencies",
        "friend_profiles",
    }
    assert_true(
        capabilities.get("api_version") == 3
        and required_features.issubset(set(capabilities.get("features", []))),
        "capabilities are missing required release features",
    )
    print_check("health and database readiness", health.elapsed_ms)

    expect(client.api("GET", "groups"), {401}, "missing-token authorization boundary")
    invalid = client.request("GET", urllib.parse.urljoin(client.api_base, "groups"), token="invalid-token")
    expect(invalid, {401}, "invalid-token authorization boundary")
    print_check("missing and invalid tokens are rejected")

    suffix = uuid.uuid4().hex[:12]
    for label in ("A", "B", "outsider"):
        user = User(
            label=label,
            email=f"cleave-smoke-{label.lower()}-{suffix}@example.invalid",
            password=secrets.token_urlsafe(32),
            username=f"smoke-{label.lower()}-{suffix}",
        )
        state.users.append(user)
        client.create_user(user)
        client.sign_in(user)
        bootstrap = expect(
            client.api(
                "POST",
                "profiles/bootstrap",
                user=user,
                json_body={
                    "username": user.username,
                    "display_name": f"Smoke {label}",
                    "email": user.email,
                },
            ),
            {200},
            f"bootstrap profile {label}",
        )
        assert_true(bootstrap.json()["id"] == user.id, f"profile {label} does not match auth identity")
        assert_true(
            bootstrap.json()["display_name"] == f"Smoke {label}",
            f"profile {label} display name did not persist",
        )
    a, b, outsider = state.users
    print_check("three disposable auth identities and profiles")

    created = expect(
        client.api(
            "POST",
            "groups",
            user=a,
            json_body={"name": f"Production smoke {suffix}", "is_collaborative": True, "member_ids": []},
        ),
        {201},
        "create collaborative group",
    )
    state.timings["group_create_ms"] = created.elapsed_ms
    group = created.json()
    state.group_id = group["id"]
    assert_true(group["is_collaborative"] is True, "group lost collaborative mode")
    assert_true({member["id"] for member in group["members"]} == {a.id}, "creator membership is incorrect")
    print_check("collaborative group creation", created.elapsed_ms)

    added = expect(
        client.api("POST", f"groups/{state.group_id}/members", user=a, json_body={"user_id": b.id}),
        {200},
        "add account B",
    )
    state.timings["member_add_ms"] = added.elapsed_ms
    assert_true({member["id"] for member in added.json()["members"]} == {a.id, b.id}, "member add did not persist")
    print_check("add account B", added.elapsed_ms)

    groups_b = expect(client.api("GET", "groups", user=b), {200}, "fetch B groups")
    assert_true(state.group_id in {group["id"] for group in groups_b.json()}, "B cannot see the shared group")
    groups_outsider = expect(client.api("GET", "groups", user=outsider), {200}, "fetch outsider groups")
    assert_true(state.group_id not in {group["id"] for group in groups_outsider.json()}, "outsider can see the private group")

    friends_a = expect(client.api("GET", "friends", user=a), {200}, "fetch A friends").json()
    friends_b = expect(client.api("GET", "friends", user=b), {200}, "fetch B friends").json()
    assert_true(b.id in {profile["id"] for profile in friends_a}, "B is missing from A's friends")
    assert_true(a.id in {profile["id"] for profile in friends_b}, "A is missing from B's friends")
    friend_b = expect(client.api("GET", f"friends/{b.id}", user=a), {200}, "fetch B friend profile").json()
    assert_true(
        friend_b["display_name"] == "Smoke B" and friend_b["username"] == b.username,
        "friend profile lost display name or username",
    )
    expect(client.api("GET", f"friends/{b.id}", user=outsider), {404}, "hide B from non-friend")

    inbox = expect(client.api("GET", "inbox", user=b), {200}, "fetch B inbox").json()
    invitation = next((item for item in inbox if item["group_id"] == state.group_id), None)
    assert_true(invitation is not None and invitation["kind"] == "group_added", "B received no group inbox event")
    read_item = expect(client.api("POST", f"inbox/{invitation['id']}/read", user=b), {200}, "mark inbox event read")
    assert_true(read_item.json()["is_read"] is True, "inbox read state did not persist")
    print_check("cross-device groups, friends, and inbox")

    manual = expect(
        client.api(
            "POST",
            f"groups/{state.group_id}/receipts/manual",
            user=a,
            json_body={
                "title": "Smoke dinner",
                "tax_amount": 1.01,
                "tip_amount": 2.02,
                "discount_amount": 0.03,
                "currency_code": "INR",
                "items": [
                    {"name": "Starter", "price": 10.01},
                    {"name": "Main", "price": 20.02},
                    {"name": "Dessert", "price": 30.03},
                ],
            },
        ),
        {200},
        "create manual receipt",
    )
    receipt = manual.json()
    receipt_id = receipt["id"]
    assert_true(receipt["currency_code"] == "INR", "manual receipt currency did not persist")
    edited_items = [
        {"id": item["id"], "name": f"{item['name']} edited", "price": item["price"]}
        for item in receipt["items"]
    ]
    edited = expect(
        client.api(
            "PATCH",
            f"receipts/{receipt_id}",
            user=a,
            json_body={
                "title": "Smoke dinner edited",
                "tax_amount": 1.01,
                "tip_amount": 2.02,
                "discount_amount": 0.03,
                "items": edited_items,
            },
        ),
        {200},
        "edit receipt",
    )
    assert_true(edited.json()["title"] == "Smoke dinner edited", "receipt edit did not persist")

    items = edited.json()["items"]
    assert_true(
        {participant["user_id"] for participant in edited.json()["participants"]} == {a.id, b.id},
        "receipt participant snapshot is incomplete",
    )
    expect(
        client.api(
            "PUT",
            f"receipts/{receipt_id}/claim",
            user=a,
            json_body={"item_ids": [items[0]["id"], items[2]["id"]]},
        ),
        {200},
        "submit A claims",
    )
    expect(
        client.api(
            "PUT",
            f"receipts/{receipt_id}/claim",
            user=b,
            json_body={"item_ids": [items[1]["id"], items[2]["id"]]},
        ),
        {200},
        "submit B claims",
    )

    assignment_payload = {
        "items": [
            {"item_id": items[0]["id"], "user_ids": [a.id]},
            {"item_id": items[1]["id"], "user_ids": [b.id]},
            {"item_id": items[2]["id"], "user_ids": [a.id, b.id]},
        ]
    }
    forbidden_assignment = json.loads(json.dumps(assignment_payload))
    forbidden_assignment["items"][0]["user_ids"] = [outsider.id]
    expect(
        client.api("PATCH", f"receipts/{receipt_id}/assignments", user=a, json_body=forbidden_assignment),
        {400},
        "reject non-member assignment",
    )

    balances_a = expect(client.api("GET", f"receipts/{receipt_id}/balances", user=a), {200}, "fetch A balances")
    balances_b = expect(client.api("GET", f"receipts/{receipt_id}/balances", user=b), {200}, "fetch B balances")
    assert_true(balances_a.json() == balances_b.json(), "members received different balances")
    allocated = sum((money(balance["total_owed"]) for balance in balances_a.json()), Decimal("0.00"))
    assert_true(allocated == Decimal("63.06"), f"allocated total {allocated} does not reconcile to 63.06")
    print_check("individual receipt claims and exact cent reconciliation")

    receipts_b = expect(client.api("GET", f"groups/{state.group_id}/receipts", user=b), {200}, "fetch B receipts")
    persisted = next((value for value in receipts_b.json() if value["id"] == receipt_id), None)
    assert_true(
        persisted is not None
        and persisted["title"] == "Smoke dinner edited"
        and persisted["currency_code"] == "INR",
        "B cannot see the edited receipt with its original currency",
    )
    expect(client.api("GET", f"groups/{state.group_id}/receipts", user=outsider), {403}, "block outsider receipt list")
    expect(client.api("GET", f"receipts/{receipt_id}/balances", user=outsider), {403}, "block outsider balances")
    print_check("receipt visibility and non-member authorization")

    rating = expect(
        client.api("PUT", f"receipts/{receipt_id}/experience", user=b, json_body={"rating": 4}),
        {200},
        "create rating",
    )
    updated_rating = expect(
        client.api("PUT", f"receipts/{receipt_id}/experience", user=b, json_body={"rating": 5}),
        {200},
        "update rating",
    )
    assert_true(rating.json()["user_id"] == b.id and updated_rating.json()["rating"] == 5, "rating upsert failed")
    fetched_rating = expect(
        client.api("GET", f"receipts/{receipt_id}/experience", user=b),
        {200},
        "reload rating",
    )
    assert_true(fetched_rating.json()["rating"] == 5, "rating did not persist across a fresh request")

    image_body, image_content_type = multipart_file(image_path)
    memory = expect(
        client.api(
            "POST",
            f"receipts/{receipt_id}/memories",
            user=b,
            body=image_body,
            content_type=image_content_type,
        ),
        {201},
        "upload private memory",
    ).json()
    content = expect(
        client.api("GET", f"receipts/{receipt_id}/memories/{memory['id']}/content", user=a),
        {200},
        "fetch private memory as member",
    )
    assert_true(content.body == image_path.read_bytes(), "downloaded private memory differs from upload")
    expect(
        client.api("GET", f"receipts/{receipt_id}/memories/{memory['id']}/content", user=outsider),
        {403},
        "block outsider memory",
    )
    relaunched = expect(client.api("GET", f"groups/{state.group_id}/receipts", user=a), {200}, "refetch receipt after memory upload")
    persisted_receipt = next(value for value in relaunched.json() if value["id"] == receipt_id)
    assert_true(memory["id"] in {value["id"] for value in persisted_receipt["memories"]}, "private memory did not persist")
    print_check("private memory persistence and authorization")

    if exercise_parser:
        parse_body, parse_content_type = multipart_file(image_path)
        parsed = expect(
            client.api(
                "POST",
                "receipts/parse",
                user=a,
                body=parse_body,
                content_type=parse_content_type,
            ),
            {200},
            "parse production receipt image",
        )
        parsed_payload = parsed.json()
        assert_true(parsed_payload.get("vendor_name") and parsed_payload.get("line_items"), "parser returned no vendor or items")
        state.timings["receipt_parse_ms"] = parsed.elapsed_ms
        print_check("production receipt parsing", parsed.elapsed_ms)

    deletion = expect(client.api("DELETE", "profiles/me", user=b), {204}, "delete account B")
    state.timings["account_delete_ms"] = deletion.elapsed_ms
    deleted_auth = client.admin("GET", f"users/{b.id}")
    expect(deleted_auth, {404}, "verify B auth deletion")
    deleted_profile = client.api("GET", "profiles/me", user=b)
    expect(deleted_profile, {401, 404}, "verify B profile deletion")
    after_delete = expect(client.api("GET", f"groups/{state.group_id}/receipts", user=a), {200}, "refetch after B deletion")
    surviving_receipt = next(value for value in after_delete.json() if value["id"] == receipt_id)
    assert_true(memory["id"] not in {value["id"] for value in surviving_receipt["memories"]}, "B's memory metadata survived account deletion")
    b.token = None
    print_check("account deletion removes auth, profile, and private media", deletion.elapsed_ms)


def cleanup(client: Client, state: RunState) -> list[str]:
    errors: list[str] = []
    owner = next((user for user in state.users if user.label == "A"), None)
    if state.group_id and owner and owner.token:
        response = client.api("POST", f"groups/{state.group_id}/leave", user=owner)
        if response.status not in {204, 404}:
            errors.append(f"group cleanup returned HTTP {response.status}")
    for user in reversed(state.users):
        if user.id is None:
            continue
        if user.token:
            response = client.api("DELETE", "profiles/me", user=user)
            if response.status in {204, 401, 404}:
                user.token = None
        # Auth Admin is an idempotent last-resort cleanup for partial runs.
        response = client.admin("DELETE", f"users/{user.id}")
        if response.status not in {200, 204, 404}:
            errors.append(f"auth cleanup for {user.label} returned HTTP {response.status}")
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-base", required=True, help="Deployed base URL ending in /api/")
    parser.add_argument("--supabase-url", required=True, help="Supabase project URL")
    parser.add_argument("--image", type=Path, required=True, help="A real PNG/JPEG receipt fixture")
    parser.add_argument("--skip-parser", action="store_true", help="Skip the variable-cost Gemini parser check")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    publishable_key = os.environ.get("CLEAVE_SUPABASE_PUBLISHABLE_KEY", "").strip()
    secret_key = os.environ.get("CLEAVE_SUPABASE_SECRET_KEY", "").strip()
    if not publishable_key or not secret_key:
        print(
            "Set CLEAVE_SUPABASE_PUBLISHABLE_KEY and CLEAVE_SUPABASE_SECRET_KEY in the environment.",
            file=sys.stderr,
        )
        return 2
    if not args.image.is_file():
        print(f"Receipt fixture does not exist: {args.image}", file=sys.stderr)
        return 2

    client = Client(
        api_base=args.api_base,
        supabase_url=args.supabase_url,
        publishable_key=publishable_key,
        secret_key=secret_key,
    )
    state = RunState()
    failure: Exception | None = None
    try:
        run(client, state, args.image, exercise_parser=not args.skip_parser)
    except Exception as error:  # Cleanup must also run after unexpected decoding errors.
        failure = error
    cleanup_errors = cleanup(client, state)

    if cleanup_errors:
        print("CLEANUP FAILED: " + "; ".join(cleanup_errors), file=sys.stderr)
        return 1
    print("PASS  cleanup removed all disposable production data", flush=True)
    if failure:
        print(f"FAIL  {failure}", file=sys.stderr)
        return 1
    print("\nProduction smoke test passed.")
    for name, elapsed_ms in state.timings.items():
        print(f"  {name}: {elapsed_ms} ms")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
