"""Thin synchronous wrapper around the real `mudbase_sdk` (urllib3-based, no
asyncio variant is published), plus small `asyncio.to_thread` adapters so
FastAPI's async handlers never block the event loop on a blocking HTTP call.

Ported verbatim from the sibling `mudbase-showcase-social/python` and
`mudbase-showcase-kanban/python` ports (same SDK version, same platform
quirks) — see those projects' `app/mudbase_client.py` docstrings for the full
history of why the two auth calls below bypass the generated typed wrapper
methods:

`login_sync` bypasses the narrow generated *typed* wrapper method in favor of
the SDK's own public low-level building blocks (`ApiClient.param_serialize` +
`ApiClient.call_api`), which every generated method uses internally:
`login_local_user`'s generated response's nested user model
(`LoginLocalUser200ResponseUser`) only declares
`id/email/firstName/lastName/role/emailVerified/twoFactorEnabled` — it has no
`customRole` field, even though the real Multi-Role feature returns one. This
app needs `customRole` on every login (it's how organizer/attendee is told
apart), so the raw response is parsed directly instead of trusting the
incomplete typed model.

`register_with_role_sync` uses the typed `MultiRoleFeatureApi.register_with_role`
method directly — this SDK version's `RegisterWithRoleRequest` has a required
`agreed_to_terms` field and the operation returns a fully-typed
`RegisterWithRole201Response` with `token`/`refreshToken`/`user` (including
`customRole`), so no raw-JSON workaround is needed here.

This app has no anonymous/guest session (see plan/build-plan.md "Auth
Model") — every one of the two roles (organizer/attendee) signs in with a
real account, so there is no `create_anonymous_session_sync` here, unlike
the social/ecommerce ports.
"""

import json
from typing import Any

import mudbase_sdk
from mudbase_sdk.rest import ApiException  # type: ignore[attr-defined]  # matches the SDK's own generated doc examples

from app.config import get_settings


class MudbaseApiError(Exception):
    """Raised for any non-2xx Mudbase response, typed or raw."""

    def __init__(self, message: str, status_code: int, code: str | None = None) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.code = code


def _build_api_client(access_token: str | None = None) -> mudbase_sdk.ApiClient:
    settings = get_settings()
    configuration = mudbase_sdk.Configuration(host=settings.mudbase_url)
    if access_token:
        configuration.access_token = access_token
    return mudbase_sdk.ApiClient(configuration)


