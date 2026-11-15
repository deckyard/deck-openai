# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# openai - embeddings: the embeddings request and its vectors. Spliced into
# openai.j via include.

/** The most inputs one embeddings request takes (OpenAI's limit). */
export def const MAX_INPUTS as int init 2048;

/**
 * Send an embeddings request (`POST /embeddings`) as it is: `model`,
 * `input` (a string, a list of strings, or token lists), and optionally
 * `dimensions` and `encoding_format`. Read the vectors with `vectors`.
 *
 * @param c {Client} the client
 * @param request {json.Value} the request, a JSON map
 * @return {json.Value} the reply: `data[].embedding`, `usage`
 * @throws {OpenaiError} when the request names no model, the server refuses it, or the reply has no data
 */
export func embeddings(c as Client, request as json.Value) {
    if (json.typeOf($request) != "map" or json.typeOf($request, "/model") != "string" or
        json.asString($request, "/model") == "") {
        fail("embeddings: a request is a JSON map naming a model");
    }
    def model as string init json.asString($request, "/model");
    def what as string init "embeddings " + shown($model);
    def reply as json.Value init send(
        $c,
        "POST",
        urlOf($c, "/embeddings", $model),
        json.encode($request),
        $what);
    listAt($reply, "/data", $what);
    return $reply;
}

/**
 * The vectors of some texts, one per text, in their order. The vectors
 * travel as base64 (`encoding_format`), a third of the size of JSON
 * numbers and much faster to read; a server that ignores the field and
 * sends numbers is read as well.
 *
 * @param c {Client} the client
 * @param model {string} the model, such as `text-embedding-3-small` or `all-minilm`
 * @param inputs {list of string} the texts, 1 to `MAX_INPUTS`, none empty
 * @return {list of list of float} the vectors
 * @throws {OpenaiError} when an input is empty, the server refuses, or the reply does not hold one vector per input
 * @example
 *   def vs as list of list of float init openai.embed($c, "text-embedding-3-small", ["red", "green"]);
 */
export func embed(c as Client, model as string, inputs as list of string) {
    checkRange(len($inputs), 1, MAX_INPUTS, "the number of inputs");
    for (def s in $inputs) {
        if ($s == "") {
            fail("embed: an input is empty");
        }
    }
    def req as json.Value init json.map();
    $req = json.set($req, "/model", $model);
    $req = json.set($req, "/input", $inputs);
    $req = json.set($req, "/encoding_format", "base64");
    def vs as list of list of float init vectors(embeddings($c, $req));
    if (len($vs) != len($inputs)) {
        fail(io.sprintf("embed: %d inputs gave %d vectors", len($inputs), len($vs)));
    }
    return $vs;
}

/**
 * The vectors of an embeddings reply, ordered by their `index`. A vector
 * is a list of numbers, or base64 of little-endian 32-bit floats when the
 * request asked for `encoding_format` `base64`.
 *
 * @param reply {json.Value} the reply of `embeddings`
 * @return {list of list of float} the vectors
 * @throws {OpenaiError} when an entry has no vector, an empty one or one holding something else than numbers, or the indexes are not 0 to n-1 once each
 */
export func vectors(reply as json.Value) {
    def what as string init "vectors";
    def n as int init listAt($reply, "/data", $what);
    # where each index is in the list: -1 until seen
    def order as list of int init [];
    for (def i in 0..$n) {
        $order[] = -1;
    }
    for (def i in 0..$n) {
        def index as int init $i;
        if (json.typeOf($reply, "/data/" + convert.toString($i) + "/index") == "int") {
            $index = json.asInt($reply, "/data/" + convert.toString($i) + "/index");
        }
        if ($index < 0 or $index >= $n or $order[$index] >= 0) {
            fail(io.sprintf("%s: the reply's indexes are not 0 to %d once each", $what, $n - 1));
        }
        $order[$index] = $i;
    }
    def out as list of list of float init [];
    for (def at in $order) {
        $out[] = vectorAt(json.get($reply, "/data/" + convert.toString($at)), $what);
    }
    return $out;
}

/**
 * The vector of one entry: a JSON list of numbers or a base64 string.
 *
 * @param entry {json.Value} the entry, `{"embedding": ..., "index": ...}`
 * @param what {string} the reader, for messages
 * @return {list of float} the vector
 */
func vectorAt(entry as json.Value, what as string) {
    def t as string init json.typeOf($entry, "/embedding");
    if ($t == "string") {
        def raw as bytes init base64Of(json.asString($entry, "/embedding"), $what);
        if (len($raw) == 0 or len($raw) % 4 != 0) {
            fail($what + ": an embedding is not a whole number of 32-bit floats, at least one");
        }
        return binary.readFloats("le", $raw, 0, len($raw) // 4, 4);
    }
    if ($t != "list") {
        fail($what + ": an embedding is " + $t + ", not a vector");
    }
    def e as json.Value init json.get($entry, "/embedding");
    def n as int init json.length($e);
    if ($n == 0) {
        fail($what + ": an embedding is an empty list");
    }
    def v as list of float init [];
    try {
        for (def j in 0..$n) {
            $v[] = json.asFloat($e, "/" + convert.toString($j));
        }
    } catch (err) {
        if (lists.contains(["limit", "timeout", "closed", "cancelled"], $err.kind)) {
            throw $err;
        }
        fail($what + ": an embedding holds something else than numbers");
    }
    return $v;
}

/**
 * Base64 text as bytes.
 *
 * @param text {string} the text
 * @param what {string} the reader, for messages
 * @return {bytes} the bytes
 */
func base64Of(text as string, what as string) {
    try {
        return encoding.fromText("base64", $text);
    } catch (e) {
        fail($what + ": an embedding is not base64");
    }
}
