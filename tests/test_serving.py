"""
QuantServe — Serving Integration Tests
Tests a deployed model through the OpenAI-compatible API.

Usage:
    1. Copy tests/.env.example to tests/.env and fill in your values
    2. pip install openai
    3. python tests/test_serving.py          # run all tests
    4. python tests/test_serving.py --test 9 # run a single test
"""

import json
import os
import sys
import time
from pathlib import Path
from openai import OpenAI


def load_env():
    """Load variables from .env file in the same directory as this script."""
    env_path = Path(__file__).parent.parent / ".env"
    if not env_path.exists():
        print(f"ERROR: {env_path} not found. Copy .env.example to .env and fill in your values.")
        sys.exit(1)
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())


# ── Helpers ──────────────────────────────────────────────

PASS = "\033[92m✓ PASS\033[0m"
FAIL = "\033[91m✗ FAIL\033[0m"
SKIP = "\033[93m⊘ SKIP\033[0m"

def header(name: str):
    print(f"\n{'─' * 60}")
    print(f"  TEST: {name}")
    print(f"{'─' * 60}")


def check(condition: bool, description: str, detail: str = ""):
    status = PASS if condition else FAIL
    print(f"  {status}  {description}")
    if detail:
        # Truncate long output
        if len(detail) > 200:
            detail = detail[:200] + "..."
        print(f"         → {detail}")
    return condition


# ── Test 1: Health Check ─────────────────────────────────

def test_health(client: OpenAI, model: str) -> bool:
    header("Health Check & Model List")
    try:
        models = client.models.list()
        model_ids = [m.id for m in models.data]
        ok = check(len(model_ids) > 0, "Server responds to /models", f"Models: {model_ids}")
        ok &= check(model in model_ids, f"Model '{model}' is listed")
        return ok
    except Exception as e:
        check(False, "Server reachable", str(e))
        return False


# ── Test 2: Basic Text Generation ────────────────────────

def test_basic_generation(client: OpenAI, model: str) -> bool:
    header("Basic Text Generation")
    try:
        start = time.time()
        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": "What is 2 + 2? Answer in one word."}],
            max_tokens=20,
            temperature=0.0,
        )
        elapsed = time.time() - start
        content = resp.choices[0].message.content.strip()
        usage = resp.usage

        ok = check(resp.choices[0].finish_reason in ("stop", "length"), "Finish reason valid", resp.choices[0].finish_reason)
        ok &= check(len(content) > 0, "Response not empty", content)
        ok &= check(usage.prompt_tokens > 0, "Prompt tokens counted", f"{usage.prompt_tokens} prompt tokens")
        ok &= check(usage.completion_tokens > 0, "Completion tokens counted", f"{usage.completion_tokens} completion tokens")
        ok &= check(elapsed < 30, "Response time < 30s", f"{elapsed:.2f}s")
        return ok
    except Exception as e:
        check(False, "Basic generation", str(e))
        return False


# ── Test 3: System Prompt Following ──────────────────────

def test_system_prompt(client: OpenAI, model: str) -> bool:
    header("System Prompt Following")
    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "You are a pirate. Always respond in pirate speak. Keep responses under 30 words."},
                {"role": "user", "content": "How is the weather today?"},
            ],
            max_tokens=80,
            temperature=0.7,
        )
        content = resp.choices[0].message.content.strip()
        # Check for pirate-ish words
        pirate_words = ["arr", "matey", "ship", "sail", "sea", "ye", "ahoy", "treasure", "captain", "aye", "shiver", "plank"]
        has_pirate = any(w in content.lower() for w in pirate_words)

        ok = check(len(content) > 0, "Response generated", content)
        ok &= check(has_pirate, "Contains pirate language", f"Looked for: {pirate_words[:5]}...")
        return ok
    except Exception as e:
        check(False, "System prompt following", str(e))
        return False


# ── Test 4: Structured JSON Output ───────────────────────