def _raw_json_call(
    api_client: mudbase_sdk.ApiClient,
    method: str,
    resource_path: str,
    path_params: dict[str, str] | None = None,
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Issues a request via the SDK's own public serialize/call primitives and
    parses the JSON body ourselves. See module docstring for why."""
    serialized = api_client.param_serialize(
        method=method,
        resource_path=resource_path,
        path_params=path_params or {},
        query_params=[],
        header_params={"Content-Type": "application/json", "Accept": "application/json"},
        body=body,
        post_params=[],
        files={},
        auth_settings=[],
        collection_formats={},
    )
    response = api_client.call_api(*serialized)
    response.read()  # type: ignore[no-untyped-call]  # mudbase_sdk.rest.RESTResponse.read() ships without a type stub
    raw_text = response.data.decode("utf-8") if response.data else ""
    parsed: dict[str, Any] = json.loads(raw_text) if raw_text else {}

    if not (200 <= response.status < 300):
        message = parsed.get("error") or parsed.get("message") or f"Request failed ({response.status})"
        raise MudbaseApiError(message, response.status, parsed.get("code"))

    return parsed


def _wrap_api_exception(exc: ApiException) -> MudbaseApiError:
    body: dict[str, Any] = {}
    if exc.body:
        try:
            body = json.loads(exc.body)
        except (ValueError, TypeError):
            body = {}
    message = body.get("error") or body.get("message") or exc.reason or "Mudbase request failed"
    return MudbaseApiError(message, exc.status or 500, body.get("code"))


# ─── Auth ───────────────────────────────────────────────────────────────────


def register_with_role_sync(
    role: str,
    email: str,
    password: str,
    first_name: str,
    last_name: str,
    agreed_to_terms: bool,
) -> dict[str, Any]:
    settings = get_settings()
    with _build_api_client() as client:
        api = mudbase_sdk.MultiRoleFeatureApi(client)
        try:
            response = api.register_with_role(
                role,
                mudbase_sdk.RegisterWithRoleRequest(
                    email=email,
                    password=password,
                    firstName=first_name,
                    lastName=last_name,
                    projectId=settings.mudbase_project_id,
                    agreedToTerms=agreed_to_terms,
                ),
            )
        except ApiException as exc:
            raise _wrap_api_exception(exc) from exc
        return response.to_dict()


def login_sync(email: str, password: str) -> dict[str, Any]:
    settings = get_settings()
    with _build_api_client() as client:
        return _raw_json_call(
            client,
            "POST",
            "/api/auth/local/login",
            body={"email": email, "password": password, "projectId": settings.mudbase_project_id},
        )


def refresh_sync(refresh_token: str) -> dict[str, Any]:
    with _build_api_client() as client:
        return _raw_json_call(
            client,
            "POST",
            "/api/auth/refresh",
            body={"refreshToken": refresh_token},
        )


def logout_sync(access_token: str) -> None:
    with _build_api_client(access_token) as client:
        auth_api = mudbase_sdk.AuthenticationApi(client)
        try:
            auth_api.logout_local_user()
        except ApiException:
            # Best-effort: the caller always clears the local session cookie
            # regardless, so a dead/expired token on logout is not fatal.
            return


# ─── Collections (events / bookings / activity) ─────────────────────────────


def list_data_sync(
    collection_id: str,
    *,
    filter_dict: dict[str, Any] | None = None,
    sort: str | None = None,
    page: int = 1,
    limit: int = 20,
    access_token: str | None = None,
) -> dict[str, Any]:
    settings = get_settings()
    with _build_api_client(access_token) as client:
        api = mudbase_sdk.DataApi(client)
        filter_str = json.dumps(filter_dict) if filter_dict else None
        try:
            response = api.list_data(
                settings.mudbase_project_id,
                collection_id,
                page=page,
                limit=limit,
                sort=sort,
                filter=filter_str,
            )
        except ApiException as exc:
            raise _wrap_api_exception(exc) from exc
        items = [item.to_dict() for item in (response.data or [])]
        pagination = response.pagination.to_dict() if response.pagination else None
        return {"data": items, "pagination": pagination}


def get_data_sync(collection_id: str, document_id: str, *, access_token: str | None = None) -> dict[str, Any] | None:
    settings = get_settings()
    with _build_api_client(access_token) as client:
        api = mudbase_sdk.DataApi(client)
        try:
            response = api.get_data(settings.mudbase_project_id, collection_id, document_id)
        except ApiException as exc:
            if exc.status == 404:
                return None
            raise _wrap_api_exception(exc) from exc
        return response.data or {}


def create_data_sync(collection_id: str, body: dict[str, Any], *, access_token: str) -> dict[str, Any]:
    settings = get_settings()
    with _build_api_client(access_token) as client:
        api = mudbase_sdk.DataApi(client)
        try:
            response = api.create_data(settings.mudbase_project_id, collection_id, body)
        except ApiException as exc:
            raise _wrap_api_exception(exc) from exc
        return response.data or {}


def update_data_sync(
    collection_id: str,
    document_id: str,
    body: dict[str, Any],
    *,
    access_token: str,
) -> dict[str, Any]:
    settings = get_settings()
    with _build_api_client(access_token) as client:
        api = mudbase_sdk.DataApi(client)
        try:
            response = api.update_data(settings.mudbase_project_id, collection_id, document_id, body)
        except ApiException as exc:
            raise _wrap_api_exception(exc) from exc
        return response.data or {}


def delete_data_sync(collection_id: str, document_id: str, *, access_token: str) -> None:
    settings = get_settings()
    with _build_api_client(access_token) as client:
        api = mudbase_sdk.DataApi(client)
        try:
            api.delete_data(settings.mudbase_project_id, collection_id, document_id)
        except ApiException as exc:
            raise _wrap_api_exception(exc) from exc
