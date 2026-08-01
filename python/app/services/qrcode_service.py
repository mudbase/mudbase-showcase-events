"""Renders a booking's `qrToken` as a real, scannable QR code — a base64
PNG data URI embedded directly in the HTML, no separate image route and no
client-side JS needed. Mirrors the visual intent of the reference web app's
`<QRCodeSVG value={booking.qrToken} />` (see
../web/src/components/bookings/BookingCard.tsx), just rendered server-side
with the pure-Python `qrcode` library instead of a browser-side SVG
component, matching this port's "no bundler, no client JS" architecture.
"""

import base64
import io

import qrcode

_BOX_SIZE = 6
_BORDER = 2


def qr_data_uri(token: str) -> str:
    image = qrcode.make(token, box_size=_BOX_SIZE, border=_BORDER)
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    encoded = base64.b64encode(buffer.getvalue()).decode("ascii")
    return f"data:image/png;base64,{encoded}"
