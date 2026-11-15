<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# openai cheatsheet

Every export of `@deckyard/openai`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/openai/" as openai;
```

A failure throws `OpenaiError` (kind `"openai"`) with the HTTP `status`
(0 when no server answered), the error's `type`, `code` and `param`, and
the `requestId`, the `retryAfterMs` the server asked for and its rate-limit
headers (`limits`); a reply over the cap is kind `"limit"`, a deadline
that passed kind `"timeout"`, a connection
closed mid-reply kind `"closed"`, a cancelled task kind `"cancelled"`. A
`c` argument is a `Client`; a `request` or `reply` is a `json.Value` in
the API's own fields.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `DEFAULT_BASE_URL` | `"https://api.openai.com/v1"` | the OpenAI API |
| `DEFAULT_TIMEOUT_MS` | `600000` | the deadline of one attempt |
| `DEFAULT_RETRIES` | `2` | retries on 408, 409, 429, 5xx, a connection refused or reset |
| `DEFAULT_MAX_BYTES` | `33554432` | the largest reply read |
| `DEFAULT_MAX_TOOL_INPUT` | `1048576` | the largest tool input a tool loop hands to a handler (and `toolCalls` parses) |
| `AZURE_API_VERSION` | `"2024-10-21"` | the last dated GA `api-version` of Azure OpenAI |
| `MAX_TURNS` | `100` | the most requests of one tool loop |
| `MAX_INPUTS` | `2048` | the most texts of one `embed` |

## The client

| Function | Returns | Does |
|---|---|---|
| `client(apiKey)` | `Client` | a client for OpenAI, the key as `Authorization: Bearer`; `""` sends no key |
| `withBaseUrl(c, url)` | `Client` | another OpenAI-compatible server, such as `http://127.0.0.1:11434/v1` |
| `azure(endpoint, apiKey)` | `Client` | Azure OpenAI's v1 API: `<endpoint>/openai/v1`, `api-key` header |
| `azureVersioned(endpoint, apiKey, apiVersion)` | `Client` | Azure OpenAI's dated API: the deployment (the request's `model`) in the path, `api-version` on every request |
| `withOrganization(c, id)` | `Client` | send `OpenAI-Organization` |
| `withProject(c, id)` | `Client` | send `OpenAI-Project` |
| `withHeader(c, name, value)` | `Client` | send one more header (a name given again, in any case, replaces it); the client's own are refused |
| `withPlainHttp(c)` | `Client` | allow plain http to another machine |
| `withTls(c, tls)` | `Client` | certificate options (`caCert`, `skipVerify`) |
| `withTimeout(c, ms)` | `Client` | the deadline of one attempt, 1000 to 86400000 ms |
| `withRetries(c, n)` | `Client` | retries on 408, 409, 429, 5xx, a connection refused or reset, 0 to 10 |
| `withMaxBytes(c, most)` | `Client` | the largest reply, 65536 to 1073741824 bytes |
| `withMaxToolInput(c, most)` | `Client` | the largest tool input a tool loop hands to a handler, 1024 to 1073741824 bytes; a larger one gets a `toolError` |
| `models(c)` | `list of Model` | the models the server offers |
| `call(c, method, path, body)` | `json.Value` | any other request below the base URL; `body` JSON `null` for none |

## Chat

| Function | Returns | Does |
|---|---|---|
| `newRequest(model)` | `json.Value` | `{"model": model, "messages": []}` |
| `withSystem(request, text)` | `json.Value` | set the instructions: a first `system` message, replacing a first `system` or `developer` one |
| `addUserText(request, text)` | `json.Value` | add a user message |
| `addMessage(request, role, content)` | `json.Value` | add a text message: `system`, `developer`, `user`, `assistant` |
| `addReply(request, reply)` | `json.Value` | add the reply's message as the assistant's turn, `reasoning_content` included |
| `addToolResult(request, id, result)` | `json.Value` | add a tool result (`tool` message); a JSON string as its text |
| `tool(name, description, parameters)` | `json.Value` | a function tool with a JSON Schema of its arguments |
| `withStrict(tool)` | `json.Value` | the tool with `strict`: arguments follow the schema exactly |
| `addTool(request, tool)` | `json.Value` | offer one tool (function, or a custom tool built with `json`) |
| `addTools(request, tools)` | `json.Value` | offer several tools |
| `setSchema(request, name, schema, strict)` | `json.Value` | ask for structured output (`response_format` `json_schema`) |
| `chat(c, request)` | `json.Value` | `POST /chat/completions`; streaming is refused |
| `text(reply)` | `string` | the first choice's text, `""` for none |
| `refusal(reply)` | `string` | why the model refused, `""` when it did not |
| `finishReason(reply)` | `string` | `stop`, `length`, `tool_calls`, `content_filter` |
| `toolCalls(reply)` | `list of ToolCall` | the tool calls of the first choice, their arguments parsed (up to `DEFAULT_MAX_TOOL_INPUT`) |
| `usage(reply)` | `Usage` | the tokens used, cached and reasoning tokens included |
| `parsed(reply)` | `json.Value` | the text as JSON; throws on a refusal, a cut-off reply or non-JSON |

