<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/openai

A client for the OpenAI-compatible API, written in Jennifer over plain
HTTPS: Chat Completions with tools and structured output, a tool loop that
runs the model's tool calls through a function of yours, embeddings and
model listing, and `call` for every other endpoint. The base URL is
settable, so one client covers OpenAI, Azure OpenAI and the servers that
speak the same API: Ollama, vLLM, the llama.cpp server, LM Studio,
OpenRouter, Groq, Mistral, Together, Google's OpenAI-compatible Gemini
endpoint.

- [Chat](chat.md): requests, messages, replies, structured output,
  reasoning models.
- [Tools](tools.md): tool definitions, the tool loop, passing context to a
  handler, a loop of your own.
- [Embeddings](embeddings.md): vectors of texts, base64, large batches.
- [Servers](servers.md): base URLs, the quirks of each server, Azure, `call`.
- [Cheatsheet](cheatsheet.md): every export.

The deck is a thin client: requests and replies are `json.Value` documents
in the API's own field names, so every field the API has is reachable, also
ones newer than the deck. Helpers build the common parts of a request
(`newRequest`, `withSystem`, `addUserText`, `tool`, `addTool`, `setSchema`) and read the common
parts of a reply (`text`, `toolCalls`, `refusal`, `usage`, `parsed`).

## Conventions

Snippets assume this import:

```jennifer
import "@deckyard/openai/" as openai;
```

## Setting up a client

**OpenAI.** `client` takes the API key and talks to
`https://api.openai.com/v1`; the key goes out as `Authorization: Bearer`.
A key in several organizations or projects names one:

```jennifer
def c as openai.Client init openai.client(os.getEnv("OPENAI_API_KEY"));
$c = openai.withProject($c, "proj_abc123");
```

**A local server.** Point the client at the server's `/v1` URL; Ollama and
most local servers need no key, so pass `""` and no `Authorization` header
is sent. Plain `http` is fine to this machine (`127.0.0.1`, `localhost`,
`[::1]`); to another machine it is refused unless the client has
`withPlainHttp`, since prompts and a key would cross the network in clear.

```jennifer
def local as openai.Client init openai.withBaseUrl(openai.client(""), "http://127.0.0.1:11434/v1");
def lan as openai.Client init openai.withPlainHttp(
    openai.withBaseUrl(openai.client(""), "http://gpu-box.lan:8000/v1"));
```

**Azure OpenAI.** `azure` uses the v1 API, which needs no `api-version`:
`<endpoint>/openai/v1`, the key in the `api-key` header, and the request's
`model` names the deployment. `azureVersioned` uses the older dated API,
with the deployment in the path and the `api-version` query on every
request; the request's `model` still names the deployment.

```jennifer
def az as openai.Client init openai.azure("https://myres.openai.azure.com",
    os.getEnv("AZURE_OPENAI_API_KEY"));
def dated as openai.Client init openai.azureVersioned("https://myres.openai.azure.com",
    os.getEnv("AZURE_OPENAI_API_KEY"), openai.AZURE_API_VERSION);
```

A Microsoft Entra ID token instead of a key goes as a bearer token:
`openai.withBaseUrl(openai.client($token), $endpoint + "/openai/v1")`. See
[Servers](servers.md) for each server's base URL and quirks.

**Settings.** Every `with*` function returns a changed copy:

| Setting | Default | Change with |
|---|---|---|
| deadline of one attempt | 10 minutes | `withTimeout(c, ms)` |
| retries on 408, 409, 429, 5xx, a connection refused or reset | 2 | `withRetries(c, n)` |
| largest reply | 32 MiB | `withMaxBytes(c, most)` |
| largest tool input a tool loop hands to a handler | 1 MiB | `withMaxToolInput(c, most)` |
| certificate checks | system roots | `withTls(c, tls)` |
| more headers | none | `withHeader(c, name, value)` |

The deadline is generous because a long generation or a reasoning model
can take minutes without sending a byte; a short one for a quick
classification is `openai.withTimeout($c, 30000)`. It applies to each
attempt, and a retry starts a new one.

## A first request

