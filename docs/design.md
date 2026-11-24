<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

`@deckyard/openai` is a client for the OpenAI™-compatible HTTP API: Chat
Completions with tools and structured output, a tool loop, embeddings,
model listing, and `call` for any other endpoint. The base URL is
settable, so one client talks to OpenAI, Azure™ OpenAI and the servers that
implement the same API: Ollama™, vLLM™, the llama.cpp™ server, LM Studio™,
OpenRouter™, Groq™, Mistral™, Together™, and Gemini™'s OpenAI-compatible
endpoint.

It is one of three LLM decks, one per vendor API (`@deckyard/anthropic`,
`@deckyard/gemini`), rather than one generic deck: the wire formats differ
in every part a client touches (where the system prompt goes, how tool
arguments arrive, error shapes, auth headers), and a common facade would
hide what each vendor does well. A provider-neutral `llm` facade over the
three is planned as its own deck.

Out of scope, on purpose:

- **Streaming.** The API streams over server-sent events, which the bundled
  `http` cannot read incrementally yet. A request with `stream: true` is
  refused. Streaming becomes a deck addition once the interpreter has a
  streaming `http` and an `sse` module.
- **The Responses API** (`/responses`), OpenAI's newer interface with
  server-side state and built-in tools. It is a separate surface, a later
  addition; `call` reaches it meanwhile.
- **Token counting.** OpenAI has no counting endpoint for Chat
  Completions, so there is no `countTokens` (the sibling decks have one).
- An agent framework: no memory, planning or prompt templating. The tool
  loop is the only orchestration.

## Decisions

- **JSON in the API's own field names.** Requests and replies are
  `json.Value` documents. Builders (`newRequest`, `withSystem`,
  `addUserText`, `addMessage`, `addReply`, `addToolResult`, `tool`,
  `withStrict`, `addTool`, `addTools`, `setSchema`) and readers (`text`,
  `refusal`, `finishReason`, `toolCalls`, `usage`, `parsed`) cover the
  common parts; anything else is set with `json.set`, so a new API field
  needs no deck release.
- **A surface shared with the sibling decks.** The three LLM decks were
  aligned on purpose: the same builder and reader names, `runTools` /
  `runToolsWith` returning `ToolRun`, `ToolCall` with `id`, `name` and
  parsed `input`, `Usage` with `inputTokens` (cache included),
  `outputTokens`, `totalTokens`, `cachedTokens` and `reasoningTokens`, one
  retry rule, the same tool input cap, and errors with `status`,
  `retryAfterMs` and `limits`. Vendor extras stay: `ToolCall` also has
  `raw` (the arguments as the model wrote them) and `type` (`function` or
  `custom`).
- **`withSystem` writes `system`, not `developer`.** Every compatible
  server knows `system`; `developer` is OpenAI's newer name, so it is
  written with `addMessage`.
- **Tool arguments are model output.** They arrive as a JSON string.
  `toolCalls` parses them into `input`; text that is not a JSON object,
  arguments a server sent as a JSON value instead of a string, and an input
  over the cap give `input` JSON `null`, an error for that call alone. An
  empty string, some servers' way of calling a tool without parameters,
  reads as `{}`.
- **The tool loop.** `runTools` sends, runs each call through a handler
  function in the model's order, adds the results and repeats. A malformed
  call is answered with a `toolError` result, so the model can try again;
  a handler that throws ends the loop with its error unchanged. At
  `maxTurns` the loop runs and answers the last reply's calls, then returns
  with `stopped` set to `"maxTurns"` instead of throwing, so the
  conversation in `request` is valid and can go on. Jennifer has no
  closures, so a handler reaches state through top-level variables or the
  read-only context of `runToolsWith`. `n` other than 1 is refused.
- **`addReply`** keeps what a request may carry: role, content, tool calls,
  a refusal, and `reasoning_content` (DeepSeek™ and others want their
  thinking back within a tool loop). It drops reader-only fields such as
  `annotations`, Ollama's `reasoning` and a tool call's `index`.
- **Embeddings travel as base64.** `embed` asks for `encoding_format`
  `base64`, about a third of the size of JSON numbers and much faster to
  read; `vectors` reads both forms and orders them by `index`.