## Tools

| Function | Returns | Does |
|---|---|---|
| `runTools(c, request, handler, maxTurns)` | `ToolRun` | the tool loop; `handler(name, input)` returns a `json.Value`; stops after `maxTurns` requests with `stopped` `"maxTurns"` |
| `runToolsWith(c, request, handler, context, maxTurns)` | `ToolRun` | the same, `handler(name, input, context)` gets a read-only context |
| `toolError(message)` | `json.Value` | a result a handler returns to tell the model the call failed: `{"error": message}` |

## Embeddings

| Function | Returns | Does |
|---|---|---|
| `embeddings(c, request)` | `json.Value` | `POST /embeddings` as given |
| `embed(c, model, inputs)` | `list of list of float` | one vector per text, sent as base64 |
| `vectors(reply)` | `list of list of float` | the vectors of a reply in index order, numbers or base64 |

## Types

### `Client`

| Field | Meaning |
|---|---|
| `baseUrl as string` | the API's URL without a trailing slash (`azureVersioned`: the endpoint) |
| `apiKey as string` | the key, `""` for none; do not print a `Client` |
| `keyHeader as string` | `"bearer"` or `"api-key"` |
| `azureVersion as string` | the `api-version` of an `azureVersioned` client, `""` otherwise |
| `organization as string` | the `OpenAI-Organization` header, `""` for none |
| `project as string` | the `OpenAI-Project` header, `""` for none |
| `headers as map of string to string` | more headers for every request |
| `tls as http.TlsOptions` | certificate checks for https |
| `allowPlainHttp as bool` | plain http to another machine allowed |
| `timeoutMs as int` | the deadline of one attempt |
| `retries as int` | retries on 408, 409, 429, 5xx, a connection refused or reset |
| `maxBytes as int` | the largest reply |
| `maxToolInput as int` | the largest tool input a tool loop hands to a handler |

### `OpenaiError`

| Field | Meaning |
|---|---|
| `kind as string` | always `"openai"` |
| `message as string` | `openai: <request>: <why> (HTTP nnn, type ..., code ...)` |
| `status as int` | the HTTP status, 0 when no server answered |
| `type as string` | the error's `type`, `""` when absent |
| `code as string` | the error's `code` (a number as its digits), `""` when absent |
| `param as string` | the request field the error is about, `""` when absent |
| `requestId as string` | `x-request-id` (Azure: `apim-request-id`), `""` when absent |
| `retryAfterMs as int` | the wait the server asked for (`retry-after-ms`, `retry-after` seconds or HTTP date), ms; 0 when none |
| `limits as map of string to string` | the rate-limit headers (`x-ratelimit-*`, `retry-after`, `retry-after-ms`), names lower-cased |

### `Model`

| Field | Meaning |
|---|---|
| `id as string` | the id a request names |
| `created as int` | Unix seconds, 0 when unknown |
| `ownedBy as string` | the owner, `""` when unknown |

### `ToolCall`

| Field | Meaning |
|---|---|
| `id as string` | the call's id, which the result names |
| `name as string` | the tool |
| `input as json.Value` | the arguments parsed (a map); a custom tool's input as a JSON string; JSON `null` when they are not a JSON object or are over the cap |
| `raw as string` | the arguments as the model wrote them (JSON text), or a custom tool's input |
| `type as string` | `function` or `custom` |

### `Usage`

| Field | Meaning |
|---|---|
| `inputTokens as int` | the whole prompt, cached tokens included (`prompt_tokens`) |
| `outputTokens as int` | generated, reasoning included (`completion_tokens`) |
| `totalTokens as int` | `total_tokens`; `inputTokens + outputTokens` when the server sends none |
| `cachedTokens as int` | prompt tokens from the cache |
| `reasoningTokens as int` | generated tokens spent on reasoning |

### `ToolRun`

| Field | Meaning |
|---|---|
| `reply as json.Value` | the last reply: the one without tool calls, or the one the loop stopped at |
| `request as json.Value` | the conversation with every turn, the last reply included |
| `turns as int` | the requests sent |
| `calls as int` | the tool calls run |
| `usage as Usage` | the tokens of all its requests, summed |
| `stopped as string` | `""` when the model finished, `"maxTurns"` when the loop stopped there (the last calls answered, the conversation continuable) |
