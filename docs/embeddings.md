<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Embeddings

An embedding is a vector of floats that places a text by meaning: texts
about the same thing have vectors pointing the same way, which is what
semantic search, clustering and deduplication compare.

## Vectors of texts

`embed(c, model, inputs)` returns one vector per text, in their order:

```jennifer
def texts as list of string init ["a fast car", "a quick automobile", "a red apple"];
def vs as list of list of float init openai.embed($c, "text-embedding-3-small", $texts);
io.printf("%d vectors of %d floats\n", len($vs), len($vs[0]));
```

It takes 1 to `MAX_INPUTS` (2048) texts, none empty, and checks that the
reply holds exactly one vector for each. OpenAI also caps a request at
300 000 tokens across its inputs and 8192 per input; split larger batches.

The vectors travel as base64 of 32-bit floats (`encoding_format`:
`base64`), a third of the size of JSON numbers and read in one call
instead of one per number. OpenAI documents it and Ollama honours it
(checked live); a server that ignores the field and sends numbers is read
as well. OpenAI's vectors have length 1, so the cosine similarity of two
is their dot product; other models' may not, so `examples/embeddings.j`
divides by the lengths.

## The request as it is

`embeddings(c, request)` sends a request of your own and returns the
reply; `vectors(reply)` reads its vectors in the order of their `index`.
Use it for `dimensions` (shorter vectors from the `text-embedding-3`
models) or token input:

```jennifer
def req as json.Value init json.decode('{"model": "text-embedding-3-large", "dimensions": 256}');
$req = json.set($req, "/input", ["first text", "second text"]);
def reply as json.Value init openai.embeddings($c, $req);
def vs as list of list of float init openai.vectors($reply);
io.printf("%d tokens\n", openai.usage($reply).inputTokens);
```

## Large batches

A batch of 2048 vectors of 3072 floats is about 25 MB as base64 and about
130 MB as JSON numbers, over the default cap of 32 MiB: raise it with
`openai.withMaxBytes($c, 268435456)` or send smaller batches. Reading
the vectors costs memory too: a `list of float` holds each number as a
Jennifer value, far more than the 4 bytes it took on the wire.
