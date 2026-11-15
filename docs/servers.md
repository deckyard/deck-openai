<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Servers

The client sends every request to its base URL plus the endpoint's path
(`/chat/completions`, `/embeddings`, `/models`), so any server that serves
those paths with OpenAI's fields works. The base URL is the part before
`/chat/completions`.

| Server | Base URL | Key |
|---|---|---|
| OpenAI | `https://api.openai.com/v1` (the default) | `OPENAI_API_KEY` |
| Ollama | `http://127.0.0.1:11434/v1` | none (`""`) |
| vLLM | `http://127.0.0.1:8000/v1` | `--api-key` if set |
| llama.cpp server | `http://127.0.0.1:8080/v1` | `--api-key` if set |
| LM Studio | `http://127.0.0.1:1234/v1` | none |
| OpenRouter | `https://openrouter.ai/api/v1` | the OpenRouter key |
| Groq | `https://api.groq.com/openai/v1` | the Groq key |
| Mistral | `https://api.mistral.ai/v1` | the Mistral key |
| Together | `https://api.together.xyz/v1` | the Together key |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | the AI Studio key |
| Azure OpenAI | `azure(endpoint, key)`: `<endpoint>/openai/v1` | the resource key |

```jennifer
def router as openai.Client init openai.withBaseUrl(openai.client(os.getEnv("OPENROUTER_API_KEY")),
    "https://openrouter.ai/api/v1");
$router = openai.withHeader($router, "X-Title", "my tool");
```

`withHeader` adds a header to every request (OpenRouter's `HTTP-Referer`
and `X-Title`, a gateway's own); the headers the client sets itself are
refused. A server behind a private CA takes its certificate with
`openai.withTls($c, http.TlsOptions{caCert: fs.readBytes("ca.pem")})`.

Each server implements its own subset: a field one does not know is
ignored or refused with a 400, a model name is the server's own
(`qwen2.5:0.5b` on Ollama, `meta-llama/Llama-3.1-8B-Instruct` on vLLM).
`models` lists what it offers.

## What the deck reads from any server

- An error body in OpenAI's shape, `{"error": {"message", "type", "param",
  "code"}}`, with `code` a string or a number; a bare `{"error": "text"}`;
  the error fields at the top level (`{"object": "error", "message",
  "type", "code"}`); FastAPI's `{"detail": "text"}`; and a plain text body
  (Ollama answers an unknown path with `404 page not found` as
  `text/plain`). An HTML page gives only the status text.
- A 2xx reply holding an `error` object is an error, as some proxies send
  them.
- Tool-call `content` given as `""` instead of `null`, an extra `index` on
  each call, missing `usage` details: read as OpenAI's. `addReply` drops
  the fields a request does not carry.
- Message content as a list of parts (Mistral's reasoning models): `text`
  joins the `text` parts.

## Ollama

Checked live with Ollama 0.40.16 (`ollama/ollama` in Docker, bound to
127.0.0.1) and the models `qwen2.5:0.5b` and `all-minilm`: chat with the
`developer` role and `max_completion_tokens`, two parallel tool calls in
one reply and the answer after their results, a no-argument tool (its
arguments `"{}"`), structured output with a strict `json_schema`,
embeddings as floats and as base64, and `/v1/models`. Errors come in
OpenAI's shape (`not_found_error` for an unknown model, with the HTTP
status), except for an unknown path. Its usage reports
`prompt_tokens_details.cached_tokens`. Ollama's native API (`/api/chat`,
`/api/embed`) is different and not this deck's; `call` reaches it only
below the base URL, so use a second client with the base URL
`http://127.0.0.1:11434` for it.

## Azure OpenAI

Two schemes, both with the key in an `api-key` header:

- **v1** (`azure`): `https://<resource>.openai.azure.com/openai/v1/...`
  (or `.services.ai.azure.com`), the same paths as OpenAI, no
  `api-version` since the v1 API went GA in August 2025. The request's
  `model` is the deployment name. This is the one to use.
- **Dated** (`azureVersioned`): the deployment in the path,
  `/openai/deployments/<deployment>/chat/completions?api-version=...`,
  with `AZURE_API_VERSION` (`2024-10-21`, the last dated GA version) or a
  preview. The deck takes the deployment from the request's `model`, which
  also stays in the body; `models` lists `/openai/models`, and `call` puts
  `/openai` before its path and adds the `api-version`.

A deployment name goes into the path, so it is checked: 1 to 64 letters,
digits, `.`, `_` and `-`. Azure's request id is `apim-request-id`;
`OpenaiError.requestId` holds it.

## Any other endpoint

`call(c, method, path, body)` sends any request below the base URL with
the client's key, headers, deadline, cap, retries and errors, and returns
the JSON reply (JSON `null` for an empty body). `body` is JSON `null` for
none.

```jennifer
def m as json.Value init openai.call($c, "GET", "/models/gpt-5.4-mini", json.decode("null"));
def mod as json.Value init openai.call($c, "POST", "/moderations",
    json.map({"model": "omni-moderation-latest", "input": "some text"}));
```

The path starts with one `/` and may carry a query; `.` and `..` segments,
spaces, `#` and backslashes are refused, so a path cannot leave the base
URL.
