# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# openai - tools: the tool loop. Send the request, run every tool call of the
# reply through a handler, add the results, repeat until the model answers
# without calling a tool. Spliced into openai.j via include.

/** The most chat requests one tool loop may send. */
export def const MAX_TURNS as int init 100;

/**
 * What a tool loop ended with.
 *
 * @field reply {json.Value} the last reply, the one without tool calls when the model finished: read it with `text`, `refusal`, `parsed`
 * @field request {json.Value} the request with every turn added: the replies and the tool results, the last reply included; add a message and `chat` it to go on
 * @field turns {int} the chat requests sent
 * @field calls {int} the tool calls run, malformed ones included
 * @field usage {Usage} the tokens of every request of the loop, summed
 * @field stopped {string} `""` when the model finished (a reply without tool calls), `"maxTurns"` when the loop stopped at `maxTurns` with the model still calling tools: `reply` is then the last reply, whose calls were run and answered in `request`
 */
export def struct ToolRun {
    reply as json.Value,
    request as json.Value,
    turns as int,
    calls as int,
    usage as Usage,
    stopped as string
};

/**
 * A tool result telling the model the call failed, for a handler to
 * return: the model sees it and can answer or call again. (A handler that
 * throws ends the loop instead.)
 *
 * @param message {string} what went wrong, for the model
 * @return {json.Value} `{"error": message}`, sent as the tool message's content
 * @example
 *   return openai.toolError("no weather for " + $city);
 */
export func toolError(message as string) {
    return json.map({"error": $message});
}

/**
 * Two token counts added.
 *
 * @param a {Usage} one
 * @param b {Usage} the other
 * @return {Usage} the sum
 */
func sumUsage(a as Usage, b as Usage) {
    return Usage{
        inputTokens: $a.inputTokens + $b.inputTokens,
        outputTokens: $a.outputTokens + $b.outputTokens,
        totalTokens: $a.totalTokens + $b.totalTokens,
        cachedTokens: $a.cachedTokens + $b.cachedTokens,
        reasoningTokens: $a.reasoningTokens + $b.reasoningTokens
    };
}

/**
 * Run a conversation with tools: send the request, run each tool call of
 * the reply through `handler`, add the results, and repeat until the model
 * answers without calling a tool. Parallel calls (several in one reply)
 * run in the model's order.
 *
 * The handler is a function `handler(name as string, input as
 * json.Value)` returning a `json.Value`: a function's arguments as a JSON
 * map, a custom tool's input as a JSON string. Its result goes back to the
 * model, a JSON string as its text, anything else as JSON; to tell the
 * model a tool failed, return `toolError(message)`. An error the handler
 * throws ends the loop and reaches the caller unchanged.
 *
 * Arguments that are not a JSON object are model output, not the
 * program's: the handler is not called and the model gets the result
 * `{"error": "the arguments are not a JSON object: ..."}`, so it can send
 * the call again. So does an input over the client's cap
 * (`withMaxToolInput`, 1 MiB by default): `{"error": "the input is over N
 * bytes; ..."}`. A turn counts against `maxTurns` either way.
 *
 * The loop stops after `maxTurns` requests even when the model still
 * calls tools: it runs and answers the last reply's calls, then returns
 * with `stopped` `"maxTurns"`, so the conversation in `request` can go on
 * (another `runTools` on it, or a user message). A finished loop has
 * `stopped` `""`.
 *
 * Jennifer has no closures: the handler sees the program's top-level
 * variables (and may change them), or takes a context through
 * `runToolsWith`.
 *
 * @param c {Client} the client
 * @param request {json.Value} the request, with its tools (`addTool`)
 * @param handler {func} `func(name as string, input as json.Value)` returning `json.Value`
 * @param maxTurns {int} the most chat requests to send, 1 to `MAX_TURNS`
 * @return {ToolRun} the last reply, the whole conversation, and why it stopped
 * @throws {OpenaiError} as `chat` does
 * @example
 *   func weather(name as string, input as json.Value) {
 *       return json.map({"city": json.asString($input, "/city"), "tempC": 18});
 *   }
 *   def run as openai.ToolRun init openai.runTools($c, $req, weather, 5);
 *   io.printf("%s\n", openai.text($run.reply));
 */
