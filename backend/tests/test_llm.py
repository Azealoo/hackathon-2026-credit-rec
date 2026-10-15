"""app/llm.py offline: request shape, failure handling, budget cap, classify_cause, no content logging.

The SDK client is replaced by a fake; nothing here reaches the network.
"""

import asyncio
import datetime as dt
import json
import logging
import time
from types import SimpleNamespace

import anthropic
import httpx2
import pytest

from app import llm

SCHEMA = {"type": "object", "properties": {"a": {"type": "string"}}, "required": ["a"], "additionalProperties": False}
REQUEST = httpx2.Request("POST", "https://api.example.test/v1/messages")


def response(text='{"a": "x"}', stop="end_turn", content=None):
    blocks = content if content is not None else [SimpleNamespace(type="text", text=text)]
    return SimpleNamespace(stop_reason=stop, content=blocks, usage=SimpleNamespace(input_tokens=10, output_tokens=5))


class FakeClient:
    """Stands in for anthropic.AsyncAnthropic: records each create() call.

    `script` gives (delay_s, error) per call in order; calls past its end use delay/error.
    """

    def __init__(self, result=None, delay=0.0, error=None, script=()):
        self.calls, self.beta_calls = [], []
        self.result, self.delay, self.error, self.script = result or response(), delay, error, list(script)
        self.messages = SimpleNamespace(create=self._create(self.calls))
        self.beta = SimpleNamespace(messages=SimpleNamespace(create=self._create(self.beta_calls)))

    def _create(self, log):
        async def create(**kwargs):
            n = len(self.calls) + len(self.beta_calls)
            log.append(kwargs)
            delay, error = self.script[n] if n < len(self.script) else (self.delay, self.error)
            if delay:
                await asyncio.sleep(delay)
            if error:
                raise error
            return self.result

        return create


@pytest.fixture(autouse=True)
def env(monkeypatch):
    monkeypatch.setenv("LLM_API_KEY", "test-key-not-real")
    monkeypatch.delenv("LLM_MODEL", raising=False)
    monkeypatch.delenv("LLM_DAILY_CAP", raising=False)
    monkeypatch.delenv("LLM_INFERENCE_GEO", raising=False)
    monkeypatch.delenv("LLM_HEDGE_AFTER_S", raising=False)
    llm.reset_budget()
    yield
    llm.reset_budget()


@pytest.fixture
def fake(monkeypatch):
    client = FakeClient()
    monkeypatch.setattr(llm, "_get_client", lambda api_key: client)
    return client


def call(**overrides):
    kwargs = dict(system="sys", user="usr", schema=SCHEMA, max_tokens=100, timeout_s=1.0) | overrides
    return asyncio.run(llm.complete_json(**kwargs))


# --- Request shape -------------------------------------------------------------------------------


def test_default_request_is_haiku_with_schema_output_and_thinking_off(fake):
    assert call() == {"a": "x"}
    (sent,) = fake.calls
    assert sent["model"] == "claude-haiku-5-5"
    assert sent["output_config"] == {"effort": "low", "format": {"type": "json_schema", "schema": SCHEMA}}
    assert sent["thinking"] == {"type": "disabled"}
    assert sent["max_tokens"] == 100
    assert sent["messages"] == [{"role": "user", "content": "usr"}]
    assert sent["system"] == [{"type": "text", "text": "sys", "cache_control": {"type": "ephemeral"}}]
    assert sent["timeout"].read == 1.0 and sent["timeout"].connect <= 1.0
    assert sent["inference_geo"] == "us"
    for banned in ("temperature", "top_p", "top_k"):  # 400 on Haiku 5.5
        assert banned not in sent
    assert fake.beta_calls == []


@pytest.mark.parametrize("value, geo", [("global", "global"), ("US", "us"), ("eu", "us"), ("", "us")])
def test_inference_geo_comes_from_env_with_us_default(fake, monkeypatch, value, geo):
    monkeypatch.setenv("LLM_INFERENCE_GEO", value)
    call()
    assert fake.calls[0]["inference_geo"] == geo


