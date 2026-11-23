# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# openai - chat: Chat Completions, the builders of a request and the readers
# of a reply. Spliced into openai.j via include.

# a tool or schema name: what the API allows
def const TOOL_NAME as string init '^[A-Za-z0-9_-]{1,64}$';

# the roles addMessage takes; tool results go through addToolResult
def const ROLES as list of string init ["system", "developer", "user", "assistant"];

/**
 * A tool call the model asked for.
 *
 * @field id {string} the call's id, which the tool result names
 * @field name {string} the tool's name
 * @field input {json.Value} a function's arguments parsed, a JSON map; a custom tool's input as a JSON string; JSON `null` when the model wrote something else than a JSON object (malformed arguments) or the input is over the cap (`withMaxToolInput`, for `toolCalls` `DEFAULT_MAX_TOOL_INPUT`)
 * @field raw {string} the arguments as the model wrote them (`function.arguments`), or a custom tool's input
 * @field type {string} `function`, or `custom` for a custom tool (free-text input)
 */
export def struct ToolCall {
    id as string,
    name as string,
    input as json.Value,
    raw as string,
    type as string
};

/**
 * The tokens a request used.
 *
 * @field inputTokens {int} all the tokens of the prompt, those read from the cache included (`prompt_tokens`, which counts them)
 * @field outputTokens {int} the tokens generated, reasoning included (`completion_tokens`, which counts it)
 * @field totalTokens {int} the server's `total_tokens`; when it sends none, `inputTokens + outputTokens`
 * @field cachedTokens {int} the prompt tokens read from the prompt cache (`prompt_tokens_details.cached_tokens`), 0 when the server does not say
 * @field reasoningTokens {int} the generated tokens spent on reasoning (`completion_tokens_details.reasoning_tokens`), 0 when the server does not say
 */
export def struct Usage {
    inputTokens as int,
    outputTokens as int,
    totalTokens as int,
    cachedTokens as int,
    reasoningTokens as int
};

/**
 * Refuse a request that is not a JSON map with a `messages` list.
 *
 * @param request {json.Value} the request
 * @param what {string} the caller, for the message
 */
func checkRequest(request as json.Value, what as string) {
    if (json.typeOf($request) != "map" or json.typeOf($request, "/messages") != "list") {
        fail($what + ": a request is a JSON map with a messages list, as newRequest builds it");
    }
}

/**
 * A Chat Completions request for a model, with no messages yet. Set more
 * fields with `json.set`: `max_completion_tokens`, `temperature`,
 * `reasoning_effort`, `tool_choice`, `parallel_tool_calls`, `seed`, `n`.
 *
 * @param model {string} the model, such as `gpt-5.4-mini`, `qwen2.5:0.5b` or an Azure deployment
 * @return {json.Value} `{"model": model, "messages": []}`
 * @example
 *   def req as json.Value init openai.newRequest("gpt-5.4-mini");
 *   $req = json.set($req, "/max_completion_tokens", 500);
 */
export func newRequest(model as string) {
    if ($model == "") {
        fail("newRequest: the model is empty");
    }
    def req as json.Value init json.map();
    $req = json.set($req, "/model", $model);
    return json.set($req, "/messages", json.list());
}

/**
 * The request with one more text message. `developer` is the newer name of
 * `system` for OpenAI's reasoning models; other servers may know only
 * `system`. A message with images or other parts is built with `json` and
 * added with `json.append($req, "/messages", $msg)`.
 *
 * @param request {json.Value} the request
 * @param role {string} `system`, `developer`, `user` or `assistant`
 * @param content {string} the text
 * @return {json.Value} the request
 */
export func addMessage(request as json.Value, role as string, content as string) {
    checkRequest($request, "addMessage");
    if (not lists.contains(ROLES, $role)) {
        fail("addMessage: the role is system, developer, user or assistant, got " + shown($role));
    }
    def msg as json.Value init json.map();
    $msg = json.set($msg, "/role", $role);
    $msg = json.set($msg, "/content", $content);
    return json.append($request, "/messages", $msg);
}