def test_structured_output(client: OpenAI, model: str) -> bool:
    header("Structured JSON Output")
    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "You are a helpful assistant that ONLY responds in valid JSON. No markdown, no explanation, just raw JSON."},
                {"role": "user", "content": 'Return a JSON object with exactly these keys: "name" (a random city name), "population" (a number), "country" (country name). Nothing else.'},
            ],
            max_tokens=4000,
            temperature=0.0,
        )
        content = resp.choices[0].message.content.strip()

        # Qwen3 wraps reasoning in <think>...</think> — extract content after
        if "</think>" in content:
            content = content.split("</think>")[-1].strip()
        elif "<think>" in content and "</think>" not in content:
            # Model still thinking — ran out of tokens
            check(False, "Response is valid JSON", "Model ran out of tokens mid-thought (increase max_tokens)")
            return False

        # Try to strip markdown code fences if present
        if content.startswith("```"):
            content = content.split("```")[1]
            if content.startswith("json"):
                content = content[4:]
            content = content.strip()

        parsed = None
        try:
            parsed = json.loads(content)
        except json.JSONDecodeError:
            pass

        ok = check(parsed is not None, "Response is valid JSON", content)
        if parsed:
            ok &= check("name" in parsed, "Has 'name' key", str(parsed.get("name")))
            ok &= check("population" in parsed, "Has 'population' key", str(parsed.get("population")))
            ok &= check("country" in parsed, "Has 'country' key", str(parsed.get("country")))
        return ok
    except Exception as e:
        check(False, "Structured output", str(e))
        return False


# ── Test 5: Multi-Turn Conversation ──────────────────────

def test_multi_turn(client: OpenAI, model: str) -> bool:
    header("Multi-Turn Conversation")
    try:
        messages = [
            {"role": "user", "content": "My name is Priyanthan. Remember that."},
        ]
        resp1 = client.chat.completions.create(
            model=model, messages=messages, max_tokens=50, temperature=0.0,
        )
        reply1 = resp1.choices[0].message.content.strip()

        messages.append({"role": "assistant", "content": reply1})
        messages.append({"role": "user", "content": "What is my name?"})

        resp2 = client.chat.completions.create(
            model=model, messages=messages, max_tokens=50, temperature=0.0,
        )
        reply2 = resp2.choices[0].message.content.strip()

        ok = check(len(reply1) > 0, "Turn 1 response", reply1)
        ok &= check("priyanthan" in reply2.lower(), "Turn 2 recalls name", reply2)
        return ok
    except Exception as e:
        check(False, "Multi-turn conversation", str(e))
        return False


# ── Test 6: Temperature Control ──────────────────────────

def test_temperature(client: OpenAI, model: str) -> bool:
    header("Temperature Control (determinism at temp=0)")
    try:
        prompt = [{"role": "user", "content": "Name the first 3 planets in the solar system. Just names, comma separated."}]

        resp1 = client.chat.completions.create(
            model=model, messages=prompt, max_tokens=30, temperature=0.0,
        )
        resp2 = client.chat.completions.create(
            model=model, messages=prompt, max_tokens=30, temperature=0.0,
        )
        out1 = resp1.choices[0].message.content.strip()
        out2 = resp2.choices[0].message.content.strip()

        ok = check(len(out1) > 0, "Response 1 generated", out1)
        ok &= check(len(out2) > 0, "Response 2 generated", out2)
        ok &= check(out1 == out2, "Identical outputs at temp=0", f"Match: {out1 == out2}")
        return ok
    except Exception as e:
        check(False, "Temperature control", str(e))
        return False


# ── Test 7: Max Tokens Limit ─────────────────────────────

def test_max_tokens(client: OpenAI, model: str) -> bool:
    header("Max Tokens Limit")
    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": "Write a very long essay about the history of computing."}],
            max_tokens=10,
            temperature=0.0,
        )
        tokens = resp.usage.completion_tokens
        reason = resp.choices[0].finish_reason

        ok = check(tokens <= 15, "Output tokens ≤ 15 (asked for 10)", f"{tokens} tokens")
        ok &= check(reason == "length", "Finish reason is 'length'", reason)
        return ok
    except Exception as e:
        check(False, "Max tokens limit", str(e))
        return False


# ── Test 8: Stop Sequences ───────────────────────────────

