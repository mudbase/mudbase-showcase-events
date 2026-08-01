"""Mirrors the zod schemas in ../web/src/components/auth/RegisterForm.tsx and
LoginForm.tsx. Unlike the sibling social/ecommerce ports (a single default
`customer` role, no selector), this app has a real two-role signup — the
form's `role` field drives which of Mudbase's two provisioned signup slugs
(`organizer`/`attendee`) the registration is submitted against."""

from typing import Literal

from pydantic import BaseModel, EmailStr, Field, field_validator

AppRole = Literal["organizer", "attendee"]


class LoginFormValues(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1)


class RegisterFormValues(BaseModel):
    role: AppRole
    first_name: str = Field(min_length=1)
    last_name: str = Field(min_length=1)
    email: EmailStr
    password: str = Field(min_length=8)
    agreed_to_terms: bool

    @field_validator("agreed_to_terms")
    @classmethod
    def _must_agree(cls, value: bool) -> bool:
        if not value:
            raise ValueError("You must agree to the Terms of Service and Privacy Policy.")
        return value