/**
 * The request with the reply's message added as the assistant's turn,
 * to continue the conversation: its content, tool calls, refusal and
 * `reasoning_content` (the thinking DeepSeek and other servers send, which
 * they want back within a tool loop).
 *
 * @param request {json.Value} the request
 * @param reply {json.Value} the reply of `chat`
 * @return {json.Value} the request
 */
export func addReply(request as json.Value, reply as json.Value) {
    checkRequest($request, "addReply");
    return json.append($request, "/messages", assistantMessage($reply, toolCalls($reply)));
}

/**
 * The request with the result of a tool call added (a `tool` message). A
 * JSON string is sent as its text, anything else as its JSON.
 *
 * @param request {json.Value} the request
 * @param id {string} the tool call's id
 * @param result {json.Value} what the tool returned
 * @return {json.Value} the request
 */
export func addToolResult(request as json.Value, id as string, result as json.Value) {
    checkRequest($request, "addToolResult");
    if ($id == "") {
        fail("addToolResult: the tool call id is empty");
    }
    def text as string init "";
    if (json.typeOf($result) == "string") {
        $text = json.asString($result);
    } else {
        $text = json.encode($result);
    }
    def msg as json.Value init json.map();
    $msg = json.set($msg, "/role", "tool");
    $msg = json.set($msg, "/tool_call_id", $id);
    $msg = json.set($msg, "/content", $text);
    return json.append($request, "/messages", $msg);
}

/**
 * A function tool for `addTool`: its name, what it does, and a JSON Schema
 * of its arguments. Add `withStrict` to make the model follow the schema
 * exactly.
 *
 * @param name {string} the tool's name: 1 to 64 letters, digits, `_` and `-`
 * @param description {string} what it does, for the model; `""` for none
 * @param parameters {json.Value} a JSON Schema of the arguments, an object schema
 * @return {json.Value} `{"type": "function", "function": {name, description, parameters}}`
 * @example
 *   def weather as json.Value init openai.tool("get_weather", "Current weather for a city",
 *       json.decode('{"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}'));
 */
export func tool(name as string, description as string, parameters as json.Value) {
    if (not regex.matches(TOOL_NAME, $name)) {
        fail("tool: a tool name is 1 to 64 letters, digits, _ and -, got " + shown($name));
    }
    if (json.typeOf($parameters) != "map") {
        fail("tool: the parameters of " + shown($name) + " are a JSON Schema map");
    }
    def fn as json.Value init json.map();
    $fn = json.set($fn, "/name", $name);
    if ($description != "") {
        $fn = json.set($fn, "/description", $description);
    }
    $fn = json.set($fn, "/parameters", $parameters);
    def t as json.Value init json.map();
    $t = json.set($t, "/type", "function");
    return json.set($t, "/function", $fn);
}

/**
 * A function tool whose arguments must follow its schema exactly
 * (`strict`, OpenAI's structured outputs). OpenAI then needs
 * `additionalProperties: false` on every object and every property in
 * `required`; an optional one is a union with `null`.
 *
 * @param tool {json.Value} a tool as `tool` builds it
 * @return {json.Value} the tool with `function.strict` true
 * @throws {OpenaiError} when the value is not a function tool
 */
export func withStrict(tool as json.Value) {
    checkTool($tool, false, "withStrict");
    return json.set($tool, "/function/strict", true);
}

/**
 * Refuse a value that is not a function tool (or, where allowed, a custom
 * tool).
 *
 * @param tool {json.Value} the value
 * @param custom {bool} whether a custom tool (`{"type": "custom", "custom": {"name": ...}}`) is allowed
 * @param what {string} the caller, for the message
 */
func checkTool(tool as json.Value, custom as bool, what as string) {
    def t as string init textAt($tool, "/type", $what);
    if ($t == "function" and json.typeOf($tool, "/function/name") == "string") {
        return null;
    }
    if ($custom and $t == "custom" and json.typeOf($tool, "/custom/name") == "string") {
        return null;
    }
    fail($what + ": a tool is a JSON map of type function with a named function, as tool builds it");
}