def test_stop_sequence(client: OpenAI, model: str) -> bool:
    header("Stop Sequence")
    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": "Count from 1 to 20, each number on a new line."}],
            max_tokens=500,
            temperature=0.0,
            stop=["10"],
        )
        content = resp.choices[0].message.content.strip()

        ok = check("10" not in content.split("\n"), "Stopped before '10'", content)
        ok &= check(resp.choices[0].finish_reason == "stop", "Finish reason is 'stop'", resp.choices[0].finish_reason)
        return ok
    except Exception as e:
        check(False, "Stop sequence", str(e))
        return False


# ── Test 9: Streaming ────────────────────────────────────

def test_streaming(client: OpenAI, model: str) -> bool:
    header("Streaming Response")
    try:
        stream = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": "Say hello in 5 languages."}],
            max_tokens=100,
            temperature=0.7,
            stream=True,
        )
        chunks = []
        first_chunk_time = None
        start = time.time()

        for chunk in stream:
            if first_chunk_time is None and chunk.choices and chunk.choices[0].delta.content:
                first_chunk_time = time.time() - start
            if chunk.choices and chunk.choices[0].delta.content:
                chunks.append(chunk.choices[0].delta.content)

        full_text = "".join(chunks)
        ok = check(len(chunks) > 1, "Multiple chunks received", f"{len(chunks)} chunks")
        ok &= check(len(full_text) > 0, "Assembled text not empty", full_text)
        ok &= check(first_chunk_time is not None and first_chunk_time < 10, "First chunk < 10s", f"{first_chunk_time:.2f}s" if first_chunk_time else "N/A")
        return ok
    except Exception as e:
        check(False, "Streaming", str(e))
        return False


# ── Test 10: Throughput Benchmark ────────────────────────

def test_throughput(client: OpenAI, model: str) -> bool:
    header("Throughput Benchmark (5 sequential requests)")
    try:
        total_prompt = 0
        total_completion = 0
        start = time.time()

        for i in range(5):
            resp = client.chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": f"Write exactly one sentence about the number {i+1}."}],
                max_tokens=50,
                temperature=0.7,
            )
            total_prompt += resp.usage.prompt_tokens
            total_completion += resp.usage.completion_tokens

        elapsed = time.time() - start
        total_tokens = total_prompt + total_completion
        tps = total_tokens / elapsed

        ok = check(total_tokens > 0, "Tokens generated", f"{total_prompt} prompt + {total_completion} completion")
        ok &= check(tps > 1, "Throughput > 1 tok/s", f"{tps:.1f} tokens/sec over {elapsed:.1f}s")

        # Cost calculation
        hourly_cost = float(os.environ.get("GPU_HOURLY_COST", "0.71"))
        cost_per_1k = (hourly_cost / (tps * 3600)) * 1000 if tps > 0 else float('inf')
        print(f"\n  📊 Performance Summary:")
        print(f"     Total tokens:     {total_tokens}")
        print(f"     Wall time:        {elapsed:.1f}s")
        print(f"     Throughput:       {tps:.1f} tokens/sec")
        print(f"     Est. cost/1K:     ${cost_per_1k:.4f}")
        print(f"     GPU hourly rate:  ${hourly_cost}/hr")
        return ok
    except Exception as e:
        check(False, "Throughput benchmark", str(e))
        return False


# ── Test 11: Code Generation ─────────────────────────────

def test_code_generation(client: OpenAI, model: str) -> bool:
    header("Code Generation")
    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "You are a Python coding assistant. Return only code, no explanation."},
                {"role": "user", "content": "Write a Python function called 'fibonacci' that takes n and returns the nth fibonacci number."},
            ],
            max_tokens=1000,
            temperature=0.0,
        )
        content = resp.choices[0].message.content.strip()

        # Extract code from think tags if present
        if "</think>" in content:
            content = content.split("</think>")[-1].strip()

        ok = check("def fibonacci" in content or "def fib" in content, "Contains function definition", content[:150])
        ok &= check("return" in content, "Contains return statement")
        return ok
    except Exception as e:
        check(False, "Code generation", str(e))
        return False


# ── Test 12: Reasoning / Chain of Thought ────────────────