@pytest.mark.parametrize("value", ["", "changeme", "  "])
def test_placeholder_model_falls_back_to_haiku(fake, monkeypatch, value):
    monkeypatch.setenv("LLM_MODEL", value)
    call()
    assert fake.calls[0]["model"] == "claude-haiku-5-5"


def test_sonnet_only_when_env_says_so_and_never_with_thinking_disabled(fake, monkeypatch):
    monkeypatch.setenv("LLM_MODEL", "claude-sonnet-5-5")
    call()
    assert fake.calls == []
    (sent,) = fake.beta_calls
    assert sent["model"] == "claude-sonnet-5-5"
    assert "thinking" not in sent  # "disabled" is a 400 on Sonnet 5.5
    assert sent["fallbacks"] == "default" and sent["betas"] == ["server-side-fallback-2026-07-01"]


def test_real_client_has_no_retries_and_uses_only_llm_api_key(monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "other-key-not-real")

    async def make():
        return llm._get_client("test-key-not-real")

    client = asyncio.run(make())
    assert client.max_retries == 0
    assert client.api_key == "test-key-not-real"


@pytest.mark.parametrize("value", [None, "", "changeme"])
def test_missing_key_raises_without_calling(fake, monkeypatch, value):
    if value is None:
        monkeypatch.delenv("LLM_API_KEY")
    else:
        monkeypatch.setenv("LLM_API_KEY", value)
    with pytest.raises(llm.LLMUnavailable):
        call()
    assert fake.calls == []


# --- Failures ------------------------------------------------------------------------------------


def test_slow_call_is_cut_off_at_timeout(monkeypatch):
    client = FakeClient(delay=5.0)
    monkeypatch.setattr(llm, "_get_client", lambda api_key: client)
    started = time.perf_counter()
    with pytest.raises(llm.LLMTimeout):
        call(timeout_s=0.05)
    assert time.perf_counter() - started < 1.0
    assert isinstance(llm.LLMTimeout("x"), TimeoutError)


@pytest.mark.parametrize(
    "error, expected",
    [
        (anthropic.APITimeoutError(request=REQUEST), llm.LLMTimeout),
        (anthropic.APIConnectionError(request=REQUEST), llm.LLMError),
        (anthropic.InternalServerError("x", response=httpx2.Response(500, request=REQUEST), body=None), llm.LLMError),
        (anthropic.RateLimitError("x", response=httpx2.Response(429, request=REQUEST), body=None), llm.LLMError),
        (anthropic.BadRequestError("x", response=httpx2.Response(400, request=REQUEST), body=None), llm.LLMError),
    ],
)
def test_sdk_errors_become_llm_errors(monkeypatch, error, expected):
    client = FakeClient(error=error)
    monkeypatch.setattr(llm, "_get_client", lambda api_key: client)
    with pytest.raises(expected):
        call()
    assert len(client.calls) == 1  # no retry


@pytest.mark.parametrize(
    "result",
    [
        response(stop="refusal"),
        response(stop="max_tokens", text='{"a": '),
        response(text="not json"),
        response(text='["a", "b"]'),
        response(content=[]),
        response(content=[SimpleNamespace(type="thinking", thinking="")]),
    ],
    ids=["refusal", "max_tokens", "not-json", "not-object", "empty", "no-text-block"],
)
def test_unusable_output_raises_invalid_output(monkeypatch, result):
    monkeypatch.setattr(llm, "_get_client", lambda api_key: FakeClient(result=result))
    with pytest.raises(llm.LLMInvalidOutput):
        call()


def test_text_block_after_a_thinking_block_is_read(monkeypatch):
    blocks = [SimpleNamespace(type="thinking", thinking=""), SimpleNamespace(type="text", text='{"a": "y"}')]
    monkeypatch.setattr(llm, "_get_client", lambda api_key: FakeClient(result=response(content=blocks)))
    assert call() == {"a": "y"}