/**
 * The request offering the model one more tool: a function tool as `tool`
 * builds it, or a custom tool (`{"type": "custom", "custom": {"name": ...}}`)
 * built with `json`.
 *
 * @param request {json.Value} the request
 * @param tool {json.Value} the tool
 * @return {json.Value} the request
 */
export func addTool(request as json.Value, tool as json.Value) {
    checkRequest($request, "addTool");
    checkTool($tool, true, "addTool");
    def req as json.Value init $request;
    if (json.typeOf($req, "/tools") != "list") {
        $req = json.set($req, "/tools", json.list());
    }
    return json.append($req, "/tools", $tool);
}

/**
 * The request offering the model several more tools, in their order.
 *
 * @param request {json.Value} the request
 * @param tools {list of json.Value} the tools, as `tool` builds them
 * @return {json.Value} the request
 */
export func addTools(request as json.Value, tools as list of json.Value) {
    def req as json.Value init $request;
    for (def t in $tools) {
        $req = addTool($req, $t);
    }
    return $req;
}

/**
 * The request with its instructions: a `system` message, first. An
 * existing first `system` or `developer` message is replaced, so calling it
 * again changes the instructions. `system` because every OpenAI-compatible
 * server knows it; `developer` is OpenAI's own newer name, recommended for
 * its reasoning models, and `addMessage(request, "developer", text)` writes
 * one.
 *
 * @param request {json.Value} the request
 * @param text {string} the instructions
 * @return {json.Value} the request
 */
export func withSystem(request as json.Value, text as string) {
    checkRequest($request, "withSystem");
    def msg as json.Value init json.map();
    $msg = json.set($msg, "/role", "system");
    $msg = json.set($msg, "/content", $text);
    def first as string init textAt($request, "/messages/0/role", "withSystem");
    if ($first == "system" or $first == "developer") {
        return json.set($request, "/messages/0", $msg);
    }
    return json.insert($request, "/messages/0", $msg);
}

/**
 * The request with one more user message of text: `addMessage(request,
 * "user", text)`.
 *
 * @param request {json.Value} the request
 * @param text {string} the text
 * @return {json.Value} the request
 */
export func addUserText(request as json.Value, text as string) {
    return addMessage($request, "user", $text);
}

/**
 * The request asking for structured output: the reply's content is JSON
 * following the schema (`response_format` of type `json_schema`). Read it
 * with `parsed`.
 *
 * @param request {json.Value} the request
 * @param name {string} the schema's name: 1 to 64 letters, digits, `_` and `-`
 * @param schema {json.Value} the JSON Schema, an object schema
 * @param strict {bool} whether the output must follow the schema exactly (OpenAI then needs `additionalProperties: false` and every property in `required`)
 * @return {json.Value} the request
 */
export func setSchema(request as json.Value, name as string, schema as json.Value, strict as bool) {
    checkRequest($request, "setSchema");
    if (not regex.matches(TOOL_NAME, $name)) {
        fail("setSchema: a schema name is 1 to 64 letters, digits, _ and -, got " + shown($name));
    }
    if (json.typeOf($schema) != "map") {
        fail("setSchema: the schema is a JSON Schema map");
    }
    def js as json.Value init json.map();
    $js = json.set($js, "/name", $name);
    $js = json.set($js, "/schema", $schema);
    $js = json.set($js, "/strict", $strict);
    def format as json.Value init json.map();
    $format = json.set($format, "/type", "json_schema");
    $format = json.set($format, "/json_schema", $js);
    return json.set($request, "/response_format", $format);
}

/**
 * Send a Chat Completions request (`POST /chat/completions`) and return
 * the reply. Streaming is refused: it needs an SSE reader `http` does not
 * have yet.
 *
 * @param c {Client} the client
 * @param request {json.Value} the request, as `newRequest` and the `add*` functions build it, or any JSON map in the API's fields
 * @return {json.Value} the reply: `choices[].message`, `finish_reason`, `usage`, ...
 * @throws {OpenaiError} when the request is malformed, the server refuses it, or the reply has no choices
 * @example
 *   def reply as json.Value init openai.chat($c, $req);
 *   io.printf("%s\n", openai.text($reply));
 */
