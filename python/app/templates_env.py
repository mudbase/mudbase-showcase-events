"""Shared Jinja2Templates instance + custom filters, importable by every
router without risking a circular import with main.py."""

from pathlib import Path

from fastapi.templating import Jinja2Templates

from app.services.qrcode_service import qr_data_uri
from app.utils import capacity_badge, format_date, initial, relative_time

TEMPLATES_DIR = Path(__file__).parent / "templates"

templates = Jinja2Templates(directory=str(TEMPLATES_DIR))
templates.env.filters["date"] = format_date
templates.env.filters["relative_time"] = relative_time
templates.env.filters["initial"] = initial
templates.env.filters["qr"] = qr_data_uri
templates.env.filters["badge_class"] = lambda confirmed, capacity: capacity_badge(confirmed, capacity)[0]
templates.env.filters["badge_label"] = lambda confirmed, capacity: capacity_badge(confirmed, capacity)[1]
