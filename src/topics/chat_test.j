# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# openai - white-box tests for the chat topic. Spliced into openai_test.j via
# include.

# the weather tool's parameters
def const WEATHER_SCHEMA as string init '{"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"], "additionalProperties": false}';

func testBuildersWriteTheApiFields() {
    def req as json.Value init newRequest("gpt-6-astra");
    $req = addMessage($req, "developer", "Be brief.");
    $req = addMessage($req, "user", 'Weather in {Paris}?');
    $req = addTool(
        $req,
        withStrict(tool("get_weather", "Current weather", json.decode(WEATHER_SCHEMA))));
    $req = addTools($req, [tool("now", "", json.decode('{"type": "object", "properties": {}}'))]);
    $req = addToolResult($req, "call_1", json.decode('{"tempC": 18}'));
    $req = addToolResult($req, "call_2", json.decode('"sunny"'));
    $req = json.set($req, "/max_completion_tokens", 300);
    $req = json.set($req, "/reasoning_effort", "low");
    testing.assertEqual(
        json.encode($req),
        '{"model":"gpt-6-astra","messages":[{"role":"developer","content":"Be brief."},{"role":"user","content":"Weather in {Paris}?"},{"role":"tool","tool_call_id":"call_1","content":"{\"tempC\":18}"},{"role":"tool","tool_call_id":"call_2","content":"sunny"}],"tools":[{"type":"function","function":{"name":"get_weather","description":"Current weather","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"],"additionalProperties":false},"strict":true}},{"type":"function","function":{"name":"now","parameters":{"type":"object","properties":{}}}}],"max_completion_tokens":300,"reasoning_effort":"low"}');
    def s as json.Value init setSchema(newRequest("m"), "city", json.decode(WEATHER_SCHEMA), true);
    testing.assertEqual(
        json.encode(json.get($s, "/response_format")),
        '{"type":"json_schema","json_schema":{"name":"city","schema":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"],"additionalProperties":false},"strict":true}}');
}

func testBuildersRefuseMalformedInput() {
    def req as json.Value init newRequest("m");
    def cases as list of string init [
        "role",
        "tool",
        "params",
        "schema",
        "model",
        "id",
        "strict",
        "notatool",
        "system",
        "request"
    ];
    for (def which in $cases) {
        try {
            match ($which) {
                when "role" { addMessage($req, "tool", "x"); }
                when "tool" { tool("get weather", "", json.decode(WEATHER_SCHEMA)); }
                when "params" { tool("w", "", json.decode('[]')); }
                when "strict" {
                    withStrict(json.decode('{"type": "custom", "custom": {"name": "sql"}}'));
                }
                when "notatool" { addTool($req, json.decode('{"name": "w"}')); }
                when "system" { withSystem(json.decode('[]'), "x"); }
                when "schema" { setSchema($req, "bad name", json.decode(WEATHER_SCHEMA), true); }
                when "model" { newRequest(""); }
                when "id" { addToolResult($req, "", json.decode('1')); }
                else { addMessage(json.decode('{"model": "m"}'), "user", "x"); }
            }
            missed($which);
        } catch (e) {
            testing.assertEqual($e.kind, "openai");
        }
    }
}

func testSystemAndUserText() {
    def req as json.Value init addUserText(newRequest("m"), "Hi.");
    $req = withSystem($req, "Be brief.");
    $req = withSystem($req, "Be very brief.");
    testing.assertEqual(
        json.encode(json.get($req, "/messages")),
        '[{"role":"system","content":"Be very brief."},{"role":"user","content":"Hi."}]');
    def dev as json.Value init addMessage(newRequest("m"), "developer", "old");
    testing.assertEqual(
        json.encode(json.get(withSystem($dev, "new"), "/messages")),
        '[{"role":"system","content":"new"}]');
    testing.assertEqual(
        json.encode(json.get(withSystem(newRequest("m"), "only"), "/messages")),
        '[{"role":"system","content":"only"}]');
}

func testCustomToolsAreAccepted() {
    def custom as json.Value init json.decode('{"type": "custom", "custom": {"name": "sql", "description": "SQL"}}');
    testing.assertEqual(json.get(addTool(newRequest("m"), $custom), "/tools/0"), $custom);
}

