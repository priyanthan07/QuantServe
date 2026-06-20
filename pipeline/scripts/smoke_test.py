"""
Smoke test: send a single request to the production endpoint
and verify the response is valid.
"""
import argparse
import json
import sys

from openai import OpenAI


def run_smoke_test(base_url: str, api_key: str, model_name: str) -> bool:
    """Send a test request and validate the response."""
    client = OpenAI(base_url=base_url, api_key=api_key)

    try:
        response = client.chat.completions.create(
            model=model_name,
            messages=[{"role": "user", "content": "Say hello in one sentence."}],
            max_tokens=50,
            temperature=0.7,
        )

        content = response.choices[0].message.content
        if content and len(content.strip()) > 0:
            print(f"Smoke test PASSED. Response: {content[:100]}")
            return True
        else:
            print("Smoke test FAILED: Empty response content")
            return False

    except Exception as e:
        print(f"Smoke test FAILED: {e}")
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True, help="vLLM endpoint URL (e.g. https://IP/v1)")
    parser.add_argument("--api-key", required=True, help="API key for authentication")
    parser.add_argument("--model-name", required=True, help="Model name as served by vLLM")
    args = parser.parse_args()

    success = run_smoke_test(args.base_url, args.api_key, args.model_name)

    if not success:
        sys.exit(1)


if __name__ == "__main__":
    main()
    