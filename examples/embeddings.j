#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * Rank texts by meaning:
 *   jennifer run examples/embeddings.j "a fast car" "a quick automobile" "an apple"
 *
 * Embeds every argument and prints how close each one is to the first
 * (cosine similarity). OPENAI_EMBED_MODEL picks the model
 * (text-embedding-3-small by default; all-minilm on Ollama). Same
 * environment as chat.j otherwise.
 */
use io;
use math;
use os;

import "../src/openai.j" as openai;

func cosine(a as list of float, b as list of float) {
    def dot as float init 0.0;
    def na as float init 0.0;
    def nb as float init 0.0;
    for (def i in 0..len($a)) {
        $dot = $dot + $a[$i] * $b[$i];
        $na = $na + $a[$i] * $a[$i];
        $nb = $nb + $b[$i] * $b[$i];
    }
    return $dot / (math.sqrt($na) * math.sqrt($nb));
}

def args as list of string init os.ARGS[1..len(os.ARGS)];
def key as string init os.getEnv("OPENAI_API_KEY");
def base as string init os.getEnv("OPENAI_BASE_URL");
def model as string init os.getEnv("OPENAI_EMBED_MODEL");
if (len($args) < 2 or ($key == "" and $base == "")) {
    io.printf("usage: OPENAI_API_KEY=... [OPENAI_BASE_URL=...] embeddings.j TEXT TEXT...\n");
    exit 0;
}
if ($model == "") {
    $model = "text-embedding-3-small";
}
def c as openai.Client init openai.client($key);
if ($base != "") {
    $c = openai.withBaseUrl($c, $base);
}
try {
    def vs as list of list of float init openai.embed($c, $model, $args);
    io.printf("%d vectors of %d floats\n", len($vs), len($vs[0]));
    for (def i in 1..len($vs)) {
        io.printf("%f|prec=3  %s\n", cosine($vs[0], $vs[$i]), $args[$i]);
    }
} catch (e) {
    io.printf("%s\n", $e.message);
    exit 2;
}