```jennifer
def req as json.Value init openai.newRequest("gpt-5.4-mini");
$req = openai.withSystem($req, "Answer in one sentence.");
$req = openai.addUserText($req, "What is the capital of France?");
def reply as json.Value init openai.chat($c, $req);
io.printf("%s\n", openai.text($reply));
```

## Errors

Every failure of this deck that is not one of the generic kinds below
throws `openai.OpenaiError`, kind `"openai"`:

| Field | Holds |
|---|---|
| `message` | `openai: <request>: <the server's message> (HTTP 404, type ..., code ...)` |
| `status` | the HTTP status; 0 when no server answered (unreachable, refused before sending) |
| `type` | the error's `type`, such as `invalid_request_error`, `insufficient_quota` |
| `code` | the error's `code`, such as `model_not_found`, `rate_limit_exceeded`; a numeric code (llama.cpp, vLLM) as its digits |
| `param` | the request field the error is about, such as `max_tokens` |
| `requestId` | the `x-request-id` header (Azure: `apim-request-id`), for the provider's support |
| `retryAfterMs` | how long the server asked to wait (`retry-after-ms`, else `retry-after` in seconds or as an HTTP date), in ms; 0 when it named no wait |
| `limits` | the server's rate-limit headers, names lower-cased: `x-ratelimit-limit-requests`, `x-ratelimit-remaining-tokens`, `x-ratelimit-reset-requests`, ..., `retry-after`, `retry-after-ms` |

The generic kinds pass through as `Error`: `"limit"` for a reply over the
cap, `"timeout"` for a deadline that
passed, `"closed"` for a server that closed the connection mid-reply,
`"cancelled"` for a cancelled task. Match `kind` and the fields, never the
message:

```jennifer
try {
    $reply = openai.chat($c, $req);
} catch (e) {
    if ($e.kind == "openai" and $e.status == 404) {
        io.printf("no such model\n");
    } elseif ($e.kind == "timeout") {
        io.printf("no answer in time\n");
    } else {
        throw $e;
    }
}
```

A helper that takes a caught error declares it as `openai.OpenaiError`:
a parameter typed `Error` does not accept the struct.

No message carries the API key: the key is never in a URL, a server's
text that echoes the client's own key (in any form: Azure, Groq or Mistral
keys are not `sk-...`) has it replaced by `***`, and any other `sk-...`
key (OpenAI's own masked one included) by `sk-***`. Do not print a
`Client`, which holds the key.

**Retries.** A 408, 409, 429 or 5xx is retried, by default twice, and so
is a connection the network refused or reset. The wait is the server's
`retry-after-ms`, else its `retry-after` in seconds or as an HTTP date,
else 0.5 s doubled per retry up to 8 s. Not retried: a server asking to
wait over a minute (the error carries the wait in `retryAfterMs`), a
response with `x-should-retry: false`, a 429 whose type or code is
`insufficient_quota` (out of credit; waiting does not help), a reply cut
off mid-way (kind `"closed"`: the request may have been carried out, and
a `POST` sent twice could be billed twice), a reply that is not HTTP, and a
deadline that passed. Every method is retried on a status, a `POST` too:
the server answered that it did not carry the request out, though a 5xx
after a long generation may still be billed.

## Not in this version

- **Streaming.** All these APIs stream over server-sent events, which the
  bundled `http` cannot read incrementally yet. M28.29 adds a streaming
  `http` and an `sse` module; streaming then becomes a deck addition. A
  request with `stream: true` is refused.
- **The Responses API** (`/responses`), OpenAI's newer interface with
  server-side conversation state, built-in tools (web and file search, code
  interpreter, computer use) and reasoning items carried between turns. It
  needs a reader for its typed `output` items (`message`, `function_call`,
  `reasoning`, ...), a tool loop that answers `function_call` items with
  `function_call_output` items by `call_id` (or chains turns with
  `previous_response_id`), and its own usage fields. Until then
  `openai.call($c, "POST", "/responses", $body)` reaches it with the same
  retries and errors.
- Files, batches, fine-tuning, images, audio, moderation, vector stores and
  the Realtime API (WebSocket) have no helpers; the JSON ones work through
  `call`. Uploads (`multipart/form-data`) do not.