export func chat(c as Client, request as json.Value) {
    checkRequest($request, "chat");
    if (json.typeOf($request, "/model") != "string" or json.asString($request, "/model") == "") {
        fail("chat: the request names no model");
    }
    if (json.typeOf($request, "/stream") == "bool" and json.asBool($request, "/stream")) {
        fail("chat: streaming is not supported; leave stream out");
    }
    def model as string init json.asString($request, "/model");
    def what as string init "chat " + shown($model);
    def reply as json.Value init send(
        $c,
        "POST",
        urlOf($c, "/chat/completions", $model),
        json.encode($request),
        $what);
    listAt($reply, "/choices", $what);
    return $reply;
}

/**
 * The pointer of the reply's first choice's message, refused when the
 * reply has none.
 *
 * @param reply {json.Value} the reply
 * @param what {string} the reader, for messages
 * @return {string} `/choices/0/message`
 */
func messageAt(reply as json.Value, what as string) {
    if (listAt($reply, "/choices", $what) == 0) {
        fail($what + ": the reply has no choices");
    }
    if (json.typeOf($reply, "/choices/0/message") != "map") {
        fail($what + ": the reply's first choice has no message");
    }
    return "/choices/0/message";
}

/**
 * The text of the reply (its first choice): `""` when the model only
 * called tools or refused. Content given as a list of parts is joined from
 * its `text` parts.
 *
 * @param reply {json.Value} the reply of `chat`
 * @return {string} the text
 * @throws {OpenaiError} when the reply has no message
 */
export func text(reply as json.Value) {
    def at as string init messageAt($reply, "text") + "/content";
    if (json.typeOf($reply, $at) != "list") {
        return textAt($reply, $at, "text");
    }
    def parts as list of string init [];
    for (def i in 0..json.length($reply, $at)) {
        def p as string init $at + "/" + convert.toString($i);
        if (textAt($reply, $p + "/type", "text") == "text") {
            $parts[] = textAt($reply, $p + "/text", "text");
        }
    }
    return strings.join($parts, "");
}

/**
 * Why the model refused, when it did (`message.refusal`, set by OpenAI's
 * safety system, mostly with structured output).
 *
 * @param reply {json.Value} the reply of `chat`
 * @return {string} the refusal, `""` when the model did not refuse
 */
export func refusal(reply as json.Value) {
    return textAt($reply, messageAt($reply, "refusal") + "/refusal", "refusal");
}

/**
 * Why the model stopped (first choice): `stop`, `length` (out of tokens),
 * `tool_calls`, `content_filter`.
 *
 * @param reply {json.Value} the reply of `chat`
 * @return {string} the reason, `""` when the server does not say
 */
export func finishReason(reply as json.Value) {
    messageAt($reply, "finishReason");
    return textAt($reply, "/choices/0/finish_reason", "finishReason");
}

/**
 * The tool calls the model asked for (first choice), in its order. Several
 * are parallel calls: run them all before the next request. A function's
 * arguments come parsed in `input` (`""` as `{}`); arguments that are not a
 * JSON object (the model's mistake) give `input` JSON `null`, with the text
 * in `raw`, and so do arguments sent as a JSON value instead of a JSON
 * string (`raw` is then that value encoded).
 * So does an input over `DEFAULT_MAX_TOOL_INPUT` bytes (1 MiB), which is
 * not parsed; `json.decode($call.raw)` reads it when wanted.
 *
 * @param reply {json.Value} the reply of `chat`
 * @return {list of ToolCall} the calls, empty when there are none
 * @throws {OpenaiError} when a call is malformed: no id or name, or a type other than function or custom
 * @throws {Error} kind "limit" when arguments nest deeper or hold more values than `json.decode` reads
 */
export func toolCalls(reply as json.Value) {
    return callsOf($reply, DEFAULT_MAX_TOOL_INPUT);
}

/**
 * Whether a tool input is over a number of bytes, without encoding it
 * when its length in characters decides.
 *
 * @param raw {string} the input
 * @param most {int} the most bytes
 * @return {bool} true when it is over
 */
