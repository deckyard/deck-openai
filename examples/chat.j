#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0
# pragma-jennifer-capability: net

/**
 * Ask a model one question: jennifer run examples/chat.j "Why is the sky blue?"
 *
 * OPENAI_API_KEY is the key, OPENAI_BASE_URL another server (such as
 * http://127.0.0.1:11434/v1 for Ollama, which needs no key), OPENAI_MODEL
 * the model (gpt-5.4-mini by default). Prints the answer and the tokens used.
 */
use io;
use json;
use os;

import "../src/openai.j" as openai;

def args as list of string init os.ARGS[1..len(os.ARGS)];
def key as string init os.getEnv("OPENAI_API_KEY");
def base as string init os.getEnv("OPENAI_BASE_URL");
def model as string init os.getEnv("OPENAI_MODEL");
if (len($args) != 1 or ($key == "" and $base == "")) {
    io.printf("usage: OPENAI_API_KEY=... [OPENAI_BASE_URL=...] chat.j QUESTION\n");
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
$req = openai.withSystem($req, "Answer in at most three sentences.");
$req = openai.addUserText($req, $args[0]);
try {
    def reply as json.Value init openai.chat($c, $req);
    if (openai.refusal($reply) != "") {
        io.printf("refused: %s\n", openai.refusal($reply));
        exit 1;
    }
    def u as openai.Usage init openai.usage($reply);
    io.printf(
        "%s\n\n(%d prompt tokens, %d cached; %d generated)\n",
        openai.text($reply),
        $u.inputTokens,
        $u.cachedTokens,
        $u.outputTokens);
} catch (e) {
    io.printf("%s\n", $e.message);
    exit 2;
}
