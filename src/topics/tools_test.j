# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# openai - white-box tests for the tool loop. Spliced into openai_test.j via
# include.

/**
 * A tool handler for the tests: the weather of a city, a row count for SQL.
 *
 * @param name {string} the tool
 * @param input {json.Value} its input
 * @return {json.Value} the result
 */
func weatherTool(name as string, input as json.Value) {
    if ($name == "sql") {
        return json.decode('"1 row"');
    }
    if (json.typeOf($input, "/city") != "string") {
        return toolError("no city given");
    }
    def temps as map of string to int init {"Paris": 18, "Berlin": 11};
    def city as string init json.asString($input, "/city");
    return json.map({"city": $city, "tempC": $temps[$city]});
}

/**
 * A tool handler that reads a context.
 *
 * @param name {string} the tool
 * @param input {json.Value} its input
 * @param context {json.Value} the context
 * @return {json.Value} the result
 */
func contextTool(name as string, input as json.Value, context as json.Value) {
    return json.map({
        "city": json.asString($input, "/city"),
        "unit": json.asString($context, "/unit")
    });
}

/**
 * A tool handler that fails.
 *
 * @param name {string} the tool
 * @param input {json.Value} its input
 * @return {json.Value} never
 */
func failingTool(name as string, input as json.Value) {
    throw Error{kind: "boom", message: "the tool broke"};
}

/**
 * A request offering the weather tool.
 *
 * @return {json.Value} the request
 */
func weatherRequest() {
    def req as json.Value init newRequest("qwen2.5:0.5b");
    $req = addTool(
        $req,
        tool("get_weather", "Current weather for a city", json.decode(WEATHER_SCHEMA)));
    return addMessage($req, "user", "What is the weather in Paris and in Berlin?");
}

func testToolLoopOverThreeTurns() {
    def f as Fake init startFake({
        "POST /v1/chat/completions#1": answer(200, TOOLS_OLLAMA),
        "POST /v1/chat/completions#2": answer(200, CUSTOM_AND_BAD),
        "POST /v1/chat/completions#3": answer(200, TOOLS_OLLAMA_DONE)
    });
    def run as ToolRun init runTools(fakeClient($f), weatherRequest(), weatherTool, 5);
    def seen as list of string init stopFake($f);
    testing.assertEqual($run.stopped, "");
    testing.assertEqual($run.turns, 3);
    testing.assertEqual($run.calls, 4);
    testing.assertEqual(len($seen), 3);
    # usage summed over the three replies (the second has none)
    testing.assertEqual(
        $run.usage,
        Usage{
            inputTokens: 415,
            outputTokens: 72,
            totalTokens: 487,
            cachedTokens: 258,
            reasoningTokens: 0
        });
    testing.assertContains(text($run.reply), "In Berlin, it's at 11°C");
    # the second request: the question, the parallel calls, both results in order
    def second as json.Value init bodyOf($seen[1]);
    testing.assertEqual(json.length($second, "/messages"), 4);
    testing.assertEqual(json.asString($second, "/messages/1/tool_calls/1/id"), "call_gdzrooo1");
    testing.assertEqual(
        json.encode(json.get($second, "/messages/2")),
        '{"role":"tool","tool_call_id":"call_zib463ui","content":"{\"city\":\"Paris\",\"tempC\":18}"}');
    testing.assertEqual(
        json.asString($second, "/messages/3/content"),
        '{"city":"Berlin","tempC":11}');
    # the third: the custom call ran, the malformed one got an error result
    def third as json.Value init bodyOf($seen[2]);
    testing.assertEqual(json.length($third, "/messages"), 7);
    testing.assertEqual(json.asString($third, "/messages/5/content"), "1 row");
    testing.assertEqual(json.asString($third, "/messages/6/tool_call_id"), "call_b1");
    testing.assertContains(
        json.asString($third, "/messages/6/content"),
        "the arguments are not a JSON object: not JSON; call the tool again with an object");
    # the run's request holds the final answer too
    testing.assertEqual(json.length($run.request, "/messages"), 8);
    testing.assertEqual(json.asString($run.request, "/messages/7/role"), "assistant");
    testing.assertEqual(json.get($run.request, "/tools"), json.get(weatherRequest(), "/tools"));
}

