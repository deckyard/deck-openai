<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Tools

A model calls a tool by answering with `tool_calls` instead of text: each
call names a function and gives its arguments as a JSON **string**. The
program runs the function, adds the result as a `tool` message, and sends
the conversation again; the model then answers, or calls more tools.

## Offering tools

`tool(name, description, parameters)` builds a function tool whose
arguments are described by a JSON Schema; `addTool(request, tool)` offers
it, `addTools(request, tools)` offers several:

```jennifer
def params as json.Value init json.decode('{"type": "object",
    "properties": {"city": {"type": "string"}, "unit": {"type": ["string", "null"], "enum": ["c", "f", null]}},
    "required": ["city", "unit"], "additionalProperties": false}');
def weather as json.Value init openai.withStrict(openai.tool("get_weather", "The current weather of a city", $params));
$req = openai.addTool($req, $weather);
```

With `withStrict` the model's arguments follow the schema exactly (OpenAI's
structured outputs); the schema then needs `additionalProperties: false`
and every property in `required`, an optional one as a union with `null`.
A tool is a plain `json.Value`, so a list of them can be kept and offered
to many requests; a custom tool (`{"type": "custom", "custom": {"name":
...}}`, free-text input) is built with `json` and added the same way.
Without it the model usually follows the schema, and the `jsonschema` deck
can check the arguments before a tool runs. `tool_choice` (`"auto"`,
`"none"`, `"required"`, or one function) and `parallel_tool_calls` are set
with `json.set`. The `mcp` module's tool definitions use the same JSON
Schemas, so an MCP server's tools can be offered as they are.

## The tool loop

`runTools(c, request, handler, maxTurns)` does the loop: send, run each
call through `handler`, add the results, repeat until a reply calls no
tool. Several calls in one reply (parallel calls) run in the model's order
and all their results go back in the next request.

```jennifer
func weather(name as string, input as json.Value) {
    if ($name != "get_weather") {
        return openai.toolError("no such tool");
    }
    return json.map({"city": json.asString($input, "/city"), "tempC": 18});
}

def run as openai.ToolRun init openai.runTools($c, $req, weather, 8);
io.printf("%s\n", openai.text($run.reply));
io.printf("%d requests, %d tool calls, %d tokens\n", $run.turns, $run.calls, $run.usage.totalTokens);
```

The handler is a function `(name as string, input as json.Value)`
returning a `json.Value`. `input` is the function's arguments, parsed,
always a JSON map (a custom tool's free-text input arrives as a JSON
string). A JSON string result goes back as its text, anything else as its
JSON. The `ToolRun` holds the last reply, the number of requests and calls,
the tokens of all requests summed (`usage`), and the whole conversation as
`request`, the last reply included, so the conversation can go on:

```jennifer
def next as json.Value init openai.addUserText($run.request, "And in Vienna?");
$run = openai.runTools($c, $next, weather, 8);
```

**Failures.** A tool that fails returns `openai.toolError(message)`, the
result `{"error": message}`; the model sees it and can answer or try
again. An error the handler throws ends the loop and reaches the caller
unchanged, with the conversation so far lost. Arguments that are not a JSON
object (a model's malformed output, seen with small models) never reach the
handler: the call is answered with `{"error": "the arguments are not a JSON
object: ..."}` so the model can send it again; arguments a server sent as
a JSON object instead of a JSON string get `{"error": "the arguments came
as a JSON object, not as a JSON string; ..."}`, for that call alone.
Empty arguments (`""`, some servers' way of calling a tool without
parameters) reach the handler as `{}`. Arguments that nest past
`json.decode`'s caps end the loop with kind `"limit"`. Arguments over the
client's cap, `withMaxToolInput(c, bytes)` (1 MiB by default), are not
parsed and are answered with `{"error":
"the input is over N bytes; call the tool again with a smaller input"}`.
`n` other than 1 is refused: the loop follows one choice. A refusal ends
the loop like any reply without tool calls.

**Stopping.** `maxTurns` (1 to `MAX_TURNS`, 100) bounds the requests. A
model still calling tools after that many does not lose the conversation:
the loop runs and answers the last reply's calls, then returns with
`stopped` `"maxTurns"` (a finished loop has `""`). `request` is then a
conversation that can go on, with another `runTools` or a user message:

```jennifer
def run as openai.ToolRun init openai.runTools($c, $req, weather, 8);
if ($run.stopped == "maxTurns") {
    $run = openai.runTools($c, $run.request, weather, 8);
}
```

## Context for a handler

Jennifer has no closures: a handler cannot capture a variable of the
function that starts the loop. It has two ways to its context:

- **The program's top-level variables.** A handler in the program sees
  them and may change them, so it can count calls, collect results or hold
  a connection:

  ```jennifer
  def seen as list of string init [];

  func lookup(name as string, input as json.Value) {
      $seen[] = json.asString($input, "/city");
      return json.map({"tempC": 18});
  }
  ```

- **`runToolsWith(c, request, handler, context, maxTurns)`** hands a
  `json.Value` to every call, as a third argument. A handler declared in a
  module needs it, since a module has no mutable top-level variables. The
  context is read-only; a handler that must keep state across calls in a
  module writes it somewhere that outlives the call (a channel, `kv`, a
  file).

  ```jennifer
  func lookup(name as string, input as json.Value, context as json.Value) {
      def base as string init json.asString($context, "/apiBase");
      return json.map({"from": $base});
  }

  def run as openai.ToolRun init openai.runToolsWith($c, $req, lookup,
      json.map({"apiBase": "https://weather.example.org"}), 8);
  ```

## A loop of your own

`runTools` is a dozen lines over the readers; write the loop by hand to
confirm a call with the user, run calls concurrently, or stop early:

```jennifer
def reply as json.Value init openai.chat($c, $req);
while (len(openai.toolCalls($reply)) > 0) {
    $req = openai.addReply($req, $reply);
    for (def call in openai.toolCalls($reply)) {
        if (json.isNull($call.input)) {
            $req = openai.addToolResult($req, $call.id, openai.toolError("the arguments are not a JSON object"));
        } else {
            $req = openai.addToolResult($req, $call.id, weather($call.name, $call.input));
        }
    }
    $reply = openai.chat($c, $req);
}
```

A `ToolCall` holds the `id`, the tool's `name`, its arguments parsed as
`input` and as the model wrote them as `raw`, and the `type` (`function`,
or `custom` for a custom tool, whose `input` is a JSON string). Arguments
that are not a JSON object (malformed model output) give `input` JSON
`null`. Every tool call a reply holds must be answered before the next
request, or the API refuses it.
