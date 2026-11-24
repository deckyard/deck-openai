<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Chat

`chat(c, request)` sends a Chat Completions request (`POST
/chat/completions`) and returns the reply as a `json.Value`. The request is
a JSON map in the API's own fields; the helpers below build the usual
parts, and `json.set` adds the rest.

## Building a request

```jennifer
def req as json.Value init openai.newRequest("gpt-5.4-mini");
$req = openai.withSystem($req, "You are terse.");
$req = openai.addUserText($req, "Name three prime numbers.");
$req = json.set($req, "/max_completion_tokens", 200);
```

`withSystem` sets the instructions: a `system` message at the start,
replacing a first `system` or `developer` message already there.
`addUserText` adds a user message. `addMessage` takes any of the roles
`system`, `developer`, `user` and `assistant`. `developer` is OpenAI™'s
newer name for `system`, which its reference recommends for o1 and newer
models; `withSystem` writes `system` because every OpenAI-compatible
server knows it, while a local server may refuse `developer`. For OpenAI's
reasoning models write `addMessage($req, "developer", $text)` instead.
A tool result is added with `addToolResult` ([Tools](tools.md)).

Fields worth knowing, set with `json.set`:

| Field | What it does |
|---|---|
| `max_completion_tokens` | the most tokens generated, reasoning included. The older `max_tokens` is deprecated and refused by OpenAI's reasoning models; some local servers know only `max_tokens` |
| `reasoning_effort` | for reasoning models: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max` (not every model takes every value) |
| `temperature`, `top_p` | sampling; reasoning models refuse them |
| `seed` | best-effort repeatable sampling |
| `stop` | up to four stop strings |
| `n` | several choices; the readers here read the first |
| `tool_choice`, `parallel_tool_calls` | see [Tools](tools.md) |
| `prompt_cache_key` | groups requests that share a long prefix, for the prompt cache |
| `safety_identifier` | a stable id of your end user (replaces `user`) |
| `store`, `metadata` | keep the completion for later (`GET /chat/completions/<id>` through `call`) |

A message with images or other content parts is built with `json` and
appended as it is:

```jennifer
def msg as json.Value init json.decode('{"role": "user", "content": [
    {"type": "text", "text": "What is in this picture?"},
    {"type": "image_url", "image_url": {"url": "https://example.org/cat.jpg"}}]}');
$req = json.append($req, "/messages", $msg);
```

## Reading the reply

| Reader | Returns |
|---|---|
| `text(reply)` | the text of the first choice; `""` when the model only called tools or refused. Content sent as a list of parts (Mistral™) is joined from its `text` parts |
| `refusal(reply)` | why the model refused, `""` when it did not |
| `finishReason(reply)` | `stop`, `length`, `tool_calls`, `content_filter` |
| `toolCalls(reply)` | the tool calls, a `list of ToolCall` |
| `usage(reply)` | a `Usage`: input tokens (all of the prompt, cached ones included), output tokens (reasoning included), the total, cached prompt tokens, reasoning tokens |
| `parsed(reply)` | the text decoded as JSON, for structured output |

Anything else is in the reply itself: `json.asString($reply, "/model")`,
`json.get($reply, "/choices/0/logprobs")`.

```jennifer
def reply as json.Value init openai.chat($c, $req);
if (openai.finishReason($reply) == "length") {
    io.printf("(cut off)\n");
}
def u as openai.Usage init openai.usage($reply);
io.printf("%s\n%d tokens, %d of the prompt from the cache\n", openai.text($reply), $u.totalTokens,
    $u.cachedTokens);
```

## A conversation

`addReply` adds the reply's message as the assistant's turn, keeping only
the fields a request carries (role, content, tool calls, refusal), so the
next request goes on from it:

```jennifer
$req = openai.addReply($req, $reply);
$req = openai.addUserText($req, "And three more?");
$reply = openai.chat($c, $req);
```

The API keeps no state between requests: every request carries the whole
conversation, and the prompt cache makes the repeated prefix cheaper.

## Structured output

`setSchema` asks for a reply that is JSON following a JSON Schema
(`response_format` of type `json_schema`); `parsed` decodes it. With
`strict` the output follows the schema exactly; OpenAI then requires
`additionalProperties: false` on every object and every property in
`required` (an optional field is a union with `null`).

```jennifer
def schema as json.Value init json.decode('{"type": "object",
    "properties": {"country": {"type": "string"}, "capital": {"type": "string"}},
    "required": ["country", "capital"], "additionalProperties": false}');
def req as json.Value init openai.setSchema(openai.newRequest("gpt-5.4-mini"), "capital", $schema, true);
$req = openai.addUserText($req, "The capital of France?");
def answer as json.Value init openai.parsed(openai.chat($c, $req));
io.printf("%s\n", json.asString($answer, "/capital"));
```

`parsed` throws `OpenaiError` when the model refused (OpenAI's safety
system answers a structured request it will not fulfil with `refusal`, not
with JSON), when the reply was cut off at the token limit, and when the
text is not JSON. The older JSON mode (`response_format` of type
`json_object`) is set with `json.set` and read with `parsed` too; it
guarantees JSON but no schema. The `jsonschema` deck can check a parsed
reply against the schema where a server does not enforce it.

Ollama™ 0.40.16 follows a strict `json_schema` (checked live); other local
servers differ in which schema features they enforce.