func testToolErrorReachesTheModel() {
    testing.assertEqual(json.encode(toolError("no such city")), '{"error":"no such city"}');
    def f as Fake init startFake({
        "POST /v1/chat/completions#1": answer(200, TOOLS_DOCS),
        "POST /v1/chat/completions": answer(200, CHAT_DOCS)
    });
    def run as ToolRun init runTools(fakeClient($f), weatherRequest(), weatherTool, 3);
    def seen as list of string init stopFake($f);
    testing.assertEqual($run.turns, 2);
    testing.assertEqual($run.usage.totalTokens, 99 + 29);
    testing.assertEqual(
        json.encode(json.get(bodyOf($seen[1]), "/messages/2")),
        '{"role":"tool","tool_call_id":"call_abc123","content":"{\"error\":\"no city given\"}"}');
}

func testToolLoopStopsAtMaxTurns() {
    def f as Fake init startFake({
        "POST /v1/chat/completions#1": answer(200, TOOLS_OLLAMA),
        "POST /v1/chat/completions#2": answer(200, TOOLS_OLLAMA),
        "POST /v1/chat/completions#3": answer(200, TOOLS_OLLAMA_DONE)
    });
    def c as Client init fakeClient($f);
    def run as ToolRun init runTools($c, weatherRequest(), weatherTool, 2);
    testing.assertEqual($run.stopped, "maxTurns");
    testing.assertEqual($run.turns, 2);
    testing.assertEqual($run.calls, 4);
    testing.assertEqual(len(toolCalls($run.reply)), 2);
    # the last calls are answered: question, 2 x (reply, 2 results)
    testing.assertEqual(json.length($run.request, "/messages"), 7);
    testing.assertEqual(json.asString($run.request, "/messages/6/role"), "tool");
    # and the conversation goes on from there
    def next as ToolRun init runTools($c, $run.request, weatherTool, 2);
    testing.assertEqual($next.stopped, "");
    testing.assertEqual($next.turns, 1);
    testing.assertEqual(json.length(bodyOf(stopFake($f)[2]), "/messages"), 7);
}

func testArgumentsEmptyOrAsAnObject() {
    def at as string init "/choices/0/message/tool_calls/";
    def reply as json.Value init json.set(
        json.set(
            json.decode(TOOLS_OLLAMA),
            $at + "0/function/arguments",
            json.map({"city": "Paris"})),
        $at + "1/function/arguments",
        "");
    def f as Fake init startFake({
        "POST /v1/chat/completions#1": answer(200, json.encode($reply)),
        "POST /v1/chat/completions#2": answer(200, TOOLS_OLLAMA_DONE)
    });
    def run as ToolRun init runTools(fakeClient($f), weatherRequest(), weatherTool, 3);
    def second as json.Value init bodyOf(stopFake($f)[1]);
    testing.assertEqual($run.calls, 2);
    # the object: an error for that call alone, sent back as a string
    testing.assertEqual(
        json.asString($second, "/messages/1/tool_calls/0/function/arguments"),
        '{"city":"Paris"}');
    testing.assertEqual(
        json.asString($second, "/messages/2/content"),
        '{"error":"the arguments came as a JSON object, not as a JSON string; call the tool again"}');
    # "": the handler got {} (and answered that no city was given)
    testing.assertEqual(json.asString($second, "/messages/3/content"), '{"error":"no city given"}');
}