func overInput(raw as string, most as int) {
    if (len($raw) > $most) {
        return true;
    }
    if (len($raw) * 4 <= $most) {
        return false;
    }
    return len(encoding.encode("utf-8", $raw)) > $most;
}

/**
 * The tool calls of a reply, as `toolCalls` reads them, with a cap on the
 * input parsed.
 *
 * @param reply {json.Value} the reply
 * @param most {int} the largest input parsed, in bytes; a larger one gives `input` JSON `null`
 * @return {list of ToolCall} the calls
 */
func callsOf(reply as json.Value, most as int) {
    def what as string init "toolCalls";
    def at as string init messageAt($reply, $what) + "/tool_calls";
    def out as list of ToolCall init [];
    def t as string init json.typeOf($reply, $at);
    if ($t == "missing" or $t == "null") {
        return $out;
    }
    for (def i in 0..listAt($reply, $at, $what)) {
        def p as string init $at + "/" + convert.toString($i);
        def none as json.Value;
        def call as ToolCall init ToolCall{
            id: textAt($reply, $p + "/id", $what),
            name: "",
            input: $none,
            raw: "",
            type: textAt($reply, $p + "/type", $what)
        };
        if ($call.type == "function") {
            $call.name = textAt($reply, $p + "/function/name", $what);
            $call = withArguments($call, $reply, $p + "/function/arguments", $most);
        } elseif ($call.type == "custom") {
            $call.name = textAt($reply, $p + "/custom/name", $what);
            $call.raw = textAt($reply, $p + "/custom/input", $what);
            if (not overInput($call.raw, $most)) {
                $call.input = json.decode(json.encode($call.raw));
            }
        } else {
            fail($what + ": tool call " + convert.toString($i) + " has the type " +
                shown($call.type) +
                ", not function or custom");
        }
        if ($call.id == "" or $call.name == "") {
            fail($what + ": tool call " + convert.toString($i) + " has no id or no name");
        }
        $out[] = $call;
    }
    return $out;
}

/**
 * A function call with its arguments read: `raw` the text, `input` parsed
 * (not past the cap). Arguments sent as a JSON value, not a JSON string,
 * are this call's error alone, answered by the tool loop: `raw` is the
 * value encoded, `input` stays null.
 *
 * @param call {ToolCall} the call, `input` JSON `null`
 * @param reply {json.Value} the reply
 * @param ptr {string} the pointer of the arguments
 * @param most {int} the largest input parsed, in bytes
 * @return {ToolCall} the call
 */
func withArguments(call as ToolCall, reply as json.Value, ptr as string, most as int) {
    def t as string init json.typeOf($reply, $ptr);
    if ($t == "missing") {
        return $call;
    }
    if ($t != "string") {
        $call.raw = json.encode(json.get($reply, $ptr));
        return $call;
    }
    $call.raw = json.asString($reply, $ptr);
    if (not overInput($call.raw, $most)) {
        $call.input = argumentsOf($call.raw);
    }
    return $call;
}

/**
 * A function call's arguments, parsed. They are model output, so text
 * that is not a JSON object is no error here: the tool loop answers it.
 * `""` (some servers' arguments of a tool without parameters) is `{}`.
 * `json.decode` bounds the work: past its nesting or node cap it throws
 * kind "limit", which is passed on.
 *
 * @param raw {string} the arguments as the model wrote them
 * @return {json.Value} the arguments, a JSON map; JSON `null` when they are not a JSON object
 */
func argumentsOf(raw as string) {
    if ($raw == "") {
        return json.map();
    }
    def v as json.Value;
    try {
        $v = json.decode($raw);
    } catch (e) {
        if (lists.contains(GENERIC_KINDS, $e.kind)) {
            throw $e;
        }
        def none as json.Value;
        return $none;
    }
    if (json.typeOf($v) != "map") {
        def none as json.Value;
        return $none;
    }
    return $v;
}