- **Azure as client variants.** `azure` is the v1 API
  (`<endpoint>/openai/v1`, `api-key` header, no `api-version`). The dated
  API, `azureVersioned`, puts the deployment (the request's `model`) in the
  path and adds `api-version` to every request; `AZURE_API_VERSION` is the
  last dated GA version. A Microsoft™ Entra™ ID token goes as a bearer token
  through `client` and `withBaseUrl`.
- **Retries are the deck's own**, not those of `http.send`, because the
  API's `retry-after-ms` header and the safety rule below need them.

## Errors

Every failure of kind `"openai"` is one struct, `OpenaiError`: `status` (0
when the deck refused locally or no server answered), the error's `type`,
`code` (a numeric code as its digits, as llama.cpp and vLLM send) and
`param`, `requestId` (`x-request-id`, Azure's `apim-request-id`),
`retryAfterMs` (the wait the server named, 0 for none) and `limits` (the
`x-ratelimit-*`, `retry-after` and `retry-after-ms` headers, names
lower-cased). Error bodies are read in OpenAI's shape and in the variants
of compatible servers; a 2xx that holds an `error` object is an error too.

The generic kinds pass through unchanged: `"limit"` (a reply over the cap,
and the nesting and node caps of `json.decode` on a reply or on tool
arguments), `"timeout"`, `"closed"` (a reply cut off mid-way),
`"cancelled"`, and `"net"`, the `net.NetError` the network layer threw.
Callers match `kind` and the fields, never the message.

## Security and limits

- **The key never shows.** It is never in a URL. Server text copied into
  an error has the client's own key masked, in whatever form (Azure, Groq
  and Mistral keys are not `sk-...`), and any other `sk-...` key masked
  too; control and bidi characters are replaced and the text is cut. A
  key or header value holding a control character is refused without
  showing it.
- **Plain http** is allowed only to 127.0.0.1, localhost and [::1] unless
  `withPlainHttp` says otherwise, checked on every request.
- **Caller input in URLs and headers.** A base URL is an absolute http(s)
  URL of plain path segments. An Azure deployment name is letters, digits,
  `.`, `_` and `-`, so it cannot add a segment, a query or a fragment.
  `call` refuses dot segments (also percent-encoded), whitespace, control
  characters, `#` and backslashes. `withHeader` takes token names only,
  refuses the headers the client sets itself, and keeps one header per
  name.
- **No redirects** are followed, so the key never travels to another
  origin.
- **Caps.** A reply is capped at 32 MiB (`withMaxBytes`); a tool input a
  loop hands to a handler at 1 MiB (`withMaxToolInput`), since parsing
  JSON costs up to about 15 times its size in memory. Each attempt has a
  whole-attempt deadline (10 minutes by default, `withTimeout`); a slow
  drip ends there, and the connection is closed.
- **The retry rule.** Retried: 408, 409, 429 and 5xx, and a network
  failure before the whole request was written (`sent` false: a refused
  connection, a failed lookup or TLS handshake, a reset while sending).
  The wait is `retry-after-ms`, else `retry-after` in seconds or as an
  HTTP date, else 0.5 s doubling to 8 s. Never retried: a wait over a
  minute (thrown with `retryAfterMs`), `x-should-retry: false`, a used-up
  quota, a deadline, and any failure after the request was sent (a reset,
  a server closing before or during its reply), since the server may have
  carried it out and a repeated POST could be billed twice. The loop is
  bounded by `withRetries` (0 to 10, default 2) and by `maxTurns`.

## Testing and validation

The suite runs offline against loopback fakes: a scripted HTTP server that
replays recorded replies and records each request, and a raw socket fake
that resets connections or closes them without answering. Fixtures are the
openai-openapi spec's examples and replies recorded from a live Ollama.

A live run against Ollama in a local container (2026-11-14) covered model
listing, chat, two parallel tool calls through the loop, a tool without
arguments, a strict JSON schema, embeddings as floats and base64, the
error shape and the examples. OpenAI itself and Azure were checked only
against the spec and Microsoft's v1 documentation, offline; one live call
to each remains to be made when a key is available.

A validation pass sent hostile replies (bodies of hundreds of megabytes,
endless chunked bodies, a 1 GiB announced length, a negative length, a
slow drip, deep nesting, millions of values, huge `retry-after` values)
and checked that each ends as kind `"limit"`, `"timeout"` or an
`OpenaiError`, and profiled a 100-turn tool loop (linear), a 2 MB reply
and 200 embeddings of 1536 dimensions.

## Known limitations and open questions

- Reading embeddings sent as JSON numbers costs about 2 microseconds per
  number; base64, the default of `embed`, avoids it. A bulk number reader
  in `json` would remove it.
- `toolCalls` takes no client, so it applies the default tool input cap;
  a larger input is read from `raw` with `json.decode` when wanted.
- Multi-turn audio (`audio.id` in the assistant turn) is not carried by
  `addReply`.
- `withTls` accepts `skipVerify` without a warning.

## Dependencies on the interpreter

The deck needs an interpreter at or above its floor, and uses these core
features: the bundled `http` module's byte responses, body cap and its
refusal of injected headers; `task.waitTimeout` and task cancellation for
the deadline; transport failures as `net.NetError` with `sent` and
`replied` (M28.65) for the retry rule; decoder caps thrown as kind
`"limit"` (M28.68); `net.abort` for the tests' real resets. Streaming waits
for the streaming `http` and `sse` work (M30.9); a bulk number reader for
JSON embeddings is M29.8.
