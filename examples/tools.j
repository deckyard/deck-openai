#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0
# pragma-jennifer-capability: net

/**
 * A tool loop: jennifer run examples/tools.j "Weather in Paris and Berlin?"
 *
 * The model may call `get_weather` (a made-up table here) as often as it
 * likes, several calls at once too; `runTools` runs each through `weather`
 * and sends the results back until the model answers. An unknown city is
 * answered with `toolError`, so the model can recover. The handler counts
 * its calls in a top-level variable: Jennifer has no closures, so that is
 * where a handler keeps state. Same environment as chat.j.
 */
use io;
use json;
use maps;
use os;

import "../src/openai.j" as openai;

def calls as int init 0;

func weather(name as string, input as json.Value) {
    $calls = $calls + 1;
    if ($name != "get_weather" or json.typeOf($input, "/city") != "string") {
        return openai.toolError("unknown tool or no city");
    }
    def city as string init json.asString($input, "/city");
    def table as map of string to int init {"Paris": 18, "Berlin": 11, "Vienna": 15};
    if (not maps.has($table, $city)) {
        return openai.toolError("no weather for " + $city);
    }
    return json.map({"city": $city, "tempC": $table[$city]});
}

def args as list of string init os.ARGS[1..len(os.ARGS)];
def key as string init os.getEnv("OPENAI_API_KEY");
def base as string init os.getEnv("OPENAI_BASE_URL");
def model as string init os.getEnv("OPENAI_MODEL");
if (len($args) != 1 or ($key == "" and $base == "")) {
    io.printf("usage: OPENAI_API_KEY=... [OPENAI_BASE_URL=...] tools.j QUESTION\n");
    exit 0;
}
if ($model == "") {
    $model = "gpt-5.4-mini";
}
def c as openai.Client init openai.client($key);
if ($base != "") {
    $c = openai.withBaseUrl($c, $base);
}
def req as json.Value init openai.newRequest($model);
def schema as json.Value init json.decode('{"type": "object", ' +
    '"properties": {"city": {"type": "string"}}, "required": ["city"], ' +
    '"additionalProperties": false}');
$req = openai.addTool(
    $req,
    openai.withStrict(openai.tool("get_weather", "The current weather of a city", $schema)));
$req = openai.addUserText($req, $args[0]);
try {
    def run as openai.ToolRun init openai.runTools($c, $req, weather, 6);
    if ($run.stopped == "maxTurns") {
        io.printf("(stopped after %d requests, the model still calling tools)\n", $run.turns);
        exit 1;
    }
    io.printf(
        "%s\n\n(%d requests, %d tool calls, the handler ran %d times, %d tokens)\n",
        openai.text($run.reply),
        $run.turns,
        $run.calls,
        $calls,
        $run.usage.totalTokens);
} catch (e) {
    io.printf("%s\n", $e.message);
    exit 2;
}