export func runTools(c as Client, request as json.Value, handler as func, maxTurns as int) {
    def none as json.Value;
    return toolLoop($c, $request, $handler, $none, false, $maxTurns);
}

/**
 * `runTools` with a context handed to every call of the handler, for
 * state a handler cannot reach otherwise (one declared in a module, which
 * has no mutable top-level variables): a base URL, a user id, a
 * connection's settings. The handler is `handler(name as string, input as
 * json.Value, context as json.Value)`; the context is read-only.
 *
 * @param c {Client} the client
 * @param request {json.Value} the request, with its tools
 * @param handler {func} `func(name as string, input as json.Value, context as json.Value)` returning `json.Value`
 * @param context {json.Value} the context
 * @param maxTurns {int} the most chat requests to send, 1 to `MAX_TURNS`
 * @return {ToolRun} the last reply, the whole conversation, and why it stopped
 * @throws {OpenaiError} as `chat` does
 */
export func runToolsWith(
    c as Client,
    request as json.Value,
    handler as func,
    context as json.Value,
    maxTurns as int) {
    return toolLoop($c, $request, $handler, $context, true, $maxTurns);
}

/**
 * The tool loop of `runTools` and `runToolsWith`.
 *
 * @param c {Client} the client
 * @param request {json.Value} the request
 * @param handler {func} the handler
 * @param context {json.Value} the context
 * @param withContext {bool} whether the handler takes the context
 * @param maxTurns {int} the most chat requests
 * @return {ToolRun} the result
 */
func toolLoop(
    c as Client,
    request as json.Value,
    handler as func,
    context as json.Value,
    withContext as bool,
    maxTurns as int) {
    checkRange($maxTurns, 1, MAX_TURNS, "the turns of a tool loop");
    checkRequest($request, "runTools");
    if (json.typeOf($request, "/n") == "int" and json.asInt($request, "/n") != 1) {
        fail("runTools: a tool loop follows one choice; leave n out");
    }
    def run as ToolRun init ToolRun{
        reply: $context,
        request: $request,
        turns: 0,
        calls: 0,
        usage: Usage{
            inputTokens: 0,
            outputTokens: 0,
            totalTokens: 0,
            cachedTokens: 0,
            reasoningTokens: 0
        },
        stopped: ""
    };
    while (true) {
        def reply as json.Value init chat($c, $run.request);
        $run.turns = $run.turns + 1;
        $run.usage = sumUsage($run.usage, usage($reply));
        def calls as list of ToolCall init callsOf($reply, $c.maxToolInput);
        $run.request = json.append($run.request, "/messages", assistantMessage($reply, $calls));
        $run.reply = $reply;
        if (len($calls) == 0) {
            return $run;
        }
        for (def call in $calls) {
            def result as json.Value init runCall(
                $call,
                $handler,
                $context,
                $withContext,
                $c.maxToolInput);
            $run.request = addToolResult($run.request, $call.id, $result);
            $run.calls = $run.calls + 1;
        }
        # the calls are answered, so the conversation can go on from here
        if ($run.turns >= $maxTurns) {
            $run.stopped = "maxTurns";
            return $run;
        }
    }
    return $run;
}

/**
 * Run one tool call through the handler, or answer malformed arguments
 * with an error result without calling it.
 *
 * @param call {ToolCall} the call
 * @param handler {func} the handler
 * @param context {json.Value} the context
 * @param withContext {bool} whether the handler takes the context
 * @param most {int} the largest input handed to the handler, in bytes
 * @return {json.Value} the result for the model
 */
func runCall(
    call as ToolCall,
    handler as func,
    context as json.Value,
    withContext as bool,
    most as int) {
    if (overInput($call.raw, $most)) {
        return toolError(io.sprintf(
            "the input is over %d bytes; call the tool again with a smaller input",
            $most));
    }
    if ($call.type == "function" and json.isNull($call.input)) {
        # malformed arguments: say what they were, decoding them again (rare)
        def bad as string init "not JSON";
        try {
            $bad = "a JSON " + json.typeOf(json.decode($call.raw));
        } catch (e) {
            if (lists.contains(GENERIC_KINDS, $e.kind)) {
                throw $e;
            }
        }
        return toolError("the arguments are not a JSON object: " + $bad +
            "; call the tool again with an object");
    }
    if ($withContext) {
        return $handler($call.name, $call.input, $context);
    }
    return $handler($call.name, $call.input);
}
