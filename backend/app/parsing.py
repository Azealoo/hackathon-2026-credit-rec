"""The parser interface shared by the rules parser and the LLM parser (SPEC.md §9.2, §15.7 step 9).

    parser_rules.parse(ocr_text) -> ParsedScreen        sync, deterministic
    parser_llm.parse(ocr_text)   -> ParsedScreen        async; raises on timeout or invalid output
    parse_screen(ocr_text)       -> (ParsedScreen, parser)

PARSER_MODE=llm tries the LLM parser and falls back to the rules parser on any error or after
LLM_DEADLINE_S, so the server answers by ~4.5 s (§9.2). PARSER_MODE=rules (the default when the
variable is unset or unknown) never calls the LLM. parser is "rules", "llm" or "rules_fallback".
"""

import asyncio
import logging
import os
from typing import Literal

from pydantic import BaseModel, ConfigDict

from app.models import Cart, ScreenType

LLM_DEADLINE_S = 4.5

ParserName = Literal["rules", "llm", "rules_fallback"]

log = logging.getLogger("paywise.parsing")


class ParsedScreen(BaseModel):
    """What a parser read from the redacted OCR text. cart is None when the screen is not a
    checkout or is unreadable (an order confirmation keeps its cart)."""

    model_config = ConfigDict(extra="forbid")

    screen_type: ScreenType
    cart: Cart | None


def parser_mode() -> str:
    mode = os.environ.get("PARSER_MODE", "rules").strip().lower()
    return mode if mode in ("rules", "llm") else "rules"


async def parse_screen(ocr_text: str) -> tuple[ParsedScreen, ParserName]:
    from app import parser_rules  # imported here: parser_rules imports ParsedScreen from this module

    if parser_mode() == "llm":
        try:
            from app import parser_llm

            parsed = await asyncio.wait_for(parser_llm.parse(ocr_text), timeout=LLM_DEADLINE_S)
            if not isinstance(parsed, ParsedScreen):
                parsed = ParsedScreen.model_validate(parsed)
            return parsed, "llm"
        except Exception as exc:  # timeout, provider error, invalid output, parser not deployed
            # The exception type only: messages can echo model output, which echoes the OCR text.
            log.warning("LLM parse failed (%s); answering with the rules parser", type(exc).__name__)
        return parser_rules.parse(ocr_text), "rules_fallback"
    return parser_rules.parse(ocr_text), "rules"