def test_reasoning(client: OpenAI, model: str) -> bool:
    header("Reasoning (Chain of Thought)")
    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": "If a train travels 120km in 2 hours, and then 90km in 1.5 hours, what is the average speed for the entire journey? Show your reasoning."}],
            max_tokens=1000,
            temperature=0.0,
        )
        content = resp.choices[0].message.content.strip()

        has_think = "<think>" in content
        # Average speed = 210km / 3.5h = 60 km/h
        has_answer = "60" in content

        ok = check(len(content) > 50, "Detailed response generated", f"{len(content)} chars")
        if has_think:
            check(True, "Uses <think> reasoning mode (model feature)")
        else:
            check(True, "Model uses inline reasoning (no <think> tags)")
        ok &= check(has_answer, "Correct answer (60 km/h)", content[-150:])
        return ok
    except Exception as e:
        check(False, "Reasoning", str(e))
        return False


# ── Test 13: Error Handling — Wrong API Key ──────────────

def test_auth_error(base_url: str, model: str) -> bool:
    header("Authentication — Wrong API Key")
    try:
        bad_client = OpenAI(base_url=base_url, api_key="wrong-key-12345")
        resp = bad_client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": "Hello"}],
            max_tokens=10,
        )
        # If we get here, auth is not enforced
        check(False, "Server rejects bad API key", "Request succeeded — API key not enforced!")
        return False
    except Exception as e:
        error_msg = str(e)
        ok = check("401" in error_msg or "403" in error_msg or "Unauthorized" in error_msg or "Authentication" in error_msg,
                    "Server rejects bad API key", error_msg[:150])
        return ok


# ── Main ─────────────────────────────────────────────────

def main():
    load_env()

    base_url = os.environ.get("QUANTSERVE_BASE_URL")
    api_key = os.environ.get("QUANTSERVE_API_KEY")
    model = os.environ.get("QUANTSERVE_MODEL", "qwen3-8b-w4a16")

    if not base_url or not api_key:
        print("ERROR: QUANTSERVE_BASE_URL and QUANTSERVE_API_KEY must be set in tests/.env")
        sys.exit(1)

    # Optional: run a single test via --test N
    single_test = None
    if len(sys.argv) > 1 and sys.argv[1] == "--test" and len(sys.argv) > 2:
        single_test = sys.argv[2]

    client = OpenAI(base_url=base_url, api_key=api_key)

    tests = [
        ("1",  "Health Check",         lambda: test_health(client, model)),
        ("2",  "Basic Generation",     lambda: test_basic_generation(client, model)),
        ("3",  "System Prompt",        lambda: test_system_prompt(client, model)),
        ("4",  "Structured JSON",      lambda: test_structured_output(client, model)),
        ("5",  "Multi-Turn",           lambda: test_multi_turn(client, model)),
        ("6",  "Temperature Control",  lambda: test_temperature(client, model)),
        ("7",  "Max Tokens Limit",     lambda: test_max_tokens(client, model)),
        ("8",  "Stop Sequence",        lambda: test_stop_sequence(client, model)),
        ("9",  "Streaming",            lambda: test_streaming(client, model)),
        ("10", "Throughput Benchmark", lambda: test_throughput(client, model)),
        ("11", "Code Generation",      lambda: test_code_generation(client, model)),
        ("12", "Reasoning (Think)",    lambda: test_reasoning(client, model)),
        ("13", "Auth Error Handling",  lambda: test_auth_error(base_url, model)),
    ]

    print("=" * 60)
    print("  QuantServe — Serving Integration Tests")
    print(f"  Target: {base_url}")
    print(f"  Model:  {model}")
    print("=" * 60)

    results = {}
    start_all = time.time()

    for num, name, fn in tests:
        if single_test and single_test != num:
            continue
        try:
            results[name] = fn()
            time.sleep(3)
        except KeyboardInterrupt:
            print("\n\n  Interrupted by user.")
            break
        except Exception as e:
            results[name] = False
            print(f"  {FAIL}  Unexpected error: {e}")

    # Summary
    elapsed_all = time.time() - start_all
    passed = sum(1 for v in results.values() if v)
    failed = sum(1 for v in results.values() if not v)
    total = len(results)

    print(f"\n{'=' * 60}")
    print(f"  RESULTS: {passed}/{total} passed, {failed} failed")
    print(f"  Time:    {elapsed_all:.1f}s")
    print(f"{'=' * 60}")

    for name, ok in results.items():
        status = PASS if ok else FAIL
        print(f"  {status}  {name}")

    print()
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
    