# --- Hedging: one duplicate for a slow call, first answer wins -----------------------------------

SERVER_ERROR = anthropic.InternalServerError("x", response=httpx2.Response(500, request=REQUEST), body=None)


def use(monkeypatch, client):
    monkeypatch.setattr(llm, "_get_client", lambda api_key: client)
    return client


def test_slow_call_gets_one_hedge_and_the_first_answer_wins(monkeypatch):
    monkeypatch.setenv("LLM_HEDGE_AFTER_S", "0.05")
    client = use(monkeypatch, FakeClient(script=[(2.0, None), (0.0, None)]))
    started = time.perf_counter()
    assert call(timeout_s=3.0) == {"a": "x"}
    assert time.perf_counter() - started < 1.0
    assert len(client.calls) == 2 and client.calls[0] == client.calls[1]
    assert llm.calls_today() == 2  # the hedge counts toward the cap


def test_fast_call_is_not_hedged(monkeypatch):
    monkeypatch.setenv("LLM_HEDGE_AFTER_S", "0.5")
    client = use(monkeypatch, FakeClient())
    call()
    assert len(client.calls) == 1


@pytest.mark.parametrize("setting", ["0", "-1"])
def test_hedging_can_be_turned_off_by_env(monkeypatch, setting):
    monkeypatch.setenv("LLM_HEDGE_AFTER_S", setting)
    client = use(monkeypatch, FakeClient(script=[(0.2, None)]))
    call()
    assert len(client.calls) == 1


def test_hedging_can_be_turned_off_per_call(monkeypatch):
    monkeypatch.setenv("LLM_HEDGE_AFTER_S", "0.05")
    client = use(monkeypatch, FakeClient(script=[(0.2, None)]))
    asyncio.run(llm.complete_json(system="s", user="u", schema=SCHEMA, max_tokens=10, timeout_s=1.0, hedge=False))
    assert len(client.calls) == 1


def test_no_hedge_when_the_budget_is_used_up(monkeypatch):
    monkeypatch.setenv("LLM_HEDGE_AFTER_S", "0.05")
    monkeypatch.setenv("LLM_DAILY_CAP", "1")
    client = use(monkeypatch, FakeClient(script=[(0.2, None)]))
    assert call() == {"a": "x"}
    assert len(client.calls) == 1


def test_hedge_answers_when_the_slow_first_call_then_fails(monkeypatch):
    monkeypatch.setenv("LLM_HEDGE_AFTER_S", "0.05")
    client = use(monkeypatch, FakeClient(script=[(0.1, SERVER_ERROR), (0.3, None)]))
    assert call() == {"a": "x"}
    assert len(client.calls) == 2


def test_error_when_every_attempt_fails(monkeypatch):
    monkeypatch.setenv("LLM_HEDGE_AFTER_S", "0.05")
    use(monkeypatch, FakeClient(script=[(0.1, SERVER_ERROR), (0.1, SERVER_ERROR)]))
    with pytest.raises(llm.LLMError):
        call()


def test_a_fast_error_is_not_retried(monkeypatch):
    monkeypatch.setenv("LLM_HEDGE_AFTER_S", "0.5")
    client = use(monkeypatch, FakeClient(error=SERVER_ERROR))
    with pytest.raises(llm.LLMError):
        call()
    assert len(client.calls) == 1


def test_timeout_still_applies_with_a_hedge_in_flight(monkeypatch):
    monkeypatch.setenv("LLM_HEDGE_AFTER_S", "0.05")
    use(monkeypatch, FakeClient(delay=5.0))
    started = time.perf_counter()
    with pytest.raises(llm.LLMTimeout):
        call(timeout_s=0.2)
    assert time.perf_counter() - started < 1.0


# --- Budget cap ----------------------------------------------------------------------------------