func testToolInputOverTheCap() {
    def big as string init '{"city": "' + strings.replicate("x", 2000) + '"}';
    def reply as json.Value init json.set(
        json.decode(TOOLS_OLLAMA),
        "/choices/0/message/tool_calls/1/function/arguments",
        $big);
    def f as Fake init startFake({
        "POST /v1/chat/completions#1": answer(200, json.encode($reply)),
        "POST /v1/chat/completions#2": answer(200, TOOLS_OLLAMA_DONE)
    });
    def c as Client init withMaxToolInput(fakeClient($f), 1024);
    def run as ToolRun init runTools($c, weatherRequest(), weatherTool, 3);
    def second as json.Value init bodyOf(stopFake($f)[1]);
    testing.assertEqual($run.stopped, "");
    testing.assertEqual($run.calls, 2);
    testing.assertEqual(
        json.asString($second, "/messages/2/content"),
        '{"city":"Paris","tempC":18}');
    testing.assertEqual(
        json.asString($second, "/messages/3/content"),
        '{"error":"the input is over 1024 bytes; call the tool again with a smaller input"}');
    # toolCalls leaves an input over DEFAULT_MAX_TOOL_INPUT unparsed
    def huge as json.Value init json.set(
        $reply,
        "/choices/0/message/tool_calls/1/function/arguments",
        '{"city": "' + strings.replicate("x", DEFAULT_MAX_TOOL_INPUT) + '"}');
    def calls as list of ToolCall init toolCalls($huge);
    testing.assertTrue(json.isNull($calls[1].input));
    testing.assertEqual(len($calls[1].raw), DEFAULT_MAX_TOOL_INPUT + 12);
    testing.assertEqual(
        json.asString(toolCalls($reply)[1].input, "/city"),
        strings.replicate("x", 2000));
    for (def bad in [1023, 1073741825]) {
        try {
            withMaxToolInput($c, $bad);
            missed(convert.toString($bad));
        } catch (e) {
            testing.assertContains($e.message, "the largest tool input must be 1024 to 1073741824");
        }
    }
    testing.assertEqual(client("").maxToolInput, 1048576);
}

func testToolLoopWithContext() {
    def f as Fake init startFake({
        "POST /v1/chat/completions#1": answer(200, TOOLS_OLLAMA),
        "POST /v1/chat/completions": answer(200, TOOLS_OLLAMA_DONE)
    });
    def run as ToolRun init runToolsWith(
        fakeClient($f),
        weatherRequest(),
        contextTool,
        json.map({"unit": "F"}),
        3);
    def seen as list of string init stopFake($f);
    testing.assertEqual($run.turns, 2);
    testing.assertEqual(
        json.asString(bodyOf($seen[1]), "/messages/3/content"),
        '{"city":"Berlin","unit":"F"}');
}

func testToolLoopEndsOnARefusalAndPassesHandlerErrors() {
    def f as Fake init startFake({
        "POST /v1/chat/completions#1": answer(200, REFUSAL),
        "POST /v1/chat/completions": answer(200, TOOLS_OLLAMA)
    });
    def c as Client init fakeClient($f);
    def run as ToolRun init runTools($c, weatherRequest(), weatherTool, 3);
    testing.assertEqual($run.turns, 1);
    testing.assertContains(refusal($run.reply), "I am sorry");
    try {
        runTools($c, weatherRequest(), failingTool, 3);
        missed("a failing tool");
    } catch (e) {
        testing.assertEqual($e.kind, "boom");
    }
    stopFake($f);
}

func testToolLoopRefusesBadSettings() {
    def c as Client init withBaseUrl(client(""), "http://127.0.0.1:9/v1");
    for (def turns in [0, MAX_TURNS + 1]) {
        try {
            runTools($c, weatherRequest(), weatherTool, $turns);
            missed(convert.toString($turns));
        } catch (e) {
            testing.assertContains($e.message, "the turns of a tool loop must be 1 to 100");
        }
    }
    try {
        runTools($c, json.set(weatherRequest(), "/n", 2), weatherTool, 3);
        missed("n = 2");
    } catch (e) {
        testing.assertContains($e.message, "a tool loop follows one choice");
    }
}