func testChatSendsTheRequestAndReadsTheReply() {
    def f as Fake init startFake({"POST /v1/chat/completions": answer(200, CHAT_DOCS)});
    def req as json.Value init addMessage(newRequest("gpt-6-astra"), "user", "Hello!");
    def reply as json.Value init chat(fakeClient($f), $req);
    def seen as list of string init stopFake($f);
    testing.assertEqual(
        headOf($seen[0]),
        "POST /v1/chat/completions|Content-Type=application/json|Authorization=Bearer " + KEY);
    testing.assertEqual(bodyOf($seen[0]), $req);
    testing.assertEqual(text($reply), "Hello! How can I assist you today?");
    testing.assertEqual(refusal($reply), "");
    testing.assertEqual(finishReason($reply), "stop");
    testing.assertEqual(len(toolCalls($reply)), 0);
    testing.assertEqual(
        usage($reply),
        Usage{
            inputTokens: 19,
            outputTokens: 10,
            totalTokens: 29,
            cachedTokens: 0,
            reasoningTokens: 0
        });
}

func testChatRefusesBeforeSending() {
    def c as Client init withBaseUrl(client(""), "http://127.0.0.1:9/v1");
    def streaming as json.Value init json.set(
        addMessage(newRequest("m"), "user", "x"),
        "/stream",
        true);
    for (def bad in [
        $streaming,
        json.decode('{"messages": []}'),
        json.decode('{"model": "", "messages": []}'),
        json.decode('[]')
    ]) {
        try {
            chat($c, $bad);
            missed(json.encode($bad));
        } catch (e) {
            testing.assertEqual($e.kind, "openai");
            testing.assertEqual($e.status, 0);
        }
    }
}

func testUsageWithCacheAndReasoning() {
    testing.assertEqual(
        usage(json.decode(REASONING)),
        Usage{
            inputTokens: 1500,
            outputTokens: 900,
            totalTokens: 2400,
            cachedTokens: 1280,
            reasoningTokens: 832
        });
    def u as Usage init usage(json.decode(CHAT_OLLAMA));
    testing.assertEqual($u.totalTokens, 44);
    testing.assertEqual($u.reasoningTokens, 0);
    # no total_tokens: the sum
    $u = usage(json.decode('{"usage": {"prompt_tokens": 7, "completion_tokens": 5}}'));
    testing.assertEqual($u.inputTokens, 7);
    testing.assertEqual($u.outputTokens, 5);
    testing.assertEqual($u.totalTokens, 12);
    testing.assertEqual(usage(json.decode('{}')).totalTokens, 0);
}

func testRefusal() {
    def reply as json.Value init json.decode(REFUSAL);
    testing.assertEqual(refusal($reply), "I am sorry, I cannot assist with that request.");
    testing.assertEqual(text($reply), "");
    try {
        parsed($reply);
        missed("parsed of a refusal");
    } catch (e) {
        testing.assertEqual($e.kind, "openai");
        testing.assertContains($e.message, "parsed: the model refused: I am sorry");
    }
    def again as json.Value init addReply(newRequest("m"), $reply);
    testing.assertEqual(
        json.encode(json.get($again, "/messages/0")),
        '{"role":"assistant","content":null,"refusal":"I am sorry, I cannot assist with that request."}');
}

func testParsedStructuredOutput() {
    testing.assertEqual(
        parsed(json.decode(SCHEMA_OLLAMA)),
        json.decode('{"country": "France", "capital": "Paris"}'));
    try {
        parsed(json.decode(TRUNCATED));
        missed("parsed of a cut-off reply");
    } catch (e) {
        testing.assertContains($e.message, "cut off at the token limit");
    }
    try {
        parsed(json.decode(CHAT_DOCS));
        missed("parsed of prose");
    } catch (e) {
        testing.assertContains($e.message, "parsed: the reply's text is not JSON");
    }
}

func testToolCallsFromTheDocsAndOllama() {
    def calls as list of ToolCall init toolCalls(json.decode(TOOLS_DOCS));
    testing.assertEqual(len($calls), 1);
    testing.assertEqual(
        $calls[0],
        ToolCall{
            id: "call_abc123",
            name: "get_current_weather",
            input: json.map({"location": "Boston, MA"}),
            raw: "\{\n\"location\": \"Boston, MA\"\n\}",
            type: "function"
        });
    testing.assertEqual(text(json.decode(TOOLS_DOCS)), "");
    def two as list of ToolCall init toolCalls(json.decode(TOOLS_OLLAMA));
    testing.assertEqual(len($two), 2);
    testing.assertEqual($two[1].id, "call_gdzrooo1");
    testing.assertEqual(json.asString($two[1].input, "/city"), "Berlin");
    testing.assertEqual(finishReason(json.decode(TOOLS_OLLAMA)), "tool_calls");
}