def test_daily_cap_raises_once_used_up(fake, monkeypatch):
    monkeypatch.setenv("LLM_DAILY_CAP", "2")
    call()
    call()
    with pytest.raises(llm.LLMBudgetExceeded):
        call()
    assert len(fake.calls) == 2
    assert llm.calls_today() == 2


def test_daily_cap_resets_on_a_new_utc_day(fake, monkeypatch):
    monkeypatch.setenv("LLM_DAILY_CAP", "1")
    monkeypatch.setattr(llm, "_today", lambda: dt.date(2026, 10, 17))
    call()
    with pytest.raises(llm.LLMBudgetExceeded):
        call()
    monkeypatch.setattr(llm, "_today", lambda: dt.date(2026, 10, 18))
    call()
    assert len(fake.calls) == 2


def test_default_cap_is_3000(monkeypatch):
    assert llm.daily_cap() == 3000
    monkeypatch.setenv("LLM_DAILY_CAP", "not-a-number")
    assert llm.daily_cap() == 3000


def test_failed_calls_count_toward_the_cap(monkeypatch):
    monkeypatch.setenv("LLM_DAILY_CAP", "1")
    monkeypatch.setattr(llm, "_get_client", lambda api_key: FakeClient(result=response(text="nope")))
    with pytest.raises(llm.LLMInvalidOutput):
        call()
    with pytest.raises(llm.LLMBudgetExceeded):
        call()


# --- classify_cause ------------------------------------------------------------------------------


@pytest.mark.parametrize("cause", llm.CAUSES)
def test_classify_cause_returns_the_models_chip(monkeypatch, cause):
    client = FakeClient(result=response(text=json.dumps({"cause": cause})))
    monkeypatch.setattr(llm, "_get_client", lambda api_key: client)
    assert asyncio.run(llm.classify_cause("Lines across the screen. Never dropped.")) == cause
    (sent,) = client.calls
    assert sent["output_config"]["format"]["schema"]["properties"]["cause"]["enum"] == list(llm.CAUSES)
    assert "Lines across the screen" in sent["messages"][0]["content"]


def test_classify_cause_is_none_when_the_llm_fails(monkeypatch):
    monkeypatch.setattr(llm, "_get_client", lambda api_key: FakeClient(error=anthropic.APITimeoutError(request=REQUEST)))
    assert asyncio.run(llm.classify_cause("Stolen from my bag")) is None


def test_classify_cause_is_none_without_a_key(monkeypatch):
    monkeypatch.delenv("LLM_API_KEY")
    assert asyncio.run(llm.classify_cause("Stolen from my bag")) is None


def test_classify_cause_rejects_values_outside_the_enum(monkeypatch):
    monkeypatch.setattr(llm, "_get_client", lambda api_key: FakeClient(result=response(text='{"cause": "fire"}')))
    assert asyncio.run(llm.classify_cause("It caught fire")) is None


@pytest.mark.parametrize("description", ["", "   ", None])
def test_classify_cause_skips_empty_descriptions(fake, description):
    assert asyncio.run(llm.classify_cause(description)) is None
    assert fake.calls == []


# --- Privacy: never log prompts or outputs -------------------------------------------------------


def test_logs_carry_no_prompt_or_output(monkeypatch, caplog):
    secret_in, secret_out = "Alex Doe ordered a Sample Widget", "SAMPLE-OUTPUT-MARKER"
    monkeypatch.setattr(llm, "_get_client", lambda api_key: FakeClient(result=response(text=json.dumps({"a": secret_out}))))
    with caplog.at_level(logging.DEBUG):
        call(system=secret_in, user=secret_in)
        monkeypatch.setattr(llm, "_get_client", lambda api_key: FakeClient(error=anthropic.APIConnectionError(request=REQUEST)))
        with pytest.raises(llm.LLMError):
            call(user=secret_in)
    text = "\n".join(r.getMessage() for r in caplog.records)
    assert caplog.records  # latency is logged ...
    assert secret_in not in text and secret_out not in text  # ... content is not
    assert "test-key-not-real" not in text