/**
 * The reply's message as the assistant's turn of a request: the role, the
 * content, the tool calls, a refusal and a `reasoning_content` (DeepSeek
 * and others), without the fields a server adds for the reader
 * (`annotations`, `reasoning`, a tool call's `index`).
 *
 * @param reply {json.Value} the reply of `chat`
 * @param calls {list of ToolCall} its tool calls, as `toolCalls` reads them
 * @return {json.Value} the message
 */
func assistantMessage(reply as json.Value, calls as list of ToolCall) {
    def at as string init messageAt($reply, "addReply");
    def msg as json.Value init json.map();
    $msg = json.set($msg, "/role", "assistant");
    if (json.has($reply, $at + "/content")) {
        $msg = json.set($msg, "/content", json.get($reply, $at + "/content"));
    } else {
        $msg = json.set($msg, "/content", json.decode("null"));
    }
    if (len($calls) > 0) {
        def items as list of json.Value init [];
        for (def call in $calls) {
            $items[] = callMessage($call);
        }
        $msg = json.set($msg, "/tool_calls", json.list($items));
    }
    def why as string init refusal($reply);
    if ($why != "") {
        $msg = json.set($msg, "/refusal", $why);
    }
    # DeepSeek's (and other servers') thinking, which a tool loop must send back
    if (json.typeOf($reply, $at + "/reasoning_content") == "string") {
        $msg = json.set(
            $msg,
            "/reasoning_content",
            json.asString($reply, $at + "/reasoning_content"));
    }
    return $msg;
}

/**
 * A tool call as a request carries it.
 *
 * @param call {ToolCall} the call
 * @return {json.Value} `{id, type, function: {name, arguments}}`, or `custom: {name, input}`
 */
func callMessage(call as ToolCall) {
    def fn as json.Value init json.map();
    $fn = json.set($fn, "/name", $call.name);
    def v as json.Value init json.map();
    $v = json.set($v, "/id", $call.id);
    $v = json.set($v, "/type", $call.type);
    if ($call.type == "custom") {
        $fn = json.set($fn, "/input", $call.raw);
        return json.set($v, "/custom", $fn);
    }
    $fn = json.set($fn, "/arguments", $call.raw);
    return json.set($v, "/function", $fn);
}

/**
 * The tokens the request used.
 *
 * @param reply {json.Value} the reply of `chat`, or of `embeddings`
 * @return {Usage} the counts, 0 where the server does not say; `totalTokens` the sum when it does not say
 */
export func usage(reply as json.Value) {
    def what as string init "usage";
    def u as Usage init Usage{
        inputTokens: intAt($reply, "/usage/prompt_tokens", $what),
        outputTokens: intAt($reply, "/usage/completion_tokens", $what),
        totalTokens: intAt($reply, "/usage/total_tokens", $what),
        cachedTokens: intAt($reply, "/usage/prompt_tokens_details/cached_tokens", $what),
        reasoningTokens: intAt($reply, "/usage/completion_tokens_details/reasoning_tokens", $what)
    };
    if (json.typeOf($reply, "/usage/total_tokens") != "int") {
        $u.totalTokens = $u.inputTokens + $u.outputTokens;
    }
    return $u;
}

/**
 * The structured output of a reply to a request with `setSchema` (or
 * `response_format` of type `json_object`): its text, decoded.
 *
 * @param reply {json.Value} the reply of `chat`
 * @return {json.Value} the decoded content
 * @throws {OpenaiError} when the model refused, ran out of tokens (`finish_reason` `length`), or the text is not JSON
 * @throws {Error} kind "limit" when the text nests too deep or holds too many values for `json.decode`
 */
export func parsed(reply as json.Value) {
    def why as string init refusal($reply);
    if ($why != "") {
        fail("parsed: the model refused: " + cleaned($why, 300));
    }
    if (finishReason($reply) == "length") {
        fail("parsed: the reply was cut off at the token limit");
    }
    def content as string init text($reply);
    try {
        return json.decode($content);
    } catch (e) {
        if (lists.contains(GENERIC_KINDS, $e.kind)) {
            throw $e;
        }
        fail("parsed: the reply's text is not JSON: " + shown($content));
    }
}