func testCustomAndMalformedToolCalls() {
    def calls as list of ToolCall init toolCalls(json.decode(CUSTOM_AND_BAD));
    testing.assertEqual($calls[0].type, "custom");
    testing.assertEqual($calls[0].raw, "SELECT 1");
    testing.assertEqual($calls[0].input, json.decode('"SELECT 1"'));
    # malformed arguments are no error here: input is null, raw keeps the text
    testing.assertEqual($calls[1].type, "function");
    testing.assertTrue(json.isNull($calls[1].input));
    testing.assertTrue($calls[1].raw != "");
    def one as json.Value init json.decode(
        '{"choices": [{"message": {"tool_calls": [{"id": "a", "type": "function", "function": {"name": "f", "arguments": ""}}]}}]}');
    def at as string init "/choices/0/message/tool_calls/0/function/arguments";
    for (def odd in ["[1]", "\"x\"", "null", "\{"]) {
        def call as ToolCall init toolCalls(json.set($one, $at, $odd))[0];
        testing.assertTrue(json.isNull($call.input));
        testing.assertEqual($call.raw, $odd);
    }
    # "" (a tool without parameters, some servers) is {}
    testing.assertEqual(toolCalls($one)[0].input, json.map());
    testing.assertEqual(toolCalls($one)[0].raw, "");
    testing.assertEqual(toolCalls(json.set($one, $at, "\{\}"))[0].input, json.map());
    # arguments as a JSON object, not a string: that call's error alone
    def two as json.Value init json.append(
        json.set($one, $at, json.map({"x": 1})),
        "/choices/0/message/tool_calls",
        json.get(json.decode(TOOLS_OLLAMA), "/choices/0/message/tool_calls/0"));
    def calls2 as list of ToolCall init toolCalls($two);
    testing.assertTrue(json.isNull($calls2[0].input));
    testing.assertEqual($calls2[0].raw, '{"x":1}');
    testing.assertEqual(json.asString($calls2[1].input, "/city"), "Paris");
    # a decoder cap on the arguments is kind "limit", passed on
    try {
        toolCalls(json.set($one, $at, strings.repeat("[", 5000)));
        missed("arguments past the nesting cap");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
    }
    for (def bad in [
        '{"choices": [{"message": {"tool_calls": [{"id": "a", "type": "web", "function": {"name": "f"}}]}}]}',
        '{"choices": [{"message": {"tool_calls": [{"id": "", "type": "function", "function": {"name": "f", "arguments": "{}"}}]}}]}'
    ]) {
        try {
            toolCalls(json.decode($bad));
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "openai");
        }
    }
}

func testAddReplyKeepsOnlyTheRequestFields() {
    def req as json.Value init addReply(newRequest("m"), json.decode(TOOLS_OLLAMA));
    testing.assertEqual(
        json.encode(json.get($req, "/messages/0")),
        '{"role":"assistant","content":"","tool_calls":[{"id":"call_zib463ui","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"Paris\"}"}},{"id":"call_gdzrooo1","type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"Berlin\"}"}}]}');
    $req = addReply($req, json.decode(CHAT_DOCS));
    testing.assertEqual(
        json.encode(json.get($req, "/messages/1")),
        '{"role":"assistant","content":"Hello! How can I assist you today?"}');
    $req = addReply($req, json.decode(CUSTOM_AND_BAD));
    testing.assertEqual(
        json.encode(json.get($req, "/messages/2/tool_calls/0")),
        '{"id":"call_c1","type":"custom","custom":{"name":"sql","input":"SELECT 1"}}');
    # DeepSeek's thinking goes back; Ollama's reasoning does not
    def thought as json.Value init json.set(
        json.set(
            json.decode(CHAT_OLLAMA),
            "/choices/0/message/reasoning_content",
            "Paris, surely."),
        "/choices/0/message/reasoning",
        "hm");
    testing.assertEqual(
        json.encode(json.get(addReply(newRequest("m"), $thought), "/messages/0")),
        '{"role":"assistant","content":"The capital of France is Paris.","reasoning_content":"Paris, surely."}');
}

func testContentPartsAndMissingChoices() {
    testing.assertEqual(text(json.decode(PARTS)), "Hello, world");
    testing.assertEqual(
        text(json.decode(TOOLS_OLLAMA_DONE)),
        "The weather in Paris is currently at 18°C with a cloudy sky. In Berlin, it's at 11°C with a rainy sky.");
    for (def bad in [NO_CHOICES, '{"object": "chat.completion"}', '{"choices": [{"index": 0}]}']) {
        try {
            text(json.decode($bad));
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "openai");
        }
    }
    def f as Fake init startFake({"POST /v1/chat/completions": answer(200, '{"id": "x"}')});
    try {
        chat(fakeClient($f), addMessage(newRequest("m"), "user", "x"));
        missed("a reply without choices");
    } catch (e) {
        testing.assertContains($e.message, "the reply's \"/choices\" is missing, not a list");
    }
    stopFake($f);
}
